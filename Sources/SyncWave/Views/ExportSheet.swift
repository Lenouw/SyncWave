import SwiftUI

struct ExportSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Exporter la synchronisation").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Format :").foregroundStyle(.secondary); Text(appState.project.exportSettings.format.rawValue).fontWeight(.medium) }
                Toggle("Remplacer l'audio des vidéos par l'audio externe", isOn: $appState.project.exportSettings.replaceAudioInVideo)
                Toggle("Inclure les clips non synchronisés", isOn: $appState.project.exportSettings.includeUnsyncedClips)
            }.padding().background(RoundedRectangle(cornerRadius: 8).fill(.bar))

            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Exporter") {
                    Task {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.xml]
                        panel.nameFieldStringValue = "SyncWave Export.xml"
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.project.exportSettings.outputDirectory = url.deletingLastPathComponent()
                            _ = await appState.exportXML()
                            dismiss()
                        }
                    }
                }.keyboardShortcut(.defaultAction).disabled(!appState.hasSyncResult)
            }
        }.padding(24).frame(width: 450)
    }
}
