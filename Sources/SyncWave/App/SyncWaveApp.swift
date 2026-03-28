import SwiftUI

@main
struct SyncWaveApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Text("SyncWave")
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}
