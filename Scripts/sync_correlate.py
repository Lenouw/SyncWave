#!/usr/bin/env python3
"""
SyncWave correlation engine — called by the Swift app as a subprocess.
Takes raw Float32 PCM files, computes envelope cross-correlation, returns offset in seconds.

Usage: python3 sync_correlate.py <ref.raw> <target.raw> <sample_rate>
Output: JSON with offset_seconds and confidence
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

def envelope(a, win=960, hop=240):
    n = (len(a) - win) // hop + 1
    env = np.zeros(n)
    for i in range(n):
        env[i] = np.sqrt(np.mean(a[i*hop:i*hop+win]**2))
    return env

def normalize(e):
    e = e - np.mean(e)
    s = np.std(e)
    return e / s if s > 1e-10 else e

def correlate_envelopes(ref_path, tgt_path, sr=48000):
    ref = np.fromfile(ref_path, dtype=np.float32)
    tgt = np.fromfile(tgt_path, dtype=np.float32)

    # Preprocess
    pref = preprocess(ref, sr)
    ptgt = preprocess(tgt, sr)

    # Envelope (20ms window, 5ms hop)
    hop = int(sr * 0.005)
    win = int(sr * 0.02)
    eref = normalize(envelope(pref, win, hop))
    etgt = normalize(envelope(ptgt, win, hop))
    env_sr = sr / hop

    # FFT-based cross-correlation
    n = len(eref) + len(etgt)
    nfft = 2**int(np.ceil(np.log2(n)))
    S1 = np.fft.rfft(eref, n=nfft)
    S2 = np.fft.rfft(etgt, n=nfft)
    cross = S2 * np.conj(S1)
    gcc = np.fft.irfft(cross, n=nfft)

    abs_gcc = np.abs(gcc)
    peak_idx = np.argmax(abs_gcc)
    offset = peak_idx - nfft if peak_idx > nfft // 2 else peak_idx
    offset_seconds = offset / env_sr

    # Confidence
    ref_e = np.sum(eref**2)
    tgt_e = np.sum(etgt**2)
    denom = np.sqrt(ref_e * tgt_e)
    confidence = float(abs_gcc[peak_idx] / denom) if denom > 0 else 0.0

    return {
        "offset_seconds": round(float(offset_seconds), 6),
        "confidence": round(min(1.0, confidence), 6),
        "ref_samples": len(ref),
        "tgt_samples": len(tgt),
        "env_ref_pts": len(eref),
        "env_tgt_pts": len(etgt),
        "fft_size": nfft
    }

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Usage: sync_correlate.py <ref.raw> <target.raw> [sample_rate]"}))
        sys.exit(1)

    ref_path = sys.argv[1]
    tgt_path = sys.argv[2]
    sr = int(sys.argv[3]) if len(sys.argv) > 3 else 48000

    try:
        result = correlate_envelopes(ref_path, tgt_path, sr)
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
