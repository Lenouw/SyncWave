import Foundation

enum ProjectMode: Equatable {
    case none       // Not chosen yet (show WelcomeView)
    case simple     // Sync rapide
    case multiClip  // Multi-clips with tracks
}

struct Track: Identifiable, Equatable {
    let id: UUID
    let name: String        // "V1", "V2", "A1", "A2"...
    let type: TrackType
    var clips: [MediaClip]

    enum TrackType: String, Equatable { case video, audio }

    init(id: UUID = UUID(), name: String, type: TrackType, clips: [MediaClip] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.clips = clips
    }
}

struct Project {
    var mode: ProjectMode = .none
    var clips: [MediaClip] = []         // Mode simple
    var tracks: [Track] = []            // Mode multi-clips
    var syncResult: SyncResult?
    var exportSettings: ExportSettings = ExportSettings()

    var referenceClip: MediaClip? {
        clips.max(by: { $0.duration < $1.duration })
    }

    var hasContent: Bool {
        !clips.isEmpty || tracks.contains(where: { !$0.clips.isEmpty })
    }
}
