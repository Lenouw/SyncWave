// Sources/SyncWave/Engine/SyncEngine.swift
import Foundation
import Accelerate

struct SyncAlignment {
    let label: String
    let offset: TimeInterval
    let driftPPM: Double
    let confidence: Double
}

struct SyncOutput {
    let alignments: [SyncAlignment]
    let processingTime: TimeInterval
}

final class SyncEngine {
    private let correlator = GCCPHATCorrelator()
    private let driftCorrector = DriftCorrector()
    private let extractor = AudioExtractor()

    /// Sync audio buffers directly (for testing with synthetic signals).
    func syncBuffers(
        reference: AudioBuffer,
        targets: [(label: String, buffer: AudioBuffer)]
    ) throws -> SyncOutput {
        let startTime = CFAbsoluteTimeGetCurrent()
        var alignments: [SyncAlignment] = []

        for (label, target) in targets {
            let result = try correlator.findOffset(reference: reference, target: target)
            alignments.append(SyncAlignment(
                label: label,
                offset: result.offsetSeconds,
                driftPPM: 0,
                confidence: result.confidence
            ))
        }

        return SyncOutput(
            alignments: alignments,
            processingTime: CFAbsoluteTimeGetCurrent() - startTime
        )
    }

    // MARK: - Progress

    typealias ProgressCallback = (Double, String) -> Void

    // MARK: - Full pipeline

    /// Full pipeline: extract audio → write raw PCM → correlate via Python → return offsets.
    func syncFiles(
        referenceURL: URL,
        targetURLs: [(label: String, url: URL)],
        progress: ProgressCallback? = nil
    ) async throws -> SyncOutput {
        let startTime = CFAbsoluteTimeGetCurrent()
        let n = Double(targetURLs.count)
        var alignments: [SyncAlignment] = []

        // Phase 1: Extract reference audio to raw PCM file
        let refName = referenceURL.lastPathComponent
        progress?(0.05, "Extraction audio : \(refName)...")
        let refRawPath = FileManager.default.temporaryDirectory.appendingPathComponent("syncwave_ref_\(UUID().uuidString).raw")
        try await extractToRawFile(url: referenceURL, output: refRawPath)
        progress?(0.15, "Extraction audio : \(refName) ✓")

        // Phase 2: For each target, extract and correlate
        for (i, (label, url)) in targetURLs.enumerated() {
            let baseProgress = 0.15 + 0.85 * Double(i) / max(1, n)

            // Extract target audio
            progress?(baseProgress, "Extraction audio : \(label)...")
            let tgtRawPath = FileManager.default.temporaryDirectory.appendingPathComponent("syncwave_tgt_\(UUID().uuidString).raw")
            try await extractToRawFile(url: url, output: tgtRawPath)
            progress?(baseProgress + 0.85 / n * 0.3, "Corrélation : \(label)...")

            // Run Python correlation
            let result = try runPythonCorrelation(refPath: refRawPath, tgtPath: tgtRawPath)
            progress?(baseProgress + 0.85 / n * 0.9, "\(label) : offset \(String(format: "%+.1fs", result.offset))...")

            // Negate: Python returns correlation lag (negative = target content starts later in file).
            // For timeline placement, we need the opposite: positive = target placed later.
            let timelineOffset = -result.offset
            alignments.append(SyncAlignment(
                label: label,
                offset: timelineOffset,
                driftPPM: 0,
                confidence: result.confidence
            ))

            // Cleanup target raw file
            try? FileManager.default.removeItem(at: tgtRawPath)
            progress?(baseProgress + 0.85 / n, "\(label) synchronisé ✓")
        }

        // Cleanup reference raw file
        try? FileManager.default.removeItem(at: refRawPath)

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        progress?(1.0, String(format: "Synchronisation terminée en %.1fs", processingTime))

        return SyncOutput(alignments: alignments, processingTime: processingTime)
    }

    // MARK: - Private

    /// Extract audio from a media file to raw Float32 PCM via FFmpeg.
    private func extractToRawFile(url: URL, output: URL) async throws {
        let ffmpegPath = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
            .first { FileManager.default.fileExists(atPath: $0) }

        guard let ffmpeg = ffmpegPath else {
            throw NSError(domain: "SyncEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "FFmpeg non trouvé"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-i", url.path, "-vn", "-ac", "1", "-ar", "48000", "-f", "f32le", "-y", output.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SyncEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "FFmpeg a échoué"])
        }
    }

    /// Run the Python correlation script and parse the JSON result.
    private func runPythonCorrelation(refPath: URL, tgtPath: URL) throws -> (offset: TimeInterval, confidence: Double) {
        // Find the Python script bundled with the app or in the project
        let scriptName = "sync_correlate.py"
        let scriptPath: String

        if let bundlePath = Bundle.main.path(forResource: "sync_correlate", ofType: "py") {
            scriptPath = bundlePath
        } else {
            // Fallback: look in Scripts/ relative to executable
            let execDir = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
            let candidates = [
                execDir + "/../Resources/\(scriptName)",
                execDir + "/../../Scripts/\(scriptName)",
                // Development path
                FileManager.default.currentDirectoryPath + "/Scripts/\(scriptName)"
            ]
            if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                scriptPath = found
            } else {
                // Last resort: write the script to temp
                scriptPath = FileManager.default.temporaryDirectory.appendingPathComponent(scriptName).path
                if !FileManager.default.fileExists(atPath: scriptPath) {
                    try embeddedPythonScript().write(toFile: scriptPath, atomically: true, encoding: .utf8)
                }
            }
        }

        // Find python3
        let pythonPath = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.fileExists(atPath: $0) }
        guard let python = pythonPath else {
            throw NSError(domain: "SyncEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Python3 non trouvé"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptPath, refPath.path, tgtPath.path, "48000"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "SyncEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "Résultat Python invalide"])
        }

        if let error = json["error"] as? String {
            throw NSError(domain: "SyncEngine", code: 5, userInfo: [NSLocalizedDescriptionKey: error])
        }

        let offset = json["offset_seconds"] as? Double ?? 0
        let confidence = json["confidence"] as? Double ?? 0

        return (offset: offset, confidence: confidence)
    }

    /// Embedded Python script as a fallback when the file isn't found.
    private func embeddedPythonScript() -> String {
        """
        #!/usr/bin/env python3
        import sys, json, numpy as np
        from scipy.signal import butter, filtfilt
        def preprocess(a, sr=48000):
            a = a - np.mean(a)
            b, c = butter(4, [200/(sr/2), 4000/(sr/2)], btype='band')
            a = filtfilt(b, c, a)
            rms = np.sqrt(np.mean(a**2))
            return a / rms if rms > 1e-10 else a
        def envelope(a, win=960, hop=240):
            n = (len(a) - win) // hop + 1
            env = np.zeros(n)
            for i in range(n): env[i] = np.sqrt(np.mean(a[i*hop:i*hop+win]**2))
            return env
        def normalize(e):
            e = e - np.mean(e)
            s = np.std(e)
            return e / s if s > 1e-10 else e
        ref = np.fromfile(sys.argv[1], dtype=np.float32)
        tgt = np.fromfile(sys.argv[2], dtype=np.float32)
        sr = int(sys.argv[3]) if len(sys.argv) > 3 else 48000
        hop = int(sr * 0.005); win = int(sr * 0.02)
        eref = normalize(envelope(preprocess(ref, sr), win, hop))
        etgt = normalize(envelope(preprocess(tgt, sr), win, hop))
        env_sr = sr / hop
        n = len(eref) + len(etgt)
        nfft = 2**int(np.ceil(np.log2(n)))
        S1 = np.fft.rfft(eref, n=nfft)
        S2 = np.fft.rfft(etgt, n=nfft)
        gcc = np.fft.irfft(S2 * np.conj(S1), n=nfft)
        abs_gcc = np.abs(gcc)
        peak_idx = np.argmax(abs_gcc)
        offset = peak_idx - nfft if peak_idx > nfft // 2 else peak_idx
        ref_e = np.sum(eref**2); tgt_e = np.sum(etgt**2)
        denom = np.sqrt(ref_e * tgt_e)
        conf = float(abs_gcc[peak_idx] / denom) if denom > 0 else 0.0
        print(json.dumps({"offset_seconds": round(float(offset / env_sr), 6), "confidence": round(min(1.0, conf), 6)}))
        """
    }
}
