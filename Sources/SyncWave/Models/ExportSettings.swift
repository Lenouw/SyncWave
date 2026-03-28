import Foundation

enum ExportFormat: String, CaseIterable {
    case fcp7XML = "FCP 7 XML"
}

struct ExportSettings {
    var format: ExportFormat = .fcp7XML
    var replaceAudioInVideo: Bool = true
    var includeUnsyncedClips: Bool = false
    var outputDirectory: URL = FileManager.default.temporaryDirectory
}
