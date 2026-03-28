import SwiftUI

struct SyncStatusPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ÉTAT DE SYNCHRONISATION").font(.caption2).foregroundStyle(.secondary).tracking(0.5)
            ScrollView {
                VStack(spacing: 6) { ForEach(appState.project.clips) { clip in clipRow(clip) } }
            }
            Spacer()
            if let syncResult = appState.project.syncResult {
                confidenceBar(avgConfidence(syncResult))
            }
        }
        .padding(14).background(Color(nsColor: .controlBackgroundColor))
    }

    private func clipRow(_ clip: MediaClip) -> some View {
        let isRef = clip.id == appState.project.referenceClip?.id
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(colorFor(clip.syncStatus)).frame(width: 8, height: 8)
                Text(clip.filename).font(.caption).lineLimit(1)
            }
            if isRef {
                Text("Référence · \(formatDuration(clip.duration))").font(.caption2).foregroundStyle(.green).padding(.leading, 14)
            } else if let offset = clip.offset {
                Text(String(format: "%+.3fs", offset) + (clip.driftPPM.map { " · drift \(Int($0)) PPM" } ?? ""))
                    .font(.caption2).foregroundStyle(.secondary).padding(.leading, 14)
            }
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 5).fill(bgFor(clip.syncStatus))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(borderFor(clip.syncStatus), lineWidth: 1)))
    }

    private func confidenceBar(_ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Confiance globale").font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: value).tint(confColor(value))
            Text("\(Int(value * 100))%").font(.caption2).foregroundStyle(confColor(value)).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func colorFor(_ s: SyncStatus) -> Color { switch s { case .synced: .green; case .lowConfidence: .yellow; case .failed: .red; case .pending: .gray } }
    private func bgFor(_ s: SyncStatus) -> Color { switch s { case .synced: .green.opacity(0.05); case .lowConfidence: .yellow.opacity(0.05); case .failed: .red.opacity(0.05); case .pending: .clear } }
    private func borderFor(_ s: SyncStatus) -> Color { switch s { case .synced: .green.opacity(0.2); case .lowConfidence: .yellow.opacity(0.2); case .failed: .red.opacity(0.2); case .pending: .gray.opacity(0.1) } }
    private func confColor(_ c: Double) -> Color { c >= 0.7 ? .green : c >= 0.3 ? .yellow : .red }
    private func avgConfidence(_ r: SyncResult) -> Double { r.alignments.isEmpty ? 0 : r.alignments.map(\.confidence).reduce(0, +) / Double(r.alignments.count) }
    private func formatDuration(_ d: TimeInterval) -> String { let h = Int(d)/3600; let m = (Int(d)%3600)/60; return h > 0 ? "\(h)h \(m)min" : "\(m)min" }
}
