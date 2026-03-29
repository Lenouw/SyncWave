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
                        ForEach(appState.project.tracks) { track in
                            TrackRowView(track: track)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var totalClipCount: Int {
        appState.project.tracks.reduce(0) { $0 + $1.clips.count }
    }
}
