import SwiftUI
import UniformTypeIdentifiers

struct TrackRowView: View {
    let track: Track
    let totalDuration: TimeInterval  // total timeline duration for positioning
    @EnvironmentObject var appState: AppState
    @State private var isDropTargeted = false

    private var baseColor: Color { track.type == .video ? .blue : .green }

    var body: some View {
        HStack(spacing: 0) {
            // Track label
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(baseColor)
                    .frame(width: 4, height: 24)
                Text(track.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(baseColor)
            }
            .frame(width: 50, alignment: .leading)
            .padding(.horizontal, 6)

            // Timeline area (drop zone + positioned clips)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Drop zone background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isDropTargeted
                              ? baseColor.opacity(0.1)
                              : Color(nsColor: .textBackgroundColor).opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(
                                    isDropTargeted ? baseColor : Color.clear,
                                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                                )
                        )

                    if track.clips.isEmpty {
                        Text("Glisser des fichiers \(track.type == .video ? "vidéo" : "audio") ici")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    } else {
                        // Position clips on timeline based on their offset
                        ForEach(track.clips) { clip in
                            let synced = appState.project.clips.first(where: { $0.id == clip.id })
                            let offset = synced?.offset ?? 0
                            let progress = synced?.processingProgress ?? 0
                            let clipWidth = totalDuration > 0
                                ? max(30, geo.size.width * CGFloat(clip.duration / totalDuration))
                                : geo.size.width / CGFloat(max(1, track.clips.count))
                            let clipX = totalDuration > 0
                                ? geo.size.width * CGFloat(offset / totalDuration)
                                : 0

                            clipBlock(clip, progress: progress, isSynced: synced?.offset != nil)
                                .frame(width: clipWidth)
                                .offset(x: clipX)
                                .animation(.easeInOut(duration: 0.5), value: offset)
                        }
                    }
                }
            }
            .frame(height: 36)
            .padding(.vertical, 2)
            .padding(.trailing, 4)
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
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .frame(height: 44)
    }

    private func clipBlock(_ clip: MediaClip, progress: Double, isSynced: Bool) -> some View {
        let opacity = isSynced ? (0.15 + 0.25 * progress) : 0.15
        let borderOpacity = isSynced ? (0.2 + 0.4 * progress) : 0.2
        let textOpacity = isSynced ? (0.4 + 0.5 * progress) : 0.5

        return ZStack(alignment: .leading) {
            // Background
            RoundedRectangle(cornerRadius: 3)
                .fill(baseColor.opacity(opacity))

            // Progress fill (left to right)
            if progress > 0 && progress < 1 {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(baseColor.opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(progress))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            } else if progress >= 1 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(baseColor.opacity(0.3))
            }

            // Left accent
            RoundedRectangle(cornerRadius: 3)
                .fill(baseColor.opacity(borderOpacity))
                .frame(width: 2)

            // Text
            HStack(spacing: 3) {
                Image(systemName: track.type == .video ? "film" : "waveform")
                    .font(.system(size: 7))
                Text(clip.filename)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let offset = appState.project.clips.first(where: { $0.id == clip.id })?.offset, offset != 0 {
                    Text(String(format: "%+.1fs", offset))
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .foregroundStyle(.white.opacity(textOpacity))
            .padding(.horizontal, 5)
        }
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
