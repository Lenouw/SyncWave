import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var updater: AutoUpdater
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Préférences").font(.headline)

            GroupBox("Mises à jour") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Vérifier automatiquement les mises à jour",
                           isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.automaticallyChecksForUpdates = $0 }
                           ))

                    HStack {
                        Button("Vérifier maintenant") {
                            updater.checkForUpdates()
                        }
                        .disabled(!updater.canCheckForUpdates)

                        Spacer()

                        Text("Version \(updater.currentVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }

            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
