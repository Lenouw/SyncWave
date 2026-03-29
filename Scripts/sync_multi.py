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

    # Step 2: Auto-cluster clips into sessions using audio correlation
    # Instead of relying on filename order, correlate ALL video clips against each other.
    # Clips that correlate well (high confidence) = same session.
    # Clips that don't correlate = different sessions.

    all_clip_list = []
    for track in tracks:
        for clip in track["clips"]:
            if clip["id"] in clip_data:
                all_clip_list.append({
                    "id": clip["id"],
                    "track": track["name"],
                    "duration": clip["duration"]
                })

    # Get all video clips for clustering
    video_clip_list = [c for c in all_clip_list if c["track"].startswith("V")]
    audio_clip_list = [c for c in all_clip_list if c["track"].startswith("A")]

    sys.stderr.write(f"\nAuto-clustering {len(video_clip_list)} video clips into sessions...\n")

    # Correlate all video pairs
    MIN_CLUSTER_CONF = 0.3  # minimum confidence to consider clips as same session
    cluster_edges = []
    for i, ca in enumerate(video_clip_list):
        for j, cb in enumerate(video_clip_list):
            if j <= i:
                continue
            if ca["track"] == cb["track"]:
                continue  # same track = different sessions by definition
            env_a = clip_data[ca["id"]]["env"]
            env_b = clip_data[cb["id"]]["env"]
            offset, conf = correlate_pair(env_a, env_b, env_sr)
            name_a = clip_data[ca["id"]]["name"][:20]
            name_b = clip_data[cb["id"]]["name"][:20]
            sys.stderr.write(f"  {name_a} vs {name_b}: conf={conf:.0%}\n")
            if conf >= MIN_CLUSTER_CONF:
                cluster_edges.append((ca["id"], cb["id"], conf))

    # Build clusters using Union-Find
    parent = {c["id"]: c["id"] for c in video_clip_list}
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    for id_a, id_b, conf in cluster_edges:
        union(id_a, id_b)

    # Group into sessions
    clusters = {}
    for c in video_clip_list:
        root = find(c["id"])
        if root not in clusters:
            clusters[root] = []
        clusters[root].append(c)

    # Assign audio clips to sessions by correlating against each session's videos
    video_sessions = list(clusters.values())
    sys.stderr.write(f"\n{len(video_sessions)} session(s) detected from audio clustering\n")
    for i, vs in enumerate(video_sessions):
        names = [clip_data[c["id"]]["name"][:20] for c in vs]
        sys.stderr.write(f"  Session {i+1}: {', '.join(names)}\n")

    # For each audio clip, find which session it belongs to (best correlation with session's videos)
    sessions = []
    for vs in video_sessions:
        session = list(vs)  # start with video clips

        for ac in audio_clip_list:
            best_conf = 0
            for vc in vs:
                env_v = clip_data[vc["id"]]["env"]
                env_a = clip_data[ac["id"]]["env"]
                _, conf = correlate_pair(env_v, env_a, env_sr)
                best_conf = max(best_conf, conf)

            if best_conf >= MIN_CLUSTER_CONF:
                session.append(ac)
                sys.stderr.write(f"  {clip_data[ac['id']]['name'][:25]} → session {len(sessions)+1} ({best_conf:.0%})\n")

        sessions.append(session)

    # Any unassigned audio clips go in a catch-all
    assigned_audio = set()
    for s in sessions:
        for c in s:
            assigned_audio.add(c["id"])
    unassigned = [c for c in audio_clip_list if c["id"] not in assigned_audio]
    if unassigned:
        sys.stderr.write(f"  {len(unassigned)} unassigned audio clips\n")
        # Add to first session as fallback
        if sessions:
            sessions[0].extend(unassigned)

    # Step 3: Sync within each session — CAMERAS FIRST, then audio vs cameras
    # Cameras capture ambient room mix → correlate well with each other.
    # Individual mics capture different people → don't correlate with each other.
    # Strategy: position cameras first, then position audio clips against cameras.
    positions = {}
    session_end = 0.0
    GAP_BETWEEN_SESSIONS = 120.0

    for session_idx, session_clips in enumerate(sessions):
        if not session_clips:
            continue

        sys.stderr.write(f"\n=== Syncing session {session_idx+1} ({len(session_clips)} clips) ===\n")

        if len(session_clips) == 1:
            cid = session_clips[0]["id"]
            positions[cid] = {"offset": session_end, "confidence": 1.0}
            session_end += clip_data[cid]["duration"] + GAP_BETWEEN_SESSIONS
            continue

        # Separate video and audio clips
        video_clips = [c for c in session_clips if clip_data[c["id"]]["track"].startswith("V")]
        audio_clips = [c for c in session_clips if clip_data[c["id"]]["track"].startswith("A")]

        sys.stderr.write(f"  {len(video_clips)} video + {len(audio_clips)} audio clips\n")

        session_positions = {}
        session_confidence = {}

        # --- Phase 1: Correlate cameras with each other ---
        if len(video_clips) >= 2:
            sys.stderr.write(f"  Phase 1: Camera-to-camera correlation\n")
            cam_edges = []
            cam_ids = [c["id"] for c in video_clips]
            for i, id_a in enumerate(cam_ids):
                for j, id_b in enumerate(cam_ids):
                    if j <= i:
                        continue
                    env_a = clip_data[id_a]["env"]
                    env_b = clip_data[id_b]["env"]
                    offset, conf = correlate_pair(env_a, env_b, env_sr)
                    timeline_offset = -offset
                    max_dur = max(clip_data[id_a]["duration"], clip_data[id_b]["duration"])
                    if abs(timeline_offset) > max_dur:
                        continue
                    cam_edges.append((id_a, id_b, timeline_offset, conf))
                    sys.stderr.write(f"    {clip_data[id_a]['name'][:20]} vs {clip_data[id_b]['name'][:20]}: {timeline_offset:+.1f}s, {conf:.0%}\n")

            cam_edges.sort(key=lambda e: e[3], reverse=True)

            # Anchor = best-connected camera
            conf_sums = {}
            for id_a, id_b, _, conf in cam_edges:
                conf_sums[id_a] = conf_sums.get(id_a, 0) + conf
                conf_sums[id_b] = conf_sums.get(id_b, 0) + conf

            anchor_id = max(conf_sums, key=conf_sums.get) if conf_sums else cam_ids[0]
            session_positions[anchor_id] = 0.0
            session_confidence[anchor_id] = 1.0
            sys.stderr.write(f"  Anchor: {clip_data[anchor_id]['name']}\n")

            # Position other cameras via greedy graph
            changed = True
            while changed:
                changed = False
                for id_a, id_b, offset, conf in cam_edges:
                    if id_a in session_positions and id_b not in session_positions:
                        session_positions[id_b] = session_positions[id_a] + offset
                        session_confidence[id_b] = conf
                        sys.stderr.write(f"  → {clip_data[id_b]['name'][:20]}: {session_positions[id_b]:+.1f}s ({conf:.0%})\n")
                        changed = True
                        break
                    elif id_b in session_positions and id_a not in session_positions:
                        session_positions[id_a] = session_positions[id_b] - offset
                        session_confidence[id_a] = conf
                        sys.stderr.write(f"  → {clip_data[id_a]['name'][:20]}: {session_positions[id_a]:+.1f}s ({conf:.0%})\n")
                        changed = True
                        break

        elif len(video_clips) == 1:
            # Single camera = anchor
            cid = video_clips[0]["id"]
            session_positions[cid] = 0.0
            session_confidence[cid] = 1.0
            sys.stderr.write(f"  Single camera anchor: {clip_data[cid]['name']}\n")

        # --- Phase 2: Position audio clips against cameras ---
        positioned_video_ids = [c["id"] for c in video_clips if c["id"] in session_positions]

        if positioned_video_ids and audio_clips:
            sys.stderr.write(f"  Phase 2: Audio-to-camera correlation\n")
            for ac in audio_clips:
                acid = ac["id"]
                best_offset = 0.0
                best_conf = 0.0
                best_via = None

                for vid in positioned_video_ids:
                    env_v = clip_data[vid]["env"]
                    env_a = clip_data[acid]["env"]
                    offset, conf = correlate_pair(env_v, env_a, env_sr)
                    timeline_offset = -offset
                    max_dur = max(clip_data[vid]["duration"], clip_data[acid]["duration"])
                    if abs(timeline_offset) > max_dur:
                        continue
                    if conf > best_conf:
                        best_conf = conf
                        best_offset = session_positions[vid] + timeline_offset
                        best_via = vid

                if best_via:
                    session_positions[acid] = best_offset
                    session_confidence[acid] = best_conf
                    sys.stderr.write(f"  → {clip_data[acid]['name'][:25]}: {best_offset:+.1f}s via {clip_data[best_via]['name'][:15]} ({best_conf:.0%})\n")
                else:
                    session_positions[acid] = 0.0
                    session_confidence[acid] = 0.0
                    sys.stderr.write(f"  ⚠ {clip_data[acid]['name'][:25]}: no match, placed at 0\n")

        # --- Fallback: no video clips, correlate all audio pairs ---
        elif not video_clips and audio_clips:
            sys.stderr.write(f"  Fallback: audio-only session, all-pairs\n")
            all_ids = [c["id"] for c in audio_clips]
            fallback_edges = []
            for i, id_a in enumerate(all_ids):
                for j, id_b in enumerate(all_ids):
                    if j <= i: continue
                    if clip_data[id_a]["track"] == clip_data[id_b]["track"]: continue
                    offset, conf = correlate_pair(clip_data[id_a]["env"], clip_data[id_b]["env"], env_sr)
                    tl = -offset
                    if abs(tl) > max(clip_data[id_a]["duration"], clip_data[id_b]["duration"]): continue
                    fallback_edges.append((id_a, id_b, tl, conf))
            fallback_edges.sort(key=lambda e: e[3], reverse=True)
            if fallback_edges:
                anchor_id = all_ids[0]
                session_positions[anchor_id] = 0.0
                session_confidence[anchor_id] = 1.0
                changed = True
                while changed:
                    changed = False
                    for id_a, id_b, offset, conf in fallback_edges:
                        if id_a in session_positions and id_b not in session_positions:
                            session_positions[id_b] = session_positions[id_a] + offset
                            session_confidence[id_b] = conf; changed = True; break
                        elif id_b in session_positions and id_a not in session_positions:
                            session_positions[id_a] = session_positions[id_b] - offset
                            session_confidence[id_a] = conf; changed = True; break

        # Place any remaining unpositioned clips
        for c in session_clips:
            cid = c["id"]
            if cid not in session_positions:
                session_positions[cid] = 0.0
                session_confidence[cid] = 0.0
                sys.stderr.write(f"  ⚠ {clip_data[cid]['name']}: unpositioned\n")

        # Normalize within session so minimum = 0, then shift by session_end
        min_pos = min(session_positions.values())
        for cid in session_positions:
            positions[cid] = {
                "offset": session_end + session_positions[cid] - min_pos,
                "confidence": session_confidence[cid]
            }

        # Advance session_end
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
