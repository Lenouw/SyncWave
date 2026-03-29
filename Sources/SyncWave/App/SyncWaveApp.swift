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
        Window("SyncWave", id: "main") {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
    }
}
