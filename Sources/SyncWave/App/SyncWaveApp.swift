import SwiftUI
import AppKit

@main
struct SyncWaveApp: App {
    @StateObject private var appState = AppState()

    init() {
        // Force l'app au premier plan (nécessaire pour SPM executable)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}
