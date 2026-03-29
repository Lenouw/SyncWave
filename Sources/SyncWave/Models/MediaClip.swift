import Foundation

enum SyncStatus: Equatable {
    case pending
    case synced
    case lowConfidence
    case failed
}

struct MediaClip: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let filename: String
    let duration: TimeInterval
    let hasAudioTrack: Bool
    let audioSampleRate: Double
    let isVideo: Bool
    let frameRate: Double // fps du clip (ex: 29.97, 24, 25, 30)
    var syncStatus: SyncStatus = .pending
    var offset: TimeInterval?
    var driftPPM: Double?
    var confidence: Double?

    var canSync: Bool { hasAudioTrack }

    init(
        id: UUID = UUID(),
        url: URL,
        filename: String,
        duration: TimeInterval,
        hasAudioTrack: Bool,
        audioSampleRate: Double,
        isVideo: Bool,
        frameRate: Double = 30.0
    ) {
        self.id = id
        self.url = url
        self.filename = filename
        self.duration = duration
        self.hasAudioTrack = hasAudioTrack
        self.audioSampleRate = audioSampleRate
        self.isVideo = isVideo
        self.frameRate = frameRate
    }

    mutating func applySyncResult(offset: TimeInterval, driftPPM: Double, confidence: Double) {
        self.offset = offset
        self.driftPPM = driftPPM
        self.confidence = confidence
        if confidence >= 0.7 {
            self.syncStatus = .synced
        } else if confidence >= 0.3 {
            self.syncStatus = .lowConfidence
        } else {
            self.syncStatus = .failed
        }
    }
}
