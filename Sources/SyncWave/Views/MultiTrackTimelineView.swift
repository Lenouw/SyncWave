import SwiftUI
import UniformTypeIdentifiers

struct MultiTrackTimelineView: View {
    @EnvironmentObject var appState: AppState

    /// Total timeline duration: max(offset + duration) across all synced clips.
    private var totalDuration: TimeInterval {
        let allClips = appState.project.clips
        if allClips.isEmpty {
            // Fallback to track clips (before sync)
            let trackClips = appState.project.tracks.flatMap(\.clips)
            return trackClips.map(\.duration).max() ?? 1
        }
        let maxEnd = allClips.map { ($0.offset ?? 0) + $0.duration }.max() ?? 1
        return max(1, maxEnd)
    }

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

                if totalClipCount > 0 {
                    Text("\(totalClipCount) clips")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)

            // Time ruler
            timeRuler

            Divider()

            // Tracks
            if appState.project.tracks.isEmpty {
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
                        // Convention NLE : V en haut (reversed), A en bas
                        ForEach(videoTracks.reversed()) { track in
                            TrackRowView(track: track, totalDuration: totalDuration)
                            // Audio sub-tracks for each channel of the video's audio
                            ForEach(0..<audioSubTrackCount(for: track), id: \.self) { chIdx in
                                AudioSubTrackView(
                                    channelIndex: chIdx,
                                    clips: track.clips,
                                    totalDuration: totalDuration
                                )
                            }
                        }
                        if !videoTracks.isEmpty && !audioTracks.isEmpty {
                            Divider().padding(.vertical, 2)
                        }
                        ForEach(audioTracks) { track in
                            TrackRowView(track: track, totalDuration: totalDuration)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var timeRuler: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.clear).frame(width: 62) // label width

            GeometryReader { geo in
                let duration = totalDuration
                let interval = duration > 3600 ? 600.0 : duration > 600 ? 120.0 : duration > 60 ? 30.0 : 10.0
                let marks = stride(from: 0.0, through: duration, by: interval)

                ForEach(Array(marks.enumerated()), id: \.offset) { _, t in
                    let x = geo.size.width * CGFloat(t / duration)
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 6)
                        Text(formatTime(t))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .position(x: x, y: 10)
                }
            }
        }
        .frame(height: 20)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
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

    /// Max audio channel count across clips in a video track
    private func audioSubTrackCount(for track: Track) -> Int {
        guard track.type == .video else { return 0 }
        return track.clips.map(\.audioChannelCount).max() ?? 0
    }
}
