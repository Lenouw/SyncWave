import Foundation

enum ProjectMode: Equatable {
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
    var mode: ProjectMode = .multiClip
    var clips: [MediaClip] = []
    var tracks: [Track] = Project.defaultTracks()
    var syncResult: SyncResult?
    var exportSettings: ExportSettings = ExportSettings()

    var referenceClip: MediaClip? {
        clips.max(by: { $0.duration < $1.duration })
    }

    var hasContent: Bool {
        tracks.contains(where: { !$0.clips.isEmpty })
    }

    static func defaultTracks() -> [Track] {
        [
            Track(name: "V1", type: .video),
            Track(name: "V2", type: .video),
            Track(name: "V3", type: .video),
            Track(name: "A1", type: .audio),
            Track(name: "A2", type: .audio),
            Track(name: "A3", type: .audio),
        ]
    }
}
