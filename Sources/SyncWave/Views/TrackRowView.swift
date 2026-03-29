import SwiftUI
import UniformTypeIdentifiers

struct TrackRowView: View {
    let track: Track
    @EnvironmentObject var appState: AppState
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            // Track label
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(track.type == .video ? Color.blue : Color.green)
                    .frame(width: 4, height: 24)
                Text(track.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(track.type == .video ? .blue : .green)
            }
            .frame(width: 60, alignment: .leading)
            .padding(.horizontal, 8)

            // Clips area (drop zone)
            ZStack(alignment: .leading) {
                // Drop zone background
                RoundedRectangle(cornerRadius: 4)
                    .fill(isDropTargeted
                          ? (track.type == .video ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                          : Color(nsColor: .textBackgroundColor).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isDropTargeted ? (track.type == .video ? Color.blue : Color.green) : Color.clear,
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                            )
                    )

                if track.clips.isEmpty {
                    Text("Glisser des fichiers \(track.type == .video ? "vidéo" : "audio") ici")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                } else {
                    // Show clips as blocks
                    HStack(spacing: 2) {
                        ForEach(track.clips) { clip in
                            clipBlock(clip)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(height: 40)
            .padding(.vertical, 2)
            .padding(.trailing, 8)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }

            // Remove track button
            Button {
                appState.removeTrack(id: track.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .frame(height: 48)
    }

    private func clipBlock(_ clip: MediaClip) -> some View {
        let color: Color = track.type == .video ? .blue : .green
        return HStack(spacing: 4) {
            Image(systemName: track.type == .video ? "film" : "waveform")
                .font(.system(size: 8))
            Text(clip.filename)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
        )
        .cornerRadius(3)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await appState.importToTrack(trackID: track.id, urls: [url])
                }
            }
        }
    }
}
