import SwiftUI
import AppKit

struct UpdateView: View {
    @EnvironmentObject var updater: AutoUpdater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // App icon
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            content

            Divider()

            buttons
                .padding(.bottom, 4)
        }
        .padding(24)
        .frame(width: 360)
    }

    @ViewBuilder
    private var content: some View {
        if updater.isChecking {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Vérification des mises à jour...")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        } else if updater.isDownloading {
            VStack(spacing: 12) {
                Text("Installation en cours...")
                    .font(.headline)
                ProgressView(value: updater.downloadProgress)
                    .frame(width: 260)
                Text("\(Int(updater.downloadProgress * 100))%")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        } else if let error = updater.errorMessage {
            VStack(spacing: 8) {
                Text("Erreur")
                    .font(.headline)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if updater.updateAvailable {
            VStack(spacing: 8) {
                Text("Mise à jour disponible")
                    .font(.headline)
                Text("SyncWave \(updater.latestVersion) est disponible (vous avez \(updater.currentVersionString)).")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if updater.checkCompleted {
            VStack(spacing: 8) {
                Text("Votre logiciel est à jour !")
                    .font(.headline)
                Text("SyncWave \(updater.currentVersionString) est la version la plus récente disponible.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            // Initial / idle state before a check has run
            VStack(spacing: 8) {
                Text("Mises à jour")
                    .font(.headline)
                Text("Cliquez sur « Vérifier » pour chercher des mises à jour.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if updater.isChecking || updater.isDownloading {
            EmptyView()
        } else if updater.updateAvailable {
            HStack(spacing: 12) {
                Button("Plus tard") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Installer") {
                    Task { await updater.downloadAndInstall() }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        } else {
            Button("OK") {
                dismiss()
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
    }
}
