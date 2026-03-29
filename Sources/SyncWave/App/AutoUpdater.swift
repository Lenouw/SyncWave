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
    @Published var isChecking: Bool = false
    @Published var checkCompleted: Bool = false
    @Published var errorMessage: String?

    private let currentVersion: String
    private let repoOwner = "Lenouw"
    private let repoName = "SyncWave"

    var currentVersionString: String { currentVersion }

    var autoCheckUpdates: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckUpdates") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "autoCheckUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates") }
    }

    init() {
        self.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Check for updates silently (no dialog if up to date).
    func checkForUpdatessilently() async {
        guard autoCheckUpdates else { return }
        await _checkForUpdates(silent: true)
    }

    /// Check for updates — always shows dialog with result.
    func checkForUpdatesManually() async {
        await _checkForUpdates(silent: false)
    }

    private func _checkForUpdates(silent: Bool) async {
        isChecking = true
        checkCompleted = false
        updateAvailable = false
        errorMessage = nil

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            isChecking = false
            if !silent { errorMessage = "URL invalide." }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                isChecking = false
                if !silent { errorMessage = "Réponse invalide du serveur." }
                return
            }

            let remoteVersion = tagName.replacingOccurrences(of: "v", with: "")
            latestVersion = remoteVersion

            if isNewer(remote: remoteVersion, current: currentVersion) {
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
            if !silent { errorMessage = "Impossible de vérifier les mises à jour." }
        }

        isChecking = false
        if !silent { checkCompleted = true }
    }

    /// Download and install the update.
    func downloadAndInstall() async {
        guard let url = downloadURL else { return }
        isDownloading = true
        downloadProgress = 0

        do {
            // Download zip
            let (downloadedData, _) = try await URLSession.shared.data(from: url)
            let zipPath = FileManager.default.temporaryDirectory.appendingPathComponent("SyncWave-update.zip")
            try downloadedData.write(to: zipPath)
            downloadProgress = 0.5

            // Extract in background to avoid blocking MainActor
            let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("SyncWave-update")
            try? FileManager.default.removeItem(at: extractDir)

            try await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-xk", zipPath.path, extractDir.path]
                try process.run()
                process.waitUntilExit()
            }.value

            downloadProgress = 0.8

            // Replace app using actual bundle location (not hardcoded /Applications)
            let newApp = extractDir.appendingPathComponent("SyncWave.app")
            let installPath = Bundle.main.bundleURL

            if FileManager.default.fileExists(atPath: newApp.path) {
                try? FileManager.default.removeItem(at: installPath)
                try FileManager.default.copyItem(at: newApp, to: installPath)
                downloadProgress = 1.0

                // Relaunch
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-n", installPath.path]
                try task.run()

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
