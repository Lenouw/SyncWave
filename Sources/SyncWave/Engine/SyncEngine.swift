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

            let extractStart = CFAbsoluteTimeGetCurrent()
            Logger.shared.info("Extraction start: \(clip.filename)")
            do {
                try await extractToRawFile(url: clip.url, output: rawPath)
            } catch {
                // Skip clips that can't be extracted (corrupted WAV, unsupported format)
                Logger.shared.warn("Extraction failed: \(clip.filename) — \(error.localizedDescription)")
                progress?(Double(i + 1) / totalClips * 0.4, "⚠ \(clip.filename) : extraction échouée, ignoré")
                continue
            }
            let extractDuration = CFAbsoluteTimeGetCurrent() - extractStart
            Logger.shared.info(String(format: "Extraction end: \(clip.filename) (%.2fs)", extractDuration))

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

        // Phase 2: Write manifest in track-based format for session grouping
        progress?(0.4, "Regroupement par session...")

        // Build track-based manifest (clips grouped by track, in order)
        var trackManifest: [[String: Any]] = []
        for track in tracks {
            let trackClips: [[String: Any]] = track.clips.compactMap { clip in
                guard let cp = clipPaths.first(where: { $0.id == clip.id.uuidString }) else { return nil }
                return [
                    "id": cp.id,
                    "path": cp.path.path,
                    "duration": cp.duration
                ] as [String: Any]
            }
            if !trackClips.isEmpty {
                trackManifest.append([
                    "name": track.name,
                    "type": track.type.rawValue,
                    "clips": trackClips
                ] as [String: Any])
            }
        }

        let manifest: [String: Any] = ["tracks": trackManifest]

        let manifestPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("syncwave_manifest.json")
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
        try manifestData.write(to: manifestPath)
        Logger.shared.info("Manifest written to: \(manifestPath.path)")

        progress?(0.45, "Analyse des correspondances entre pistes...")

        let result = try runPythonMultiSync(manifestPath: manifestPath)

        progress?(0.9, "Calcul des positions timeline...")

        // Phase 3: Build alignments from Python result
        var alignments: [SyncAlignment] = []
        for position in result {
            let filename = clipPaths.first(where: { $0.id == position.id })?.filename ?? position.id
            Logger.shared.info(String(format: "Alignment: \(filename) offset=%.4fs confidence=%.3f", position.offset, position.confidence))
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
        Logger.shared.info(String(format: "SyncEngine.syncTracks completed in %.2fs (%d alignments)", processingTime, alignments.count))
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
        let scriptPath = try findScript(scriptName)
        Logger.shared.info("Python script: \(scriptPath)")

        let pythonPath = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { FileManager.default.fileExists(atPath: $0) }
        guard let python = pythonPath else {
            Logger.shared.error("Python3 not found in expected paths")
            throw NSError(domain: "SyncEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Python3 non trouvé"])
        }
        Logger.shared.info("Python interpreter: \(python)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptPath, manifestPath.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        // Read pipes BEFORE waitUntilExit to avoid deadlock if output exceeds pipe buffer (64KB)
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if let stdoutStr = String(data: data, encoding: .utf8), !stdoutStr.isEmpty {
            Logger.shared.info("Python stdout: \(stdoutStr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if let stderrStr = String(data: stderrData, encoding: .utf8), !stderrStr.isEmpty {
            Logger.shared.warn("Python stderr: \(stderrStr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let positions = json["positions"] as? [[String: Any]] else {
            Logger.shared.error("Invalid Python result (exit code: \(process.terminationStatus))")
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
    private func findScript(_ name: String) throws -> String {
        let execDir = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
        let candidates = [
            Bundle.main.path(forResource: name.replacingOccurrences(of: ".py", with: ""), ofType: "py"),
            execDir + "/../Resources/\(name)",
            FileManager.default.currentDirectoryPath + "/Scripts/\(name)"
        ].compactMap { $0 }

        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            Logger.shared.error("Script Python \(name) introuvable dans : \(candidates)")
            throw NSError(domain: "SyncEngine", code: 6, userInfo: [NSLocalizedDescriptionKey: "Script \(name) introuvable. Réinstallez SyncWave."])
        }
        return path
    }
}
