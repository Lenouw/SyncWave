import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @State private var showExportSheet = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            HStack(spacing: 0) {
                PreviewView()
                    .frame(height: 220)
                SyncStatusPanel()
                    .frame(width: 220, height: 220)
            }
            .frame(height: 220)

            Divider()

            MultiTrackTimelineView()

            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showExportSheet) { ExportSheet() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                appState.resetProject()
            } label: {
                Label("Nouveau projet", systemImage: "plus.square")
            }
            Divider().frame(height: 20)
            Button { Task { await appState.sync() } } label: { Label("Synchroniser", systemImage: "play.fill") }
                .disabled(!appState.canSync || appState.isSyncing).tint(.red)
            Spacer()
            if appState.hasClips {
                let count = appState.totalClipCount
                Text("\(count) clips").font(.caption).foregroundStyle(.secondary)
            }
            Divider().frame(height: 20)
            Button { showExportSheet = true } label: { Label("Exporter XML", systemImage: "square.and.arrow.up") }
                .disabled(!appState.hasSyncResult)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    private var statusBar: some View {
        HStack {
            if appState.isSyncing { ProgressView(value: appState.syncProgress).frame(width: 100) }
            Text(appState.statusMessage ?? "Prêt").font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 4).background(.bar)
    }

}
