import SwiftUI
import AVFoundation

@MainActor
final class AppState: ObservableObject {
    @Published var project = Project()
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0.0
    @Published var statusMessage: String?

    private let syncEngine = SyncEngine()
    private let exportEngine = ExportEngine()

    var hasClips: Bool {
        if project.mode == .multiClip {
            return project.tracks.contains { !$0.clips.isEmpty }
        }
        return !project.clips.isEmpty
    }
    var hasSyncResult: Bool { project.syncResult != nil }

    func setMode(_ mode: ProjectMode) {
        project.mode = mode
        if mode == .multiClip {
            project.tracks = [
                Track(name: "V1", type: .video),
                Track(name: "V2", type: .video),
                Track(name: "A1", type: .audio),
                Track(name: "A2", type: .audio),
                Track(name: "A3", type: .audio),
            ]
        }
    }

    func addTrack(type: Track.TrackType) {
        let existingCount = project.tracks.filter { $0.type == type }.count
        let prefix = type == .video ? "V" : "A"
        let name = "\(prefix)\(existingCount + 1)"
        project.tracks.append(Track(name: name, type: type))
        // Renumber tracks to keep names consistent after deletions
        renumberTracks()
    }

    private func renumberTracks() {
        var videoNum = 1
        var audioNum = 1
        for i in 0..<project.tracks.count {
            if project.tracks[i].type == .video {
                project.tracks[i] = Track(
                    id: project.tracks[i].id, name: "V\(videoNum)",
                    type: .video, clips: project.tracks[i].clips
                )
                videoNum += 1
            } else {
                project.tracks[i] = Track(
                    id: project.tracks[i].id, name: "A\(audioNum)",
                    type: .audio, clips: project.tracks[i].clips
                )
                audioNum += 1
            }
        }
    }

    func removeTrack(id: UUID) {
        project.tracks.removeAll { $0.id == id }
        renumberTracks()
    }

    func importToTrack(trackID: UUID, urls: [URL]) async {
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }

        for url in urls {
            let ext = url.pathExtension.lowercased()
            let videoExts = ["mov", "mp4", "m4v", "mxf", "avi", "mts", "m2ts"]
            let audioExts = ["wav", "aiff", "aif", "mp3", "aac", "m4a"]
            guard videoExts.contains(ext) || audioExts.contains(ext) else { continue }

            let isVideo = videoExts.contains(ext)
            let duration = await getMediaDuration(url: url)
            let hasAudio = await hasAudioTrack(url: url)
            let fps = isVideo ? await getFrameRate(url: url) : 30.0

            let clip = MediaClip(
                url: url, filename: url.lastPathComponent,
                duration: duration, hasAudioTrack: hasAudio,
                audioSampleRate: 48000, isVideo: isVideo,
                frameRate: fps
            )
            project.tracks[trackIndex].clips.append(clip)
        }
    }

    func resetProject() {
        project = Project()
        statusMessage = nil
    }

    func importFiles(urls: [URL]) async {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let videoExts = ["mov", "mp4", "m4v", "mxf", "avi", "mts", "m2ts"]
            let audioExts = ["wav", "aiff", "aif", "mp3", "aac", "m4a"]
            guard videoExts.contains(ext) || audioExts.contains(ext) else { continue }

            let isVideo = videoExts.contains(ext)
            let duration = await getMediaDuration(url: url)
            let hasAudio = await hasAudioTrack(url: url)
            let fps = isVideo ? await getFrameRate(url: url) : 30.0

            let clip = MediaClip(
                url: url, filename: url.lastPathComponent,
                duration: duration, hasAudioTrack: hasAudio,
                audioSampleRate: 48000, isVideo: isVideo,
                frameRate: fps
            )
            project.clips.append(clip)
        }
    }

    func sync() async {
        guard project.clips.count >= 2, let refClip = project.referenceClip else {
            statusMessage = "Minimum 2 clips requis"
            return
        }

        isSyncing = true
        syncProgress = 0
        statusMessage = "Synchronisation en cours..."

        // Reset all clips to 0 progress, mark reference as done
        for i in 0..<project.clips.count {
            project.clips[i].processingProgress = project.clips[i].id == refClip.id ? 1.0 : 0.0
        }

        let targetURLs = project.clips
            .filter { $0.id != refClip.id && $0.canSync }
            .map { (label: $0.filename, url: $0.url) }

        do {
            let result = try await syncEngine.syncFiles(
                referenceURL: refClip.url, targetURLs: targetURLs,
                progress: { [weak self] p, msg in Task { @MainActor in
                    self?.syncProgress = p
                    self?.statusMessage = msg
                    // Update per-clip progress based on message
                    self?.updateClipProgress(message: msg, globalProgress: p, targetCount: targetURLs.count)
                } }
            )

            for alignment in result.alignments {
                if let idx = project.clips.firstIndex(where: { $0.filename == alignment.label }) {
                    project.clips[idx].applySyncResult(
                        offset: alignment.offset, driftPPM: alignment.driftPPM, confidence: alignment.confidence
                    )
                }
            }

            project.syncResult = SyncResult(
                referenceClipID: refClip.id,
                alignments: result.alignments.compactMap { a in
                    guard let clip = project.clips.first(where: { $0.filename == a.label }) else { return nil }
                    return ClipAlignment(clipID: clip.id, offset: a.offset, driftPPM: a.driftPPM, confidence: a.confidence)
                },
                processingTime: result.processingTime
            )
            statusMessage = String(format: "✓ Synchronisation terminée en %.1fs", result.processingTime)
        } catch {
            statusMessage = "✗ Erreur: \(error.localizedDescription)"
        }
        isSyncing = false
    }

    func exportXML(to destination: URL? = nil) async -> URL? {
        guard let syncResult = project.syncResult else { return nil }
        do {
            // Use the reference clip's frame rate for the sequence
            let refFPS = project.referenceClip?.frameRate ?? 30.0
            let seqFrameRate = Int(round(refFPS))
            let xml = try exportEngine.generateFCP7XML(
                clips: project.clips, syncResult: syncResult, settings: project.exportSettings,
                frameRate: seqFrameRate
            )
            if let destination {
                try xml.write(to: destination, atomically: true, encoding: .utf8)
                statusMessage = "✓ Export: \(destination.lastPathComponent)"
                return destination
            } else {
                let url = try exportEngine.exportToFile(xml: xml, directory: project.exportSettings.outputDirectory)
                statusMessage = "✓ Export: \(url.lastPathComponent)"
                return url
            }
        } catch {
            statusMessage = "✗ Export échoué: \(error.localizedDescription)"
            return nil
        }
    }

    private func updateClipProgress(message: String, globalProgress: Double, targetCount: Int) {
        // Match clip by filename in the message
        for i in 0..<project.clips.count {
            let filename = project.clips[i].filename
            if message.contains(filename) {
                if message.contains("✓") || message.contains("synchronisé") {
                    project.clips[i].processingProgress = 1.0
                } else if message.contains("Extraction") {
                    project.clips[i].processingProgress = 0.2
                } else if message.contains("Corrélation") || message.contains("enveloppe") {
                    project.clips[i].processingProgress = 0.5
                } else if message.contains("Affinage") {
                    project.clips[i].processingProgress = 0.7
                } else if message.contains("Drift") {
                    project.clips[i].processingProgress = 0.9
                }
            }
        }
    }

    private func getMediaDuration(url: URL) async -> TimeInterval {
        let asset = AVAsset(url: url)
        return (try? await asset.load(.duration))?.seconds ?? 0
    }

    private func hasAudioTrack(url: URL) async -> Bool {
        let asset = AVAsset(url: url)
        return !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
    }

    private func getFrameRate(url: URL) async -> Double {
        let asset = AVAsset(url: url)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else { return 30.0 }
        let fps = (try? await videoTrack.load(.nominalFrameRate)) ?? 30.0
        return Double(fps)
    }
}
