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
                label: label, offset: result.offsetSeconds, driftPPM: 0, confidence: result.confidence
            ))
        }

        return SyncOutput(alignments: alignments, processingTime: CFAbsoluteTimeGetCurrent() - startTime)
    }

    typealias ProgressCallback = (Double, String) -> Void

    // MARK: - Multi-clip sync pipeline

    /// Multi-clip pipeline: extract all audio → correlate all pairs across tracks → build timeline.
    func syncTracks(
        tracks: [Track],
        progress: ProgressCallback? = nil
    ) async throws -> SyncOutput {
        let startTime = CFAbsoluteTimeGetCurrent()
        let allClips = tracks.flatMap(\.clips)
        guard allClips.count >= 2 else {
            throw NSError(domain: "SyncEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Minimum 2 clips requis"])
        }

        // Phase 1: Extract all clips to raw PCM
        var clipPaths: [(id: String, path: URL, track: String, duration: TimeInterval, filename: String)] = []
        let totalClips = Double(allClips.count)

        for (i, clip) in allClips.enumerated() {
            let p = Double(i) / totalClips * 0.4
            progress?(p, "Extraction audio : \(clip.filename)...")

            let rawPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("syncwave_\(clip.id.uuidString).raw")
            try await extractToRawFile(url: clip.url, output: rawPath)

            let trackName = tracks.first(where: { $0.clips.contains(where: { $0.id == clip.id }) })?.name ?? "?"
            clipPaths.append((
                id: clip.id.uuidString,
                path: rawPath,
                track: trackName,
                duration: clip.duration,
                filename: clip.filename
            ))

            progress?(Double(i + 1) / totalClips * 0.4, "Extraction : \(clip.filename) ✓")
        }

        // Phase 2: Write manifest and run Python multi-clip correlator
        progress?(0.4, "Corrélation de toutes les pistes...")

        let manifest: [String: Any] = [
            "clips": clipPaths.map { [
                "id": $0.id,
                "path": $0.path.path,
                "track": $0.track,
                "duration": $0.duration
            ] as [String: Any] }
        ]

        let manifestPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("syncwave_manifest.json")
        let manifestData = try JSONSerialization.data(withJSONObject: manifest)
        try manifestData.write(to: manifestPath)

        progress?(0.45, "Analyse des correspondances entre pistes...")

        let result = try runPythonMultiSync(manifestPath: manifestPath)

        progress?(0.9, "Calcul des positions timeline...")

        // Phase 3: Build alignments from Python result
        var alignments: [SyncAlignment] = []
        for position in result {
            let filename = clipPaths.first(where: { $0.id == position.id })?.filename ?? position.id
            alignments.append(SyncAlignment(
                label: filename,
                offset: position.offset,
                driftPPM: 0,
                confidence: position.confidence
            ))
        }

        // Cleanup raw files
        for cp in clipPaths {
            try? FileManager.default.removeItem(at: cp.path)
        }
        try? FileManager.default.removeItem(at: manifestPath)

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
            throw NSError(domain: "SyncEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "FFmpeg a échoué sur \(url.lastPathComponent)"])
        }
    }

    /// Run the Python multi-clip correlator.
    private func runPythonMultiSync(manifestPath: URL) throws -> [(id: String, offset: TimeInterval, confidence: Double)] {
        let scriptName = "sync_multi.py"
        let scriptPath = findScript(scriptName)

        let pythonPath = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.fileExists(atPath: $0) }
        guard let python = pythonPath else {
            throw NSError(domain: "SyncEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Python3 non trouvé"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptPath, manifestPath.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle(forWritingAtPath: "/dev/stderr") ?? FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let positions = json["positions"] as? [[String: Any]] else {
            throw NSError(domain: "SyncEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "Résultat Python invalide"])
        }

        return positions.map { pos in
            (
                id: pos["id"] as? String ?? "",
                offset: pos["offset_seconds"] as? Double ?? 0,
                confidence: pos["confidence"] as? Double ?? 0
            )
        }
    }

    /// Find a Python script (in bundle, project, or embedded).
    private func findScript(_ name: String) -> String {
        let execDir = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
        let candidates = [
            Bundle.main.path(forResource: name.replacingOccurrences(of: ".py", with: ""), ofType: "py"),
            execDir + "/../Resources/\(name)",
            FileManager.default.currentDirectoryPath + "/Scripts/\(name)"
        ].compactMap { $0 }

        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(name).path
    }
}
