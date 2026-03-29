import SwiftUI
import UniformTypeIdentifiers

struct MultiTrackTimelineView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: add tracks
            HStack(spacing: 10) {
                Button {
                    appState.addTrack(type: .video)
                } label: {
                    Label("Piste vidéo", systemImage: "film")
                }

                Button {
                    appState.addTrack(type: .audio)
                } label: {
                    Label("Piste audio", systemImage: "waveform")
                }

                Spacer()

                if appState.project.hasContent {
                    Text("\(totalClipCount) clips")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Tracks
            if appState.project.tracks.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Ajoutez des pistes vidéo et audio")
                        .foregroundStyle(.secondary)
                    Text("Puis glissez vos fichiers sur chaque piste")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        // Convention NLE : vidéo empilée de bas en haut (V6 en haut, V1 en bas)
                        // Audio empilée de haut en bas (A1 en haut, A6 en bas)
                        // V1 et A1 sont collés au séparateur central
                        ForEach(videoTracks.reversed()) { track in
                            TrackRowView(track: track)
                        }
                        if !videoTracks.isEmpty && !audioTracks.isEmpty {
                            Divider().padding(.vertical, 2)
                        }
                        ForEach(audioTracks) { track in
                            TrackRowView(track: track)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var videoTracks: [Track] {
        appState.project.tracks.filter { $0.type == .video }
    }

    private var audioTracks: [Track] {
        appState.project.tracks.filter { $0.type == .audio }
    }

    private var totalClipCount: Int {
        appState.project.tracks.reduce(0) { $0 + $1.clips.count }
    }
}
