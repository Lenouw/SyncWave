import Foundation

enum ExportFormat: String, CaseIterable {
    case fcp7XML = "FCP 7 XML"
}

struct ExportSettings {
    var format: ExportFormat = .fcp7XML
    var includeUnsyncedClips: Bool = true
    var outputDirectory: URL = FileManager.default.temporaryDirectory
}
