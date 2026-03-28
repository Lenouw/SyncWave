import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @State private var showExportSheet = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if appState.hasClips { mainContent } else { ImportDropZone() }
            statusBar
        }
        .sheet(isPresented: $showExportSheet) { ExportSheet() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { openFileDialog() } label: { Label("Importer", systemImage: "plus") }
            Divider().frame(height: 20)
            Button { Task { await appState.sync() } } label: { Label("Synchroniser", systemImage: "play.fill") }
                .disabled(appState.project.clips.count < 2 || appState.isSyncing).tint(.red)
            Spacer()
            if appState.hasClips { Text("\(appState.project.clips.count) clips").font(.caption).foregroundStyle(.secondary) }
            Divider().frame(height: 20)
            Button { showExportSheet = true } label: { Label("Exporter XML", systemImage: "square.and.arrow.up") }
                .disabled(!appState.hasSyncResult)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PreviewView().frame(height: 220)
                SyncStatusPanel().frame(width: 220, height: 220)
            }
            Divider()
            TimelineView()
        }
    }

    private var statusBar: some View {
        HStack {
            if appState.isSyncing { ProgressView(value: appState.syncProgress).frame(width: 100) }
            Text(appState.statusMessage ?? "Prêt").font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 4).background(.bar)
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .wav, .aiff, .mp3, .mpeg4Audio]
        if panel.runModal() == .OK { Task { await appState.importFiles(urls: panel.urls) } }
    }
}
