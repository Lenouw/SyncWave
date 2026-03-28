import Foundation

struct ClipAlignment: Equatable {
    let clipID: UUID
    let offset: TimeInterval
    let driftPPM: Double
    let confidence: Double
}

struct SyncResult: Equatable {
    let referenceClipID: UUID
    let alignments: [ClipAlignment]
    let processingTime: TimeInterval
}
