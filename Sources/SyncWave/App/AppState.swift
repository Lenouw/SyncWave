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
        project.tracks.contains { !$0.clips.isEmpty }
    }
    var hasSyncResult: Bool { project.syncResult != nil }

    var canSync: Bool {
        project.tracks.filter { !$0.clips.isEmpty }.count >= 2
    }

    var totalClipCount: Int {
        project.tracks.reduce(0) { $0 + $1.clips.count }
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

    func sync() async {
        // Collect all clips from tracks
        let allClips = project.tracks.flatMap(\.clips)
        project.clips = allClips

        guard allClips.count >= 2 else {
            statusMessage = "Minimum 2 clips requis"
            return
        }

        isSyncing = true
        syncProgress = 0
        statusMessage = "Synchronisation en cours..."

        // Reset all clips to 0 progress
        for i in 0..<project.clips.count {
            project.clips[i].processingProgress = 0
        }

        do {
            // Use multi-clip sync: correlates ALL pairs across tracks
            let result = try await syncEngine.syncTracks(
                tracks: project.tracks,
                progress: { [weak self] p, msg in Task { @MainActor in
                    self?.syncProgress = p
                    self?.statusMessage = msg
                    self?.updateClipProgress(message: msg, globalProgress: p, targetCount: allClips.count)
                } }
            )

            // Apply results to clips
            for alignment in result.alignments {
                if let idx = project.clips.firstIndex(where: { $0.filename == alignment.label }) {
                    project.clips[idx].applySyncResult(
                        offset: alignment.offset, driftPPM: alignment.driftPPM, confidence: alignment.confidence
                    )
                }
            }

            // Find the anchor clip (the one at offset 0 or with highest confidence)
            let anchorClip = project.clips.first(where: { $0.offset == 0 })
                ?? project.clips.max(by: { ($0.confidence ?? 0) < ($1.confidence ?? 0) })

            project.syncResult = SyncResult(
                referenceClipID: anchorClip?.id ?? allClips[0].id,
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
            // Use the first video clip's frame rate, or default 30
            let videoClip = project.clips.first(where: { $0.isVideo })
            let seqFrameRate = Int(round(videoClip?.frameRate ?? 30.0))

            // Ensure all clips have sync data (assign 0 offset to clips without sync results)
            var clipsForExport = project.clips
            for i in 0..<clipsForExport.count {
                if clipsForExport[i].offset == nil {
                    clipsForExport[i].offset = 0
                    clipsForExport[i].confidence = 0
                    clipsForExport[i].syncStatus = .failed
                }
            }

            let xml = try exportEngine.generateFCP7XML(
                clips: clipsForExport, syncResult: syncResult, settings: project.exportSettings,
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
