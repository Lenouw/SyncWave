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

                RoundedRectangle(cornerRadius: 3)
                    .fill(clip.isVideo ? Color.blue.opacity(0.3) : Color.green.opacity(0.3))
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(clip.isVideo ? Color.blue.opacity(0.5) : Color.green.opacity(0.5)).frame(width: 2) }
                    .overlay {
                        HStack {
                            Text(clip.filename).font(.system(size: 8)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                            if let o = clip.offset, !isReference { Text(String(format: "%+.3fs", o)).font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)) }
                        }.padding(.horizontal, 6)
                    }
                    .frame(width: w).offset(x: ox)
            }
        }.frame(height: 36)
    }

    private var statusColor: Color { switch clip.syncStatus { case .synced: .green; case .lowConfidence: .yellow; case .failed: .red; case .pending: .gray } }
}
