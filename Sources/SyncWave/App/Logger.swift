// Sources/SyncWave/App/Logger.swift
import Foundation

final class Logger {
    static let shared = Logger()

    enum Level: String {
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERROR"
    }

    private let queue = DispatchQueue(label: "com.syncwave.logger", qos: .utility)
    private let logFileURL: URL
    private let maxFileSize: Int = 5 * 1024 * 1024 // 5 MB

    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SyncWave")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logFileURL = logsDir.appendingPathComponent("SyncWave.log")
    }

    func info(_ message: String)  { log(message, level: .info) }
    func warn(_ message: String)  { log(message, level: .warn) }
    func error(_ message: String) { log(message, level: .error) }

    private func log(_ message: String, level: Level) {
        queue.async { [self] in
            self.rotateIfNeeded()
            let line = "[\(self.timestamp())] [\(level.rawValue)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.logFileURL)
                }
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? Int, size > maxFileSize else { return }
        let oldURL = logFileURL.deletingPathExtension().appendingPathExtension("log.old")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: logFileURL, to: oldURL)
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
