#!/usr/bin/env python3
"""
SyncWave multi-clip correlation engine.
Takes a JSON manifest of clips grouped by track, correlates all pairs
across different tracks, and returns the optimal timeline positions.

Usage: python3 sync_multi.py <manifest.json>

Input manifest format:
{
  "clips": [
    {"id": "uuid1", "path": "/path/to/file.raw", "track": "V1", "duration": 2062.0},
    {"id": "uuid2", "path": "/path/to/file.raw", "track": "A1", "duration": 2227.0},
    ...
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
    """Correlate two normalized envelopes. Returns (offset_seconds, confidence)."""
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

    clips = manifest["clips"]
    sr = 48000
    hop_ms = 5
    env_sr = sr / (sr * hop_ms / 1000)  # 200 Hz

    # Step 1: Load and preprocess all clips
    sys.stderr.write(f"Loading {len(clips)} clips...\n")
    clip_data = {}
    for clip in clips:
        cid = clip["id"]
        try:
            raw = np.fromfile(clip["path"], dtype=np.float32)
            processed = preprocess(raw, sr)
            env = normalize(envelope(processed, sr))
            clip_data[cid] = {"env": env, "track": clip["track"], "duration": clip["duration"]}
            sys.stderr.write(f"  {clip['path'].split('/')[-1]}: {len(raw)/sr:.1f}s, env={len(env)} pts\n")
        except Exception as e:
            sys.stderr.write(f"  ERROR loading {clip['path']}: {e}\n")
            clip_data[cid] = None

    # Step 2: Correlate all pairs across different tracks
    sys.stderr.write("Correlating pairs...\n")
    correlations = []  # (id_a, id_b, offset_seconds, confidence)

    clip_ids = [c["id"] for c in clips if clip_data.get(c["id"]) is not None]

    for i, id_a in enumerate(clip_ids):
        for j, id_b in enumerate(clip_ids):
            if j <= i:
                continue
            # Only correlate clips from DIFFERENT tracks
            if clip_data[id_a]["track"] == clip_data[id_b]["track"]:
                continue

            env_a = clip_data[id_a]["env"]
            env_b = clip_data[id_b]["env"]

            offset, conf = correlate_pair(env_a, env_b, env_sr)
            # Negate for timeline convention
            timeline_offset = -offset

            correlations.append({
                "id_a": id_a,
                "id_b": id_b,
                "offset": round(timeline_offset, 6),  # B starts this many seconds after A
                "confidence": round(conf, 6)
            })
            sys.stderr.write(f"  {id_a[:8]} vs {id_b[:8]}: offset={timeline_offset:.1f}s, conf={conf:.2%}\n")

    # Step 3: Build timeline positions using best correlations
    # Strategy: pick the clip with the most high-confidence correlations as anchor (position 0)
    # Then propagate positions through the graph

    # Find the anchor: clip that has the highest sum of confidences
    conf_sums = {}
    for c in correlations:
        conf_sums[c["id_a"]] = conf_sums.get(c["id_a"], 0) + c["confidence"]
        conf_sums[c["id_b"]] = conf_sums.get(c["id_b"], 0) + c["confidence"]

    if not conf_sums:
        print(json.dumps({"error": "No valid correlations found", "positions": []}))
        sys.exit(0)

    anchor_id = max(conf_sums, key=conf_sums.get)
    sys.stderr.write(f"Anchor: {anchor_id[:8]} (sum conf={conf_sums[anchor_id]:.2f})\n")

    # BFS from anchor to assign positions
    positions = {anchor_id: 0.0}
    confidence_map = {anchor_id: 1.0}

    # Build adjacency list with best correlation per pair
    adj = {}
    for c in correlations:
        key_ab = (c["id_a"], c["id_b"])
        key_ba = (c["id_b"], c["id_a"])

        if key_ab not in adj or c["confidence"] > adj[key_ab][1]:
            adj[key_ab] = (c["offset"], c["confidence"])
        if key_ba not in adj or c["confidence"] > adj[key_ba][1]:
            adj[key_ba] = (-c["offset"], c["confidence"])

    # BFS
    queue = [anchor_id]
    visited = {anchor_id}
    while queue:
        current = queue.pop(0)
        for other_id in clip_ids:
            if other_id in visited:
                continue
            key = (current, other_id)
            if key in adj:
                offset, conf = adj[key]
                if conf > 0.1:  # minimum confidence threshold
                    positions[other_id] = positions[current] + offset
                    confidence_map[other_id] = conf
                    visited.add(other_id)
                    queue.append(other_id)

    # Assign unpositioned clips (no good correlation with anything)
    # Place them in order after the last positioned clip, with 120s gap between sessions
    max_pos = max(positions.values()) if positions else 0
    max_dur = max((clip_data[cid]["duration"] for cid in positions), default=0)
    gap_position = max_pos + max_dur + 120  # 2 min gap

    for cid in clip_ids:
        if cid not in positions:
            positions[cid] = gap_position
            confidence_map[cid] = 0.0
            gap_position += clip_data[cid]["duration"] + 10

    # Normalize: shift so minimum position = 0
    min_pos = min(positions.values()) if positions else 0
    for cid in positions:
        positions[cid] -= min_pos

    # Build output
    result = {
        "anchor": anchor_id,
        "positions": []
    }
    for clip in clips:
        cid = clip["id"]
        if cid in positions:
            result["positions"].append({
                "id": cid,
                "offset_seconds": round(positions[cid], 6),
                "confidence": round(confidence_map.get(cid, 0), 6)
            })

    sys.stderr.write(f"\nTimeline positions:\n")
    for p in sorted(result["positions"], key=lambda x: x["offset_seconds"]):
        cid = p["id"]
        name = next((c["path"].split("/")[-1] for c in clips if c["id"] == cid), cid[:8])
        sys.stderr.write(f"  {name}: {p['offset_seconds']:.1f}s (conf={p['confidence']:.0%})\n")

    print(json.dumps(result))

if __name__ == "__main__":
    main()
