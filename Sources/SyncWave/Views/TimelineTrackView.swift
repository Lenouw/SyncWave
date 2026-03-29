import SwiftUI

struct TimelineTrackView: View {
    let clip: MediaClip
    let totalDuration: TimeInterval
    let isReference: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(clip.filename).font(.caption2).lineLimit(1).truncationMode(.middle)
            }
            .frame(width: 100, alignment: .leading).padding(.horizontal, 8)

            GeometryReader { geo in
                let w = totalDuration > 0 ? CGFloat(clip.duration / totalDuration) * geo.size.width : geo.size.width
                let ox = totalDuration > 0 ? CGFloat((clip.offset ?? 0) / totalDuration) * geo.size.width : 0
                let baseColor: Color = clip.isVideo ? .blue : .green
                let progress = clip.processingProgress

                ZStack(alignment: .leading) {
                    // Background: grayed out version of the clip
                    RoundedRectangle(cornerRadius: 3)
                        .fill(baseColor.opacity(0.1 + 0.05 * progress))

                    // Progress fill: colorizes from left to right as processing advances
                    if progress > 0 && progress < 1 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(baseColor.opacity(0.3))
                            .frame(width: w * CGFloat(progress))
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    } else if progress >= 1 {
                        // Fully processed: full color
                        RoundedRectangle(cornerRadius: 3)
                            .fill(baseColor.opacity(0.3))
                    }

                    // Left accent bar
                    RoundedRectangle(cornerRadius: 3)
                        .fill(baseColor.opacity(progress >= 1 ? 0.6 : 0.2))
                        .frame(width: 2)

                    // Text overlay
                    HStack {
                        Text(clip.filename)
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(progress >= 1 ? 0.8 : 0.4))
                            .lineLimit(1)
                        if let o = clip.offset, !isReference {
                            Text(String(format: "%+.3fs", o))
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(width: w)
                .offset(x: ox)
            }
        }
        .frame(height: 36)
    }

    private var statusColor: Color {
        switch clip.syncStatus {
        case .synced: .green
        case .lowConfidence: .yellow
        case .failed: .red
        case .pending: .gray
        }
    }
}
