#!/usr/bin/env python3
"""
SyncWave multi-clip correlation engine.
Groups clips by session (1st clip on each track = session 1, 2nd = session 2, etc.)
then syncs within each session independently.

Usage: python3 sync_multi.py <manifest.json>

Input manifest format:
{
  "tracks": [
    {"name": "V1", "type": "video", "clips": [
      {"id": "uuid1", "path": "/path/to/file.raw", "duration": 2062.0},
      {"id": "uuid2", "path": "/path/to/file.raw", "duration": 1800.0}
    ]},
    {"name": "A1", "type": "audio", "clips": [
      {"id": "uuid3", "path": "/path/to/file.raw", "duration": 2227.0}
    ]}
  ]
}

Output: JSON with timeline positions for each clip.
"""
import sys
import json
import numpy as np
from scipy.signal import butter, filtfilt

def preprocess(a, sr=48000):
    a = a - np.mean(a)
    nyq = sr / 2
    low = min(200 / nyq, 0.99)
    high = min(4000 / nyq, 0.99)
    if low >= high:
        return a
    b, c = butter(4, [low, high], btype='band')
    a = filtfilt(b, c, a)
    rms = np.sqrt(np.mean(a**2))
    return a / rms if rms > 1e-10 else a

def envelope(a, sr=48000, win_ms=20, hop_ms=5):
    win = int(sr * win_ms / 1000)
    hop = int(sr * hop_ms / 1000)
    n = (len(a) - win) // hop + 1
    if n <= 0:
        return np.array([0.0])
    env = np.zeros(n)
    for i in range(n):
        env[i] = np.sqrt(np.mean(a[i*hop:i*hop+win]**2))
    return env

def normalize(e):
    e = e - np.mean(e)
    s = np.std(e)
    return e / s if s > 1e-10 else e

def correlate_pair(ref_env, tgt_env, env_sr):
    n = len(ref_env) + len(tgt_env)
    nfft = 2**int(np.ceil(np.log2(n)))
    S1 = np.fft.rfft(ref_env, n=nfft)
    S2 = np.fft.rfft(tgt_env, n=nfft)
    gcc = np.fft.irfft(S2 * np.conj(S1), n=nfft)
    abs_gcc = np.abs(gcc)
    peak_idx = np.argmax(abs_gcc)
    offset = peak_idx - nfft if peak_idx > nfft // 2 else peak_idx
    offset_seconds = offset / env_sr
    ref_e = np.sum(ref_env**2)
    tgt_e = np.sum(tgt_env**2)
    denom = np.sqrt(ref_e * tgt_e)
    confidence = float(abs_gcc[peak_idx] / denom) if denom > 0 else 0.0
    return offset_seconds, min(1.0, confidence)

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "Usage: sync_multi.py <manifest.json>"}))
        sys.exit(1)

    with open(sys.argv[1]) as f:
        manifest = json.load(f)

    sr = 48000
    env_sr = sr / (sr * 0.005)  # 200 Hz

    tracks = manifest.get("tracks", [])
    if not tracks:
        # Legacy format: flat clips list
        clips = manifest.get("clips", [])
        print(json.dumps({"error": "Legacy format not supported", "positions": []}))
        sys.exit(1)

    # Step 1: Load and preprocess all clips
    sys.stderr.write(f"Loading clips from {len(tracks)} tracks...\n")
    clip_data = {}  # id -> {env, duration, track, name}

    for track in tracks:
        for clip in track["clips"]:
            cid = clip["id"]
            try:
                raw = np.fromfile(clip["path"], dtype=np.float32)
                processed = preprocess(raw, sr)
                env = normalize(envelope(processed, sr))
                name = clip["path"].split("/")[-1]
                clip_data[cid] = {"env": env, "duration": clip["duration"], "track": track["name"], "name": name}
                sys.stderr.write(f"  [{track['name']}] {name}: {clip['duration']:.0f}s, env={len(env)} pts\n")
            except Exception as e:
                sys.stderr.write(f"  [{track['name']}] ERROR: {e}\n")

    # Step 2: Group clips by session
    # Session N = Nth clip on each track
    # Find max number of clips per track
    max_clips_per_track = max((len(t["clips"]) for t in tracks), default=0)
    sys.stderr.write(f"\n{max_clips_per_track} session(s) detected\n")

    sessions = []
    for session_idx in range(max_clips_per_track):
        session_clips = []
        for track in tracks:
            if session_idx < len(track["clips"]):
                clip = track["clips"][session_idx]
                if clip["id"] in clip_data:
                    session_clips.append({
                        "id": clip["id"],
                        "track": track["name"],
                        "duration": clip["duration"]
                    })
        sessions.append(session_clips)
        sys.stderr.write(f"  Session {session_idx+1}: {len(session_clips)} clips\n")

    # Step 3: Sync within each session independently
    positions = {}
    session_end = 0.0  # Running position for chaining sessions
    GAP_BETWEEN_SESSIONS = 120.0  # 2 minutes gap

    for session_idx, session_clips in enumerate(sessions):
        if not session_clips:
            continue

        sys.stderr.write(f"\n=== Syncing session {session_idx+1} ({len(session_clips)} clips) ===\n")

        if len(session_clips) == 1:
            # Only one clip in session — place at session_end
            cid = session_clips[0]["id"]
            positions[cid] = {"offset": session_end, "confidence": 1.0}
            session_end += clip_data[cid]["duration"] + GAP_BETWEEN_SESSIONS
            continue

        # Find anchor: longest clip in this session
        anchor = max(session_clips, key=lambda c: c["duration"])
        anchor_id = anchor["id"]
        positions[anchor_id] = {"offset": session_end, "confidence": 1.0}
        sys.stderr.write(f"  Anchor: {clip_data[anchor_id]['name']} ({anchor['duration']:.0f}s)\n")

        # Correlate each other clip against the anchor
        anchor_env = clip_data[anchor_id]["env"]

        for clip in session_clips:
            if clip["id"] == anchor_id:
                continue

            cid = clip["id"]
            if cid not in clip_data:
                continue

            tgt_env = clip_data[cid]["env"]
            offset, conf = correlate_pair(anchor_env, tgt_env, env_sr)
            # Negate for timeline convention
            timeline_offset = -offset

            # Sanity check
            max_dur = max(anchor["duration"], clip["duration"])
            if abs(timeline_offset) > max_dur:
                sys.stderr.write(f"  {clip_data[cid]['name']}: REJECTED offset={timeline_offset:.1f}s > {max_dur:.0f}s\n")
                positions[cid] = {"offset": session_end, "confidence": 0.0}
                continue

            positions[cid] = {
                "offset": session_end + timeline_offset,
                "confidence": conf
            }
            sys.stderr.write(f"  {clip_data[cid]['name']}: offset={timeline_offset:+.1f}s, conf={conf:.0%}\n")

        # Advance session_end past all clips in this session
        max_end = 0
        for clip in session_clips:
            cid = clip["id"]
            if cid in positions:
                clip_end = positions[cid]["offset"] + clip["duration"]
                max_end = max(max_end, clip_end)
        session_end = max_end + GAP_BETWEEN_SESSIONS

    # Normalize: shift so minimum position = 0
    if positions:
        min_pos = min(p["offset"] for p in positions.values())
        for cid in positions:
            positions[cid]["offset"] -= min_pos

    # Build output
    result = {"positions": []}
    for cid, pos in positions.items():
        result["positions"].append({
            "id": cid,
            "offset_seconds": round(pos["offset"], 6),
            "confidence": round(pos["confidence"], 6)
        })

    sys.stderr.write(f"\nFinal positions:\n")
    for p in sorted(result["positions"], key=lambda x: x["offset_seconds"]):
        name = clip_data.get(p["id"], {}).get("name", p["id"][:8])
        sys.stderr.write(f"  {name}: {p['offset_seconds']:.1f}s (conf={p['confidence']:.0%})\n")

    print(json.dumps(result))

if __name__ == "__main__":
    main()
