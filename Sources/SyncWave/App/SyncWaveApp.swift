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

    @State private var showPreferences: Bool = false

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSWindow.allowsAutomaticWindowTabbing = false

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        Logger.shared.info("SyncWave \(version) launched")
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .environmentObject(updater)
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: $showPreferences) {
                    PreferencesView()
                        .environmentObject(updater)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("SyncWave") {
                Button("Vérifier les mises à jour...") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)

                Button("Ouvrir les logs...") {
                    let logURL = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Logs/SyncWave/SyncWave.log")
                    NSWorkspace.shared.open(logURL)
                }

                Divider()

                Button("Préférences...") {
                    showPreferences = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
