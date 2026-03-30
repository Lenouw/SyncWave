import SwiftUI

/// Renders a single audio sub-track (one channel) beneath its parent video track.
/// Height: 16px, indented label, green color, with waveform.
struct AudioSubTrackView: View {
    let channelIndex: Int          // 0-based channel index
    let clips: [MediaClip]         // clips from the parent video track
    let totalDuration: TimeInterval
    @EnvironmentObject var appState: AppState

    private let subTrackHeight: CGFloat = 16

    var body: some View {
        HStack(spacing: 0) {
            // Indented label
            HStack(spacing: 4) {
                Spacer().frame(width: 14)
                Text("ch\(channelIndex + 1)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.7))
            }
            .frame(width: 50, alignment: .leading)
            .padding(.horizontal, 6)

            // Timeline area with waveform clips
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(0.03))

                    ForEach(clips) { clip in
                        let synced = appState.project.clips.first(where: { $0.id == clip.id })
                        let offset = synced?.offset ?? 0
                        let clipWidth = totalDuration > 0
                            ? max(20, geo.size.width * CGFloat(clip.duration / totalDuration))
                            : geo.size.width / CGFloat(max(1, clips.count))
                        let clipX = totalDuration > 0
                            ? geo.size.width * CGFloat(offset / totalDuration)
                            : 0

                        let waveformData = waveformForChannel(clip: synced ?? clip)

                        ZStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.green.opacity(0.08))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !waveformData.isEmpty {
                                WaveformView(samples: waveformData, color: .green)
                                    .padding(.horizontal, 2)
                            }
                        }
                        .frame(width: clipWidth)
                        .offset(x: clipX)
                        .animation(.easeInOut(duration: 0.5), value: offset)
                    }
                }
            }
            .frame(height: subTrackHeight)
            .padding(.vertical, 0)
            .padding(.trailing, 4)

            // Spacer to align with remove button in TrackRowView
            Spacer().frame(width: 22)
        }
        .frame(height: subTrackHeight + 2)
    }

    private func waveformForChannel(clip: MediaClip) -> [Float] {
        guard channelIndex < clip.waveformSamples.count else { return [] }
        return clip.waveformSamples[channelIndex]
    }
}
