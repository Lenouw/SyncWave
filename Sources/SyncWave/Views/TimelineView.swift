import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            timeHeader
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(appState.project.clips) { clip in
                        TimelineTrackView(clip: clip, totalDuration: maxDur, isReference: clip.id == appState.project.referenceClip?.id)
                    }
                }.padding(.vertical, 4)
            }
        }.background(Color(nsColor: .textBackgroundColor).opacity(0.3))
    }

    private var timeHeader: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.clear).frame(width: 100)
            GeometryReader { geo in
                let d = maxDur; let interval = d > 3600 ? 600.0 : d > 600 ? 120.0 : 30.0
                ForEach(Array(stride(from: 0.0, through: d, by: interval)), id: \.self) { t in
                    Text(String(format: "%02d:%02d", Int(t)/60, Int(t)%60))
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary)
                        .position(x: CGFloat(t / d) * geo.size.width, y: 10)
                }
            }
        }.frame(height: 20).background(Color(nsColor: .controlBackgroundColor))
    }

    private var maxDur: TimeInterval { appState.project.clips.map { ($0.offset ?? 0) + $0.duration }.max() ?? 1 }
}
