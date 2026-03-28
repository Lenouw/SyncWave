import SwiftUI
import AVKit

struct PreviewView: View {
    @EnvironmentObject var appState: AppState
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if let player { VideoPlayer(player: player) }
            else {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Aperçu vidéo").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .onChange(of: appState.project.clips) { _, clips in
            if let first = clips.first(where: { $0.isVideo }) { player = AVPlayer(url: first.url) }
        }
    }
}
