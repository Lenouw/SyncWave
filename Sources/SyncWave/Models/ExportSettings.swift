import Foundation

enum ExportFormat: String, CaseIterable {
    case fcp7XML = "FCP 7 XML"
}

struct ExportSettings {
    var format: ExportFormat = .fcp7XML
    var replaceAudioInVideo: Bool = true
    var includeUnsyncedClips: Bool = true  // Include all clips by default in multi-clip mode
    var outputDirectory: URL = FileManager.default.temporaryDirectory
}
