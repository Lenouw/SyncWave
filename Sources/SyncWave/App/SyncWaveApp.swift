import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let windows = NSApplication.shared.windows
            if windows.count > 1 {
                for window in windows.dropFirst() { window.close() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = sender.windows.first { window.makeKeyAndOrderFront(nil) }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SyncWaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var updater = AutoUpdater()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .environmentObject(updater)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await updater.checkForUpdates()
                }
                .alert("Mise à jour disponible", isPresented: $updater.updateAvailable) {
                    Button("Installer v\(updater.latestVersion)") {
                        Task { await updater.downloadAndInstall() }
                    }
                    Button("Plus tard", role: .cancel) { }
                } message: {
                    Text("SyncWave v\(updater.latestVersion) est disponible. Voulez-vous l'installer ?")
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
