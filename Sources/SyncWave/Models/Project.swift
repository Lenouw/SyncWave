import Foundation

struct Project {
    var clips: [MediaClip] = []
    var syncResult: SyncResult?
    var exportSettings: ExportSettings = ExportSettings()

    var referenceClip: MediaClip? {
        clips.max(by: { $0.duration < $1.duration })
    }
}
