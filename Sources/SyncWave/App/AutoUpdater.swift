import Foundation
import AppKit

/// Checks GitHub Releases for new versions and offers to download/install.
@MainActor
final class AutoUpdater: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var downloadURL: URL?
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0

    private let currentVersion: String
    private let repoOwner = "Lenouw"
    private let repoName = "SyncWave"

    init() {
        self.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Check for updates on launch (silently).
    func checkForUpdates() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let remoteVersion = tagName.replacingOccurrences(of: "v", with: "")

            if isNewer(remote: remoteVersion, current: currentVersion) {
                latestVersion = remoteVersion

                // Find the zip asset
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                           let urlStr = asset["browser_download_url"] as? String {
                            downloadURL = URL(string: urlStr)
                            break
                        }
                    }
                }

                updateAvailable = true
            }
        } catch {
            // Silent fail — no network or API error
        }
    }

    /// Download and install the update.
    func downloadAndInstall() async {
        guard let url = downloadURL else { return }
        isDownloading = true
        downloadProgress = 0

        do {
            // Download to temp
            let (tempURL, _) = try await URLSession.shared.data(from: url)
            let zipPath = FileManager.default.temporaryDirectory.appendingPathComponent("SyncWave-update.zip")
            try tempURL.write(to: zipPath)

            downloadProgress = 0.5

            // Unzip
            let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("SyncWave-update")
            try? FileManager.default.removeItem(at: extractDir)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", zipPath.path, extractDir.path]
            try process.run()
            process.waitUntilExit()

            downloadProgress = 0.8

            // Replace /Applications/SyncWave.app
            let newApp = extractDir.appendingPathComponent("SyncWave.app")
            let installPath = URL(fileURLWithPath: "/Applications/SyncWave.app")

            if FileManager.default.fileExists(atPath: newApp.path) {
                try? FileManager.default.removeItem(at: installPath)
                try FileManager.default.copyItem(at: newApp, to: installPath)

                downloadProgress = 1.0

                // Relaunch
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-n", installPath.path]
                try task.run()

                // Quit current instance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            }
        } catch {
            isDownloading = false
        }
    }

    /// Compare semver strings.
    private func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
