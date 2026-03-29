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

    var hasClips: Bool { !project.clips.isEmpty }
    var hasSyncResult: Bool { project.syncResult != nil }

    func importFiles(urls: [URL]) async {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let videoExts = ["mov", "mp4", "m4v", "mxf", "avi", "mts", "m2ts"]
            let audioExts = ["wav", "aiff", "aif", "mp3", "aac", "m4a"]
            guard videoExts.contains(ext) || audioExts.contains(ext) else { continue }

            let isVideo = videoExts.contains(ext)
            let duration = await getMediaDuration(url: url)
            let hasAudio = await hasAudioTrack(url: url)

            let clip = MediaClip(
                url: url, filename: url.lastPathComponent,
                duration: duration, hasAudioTrack: hasAudio,
                audioSampleRate: 48000, isVideo: isVideo
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

        let targetURLs = project.clips
            .filter { $0.id != refClip.id && $0.canSync }
            .map { (label: $0.filename, url: $0.url) }

        do {
            let result = try await syncEngine.syncFiles(
                referenceURL: refClip.url, targetURLs: targetURLs,
                progress: { [weak self] p in Task { @MainActor in self?.syncProgress = p } }
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
            let xml = try exportEngine.generateFCP7XML(
                clips: project.clips, syncResult: syncResult, settings: project.exportSettings
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

    private func getMediaDuration(url: URL) async -> TimeInterval {
        let asset = AVAsset(url: url)
        return (try? await asset.load(.duration))?.seconds ?? 0
    }

    private func hasAudioTrack(url: URL) async -> Bool {
        let asset = AVAsset(url: url)
        return !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
    }
}
