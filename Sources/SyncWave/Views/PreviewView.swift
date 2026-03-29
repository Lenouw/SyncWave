import SwiftUI
import AVKit

/// NSViewRepresentable wrapper for AVPlayerView (avoids _AVKit_SwiftUI crash in SPM builds)
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

struct PreviewView: View {
    @EnvironmentObject var appState: AppState
    @State private var player: AVPlayer?
    @State private var currentVideoURL: URL?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                NativePlayerView(player: player)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Aperçu vidéo").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .onChange(of: appState.project.clips) { _, clips in
            // Only recreate player when the first video URL actually changes
            if let first = clips.first(where: { $0.isVideo }), first.url != currentVideoURL {
                currentVideoURL = first.url
                player = AVPlayer(url: first.url)
            }
        }
    }
}
