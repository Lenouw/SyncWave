import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var updater: AutoUpdater
    @State private var autoCheck: Bool = true
    @State private var showUpdateWindow: Bool = false

    var body: some View {
        Form {
            Section("Mises à jour") {
                Toggle("Vérifier automatiquement les mises à jour", isOn: $autoCheck)
                    .onChange(of: autoCheck) { _, newValue in
                        updater.autoCheckUpdates = newValue
                    }

                HStack {
                    Button("Vérifier maintenant") {
                        showUpdateWindow = true
                        Task { await updater.checkForUpdatesManually() }
                    }
                    .disabled(updater.isChecking)

                    Spacer()

                    Text("Version \(updater.currentVersionString)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 160)
        .onAppear {
            autoCheck = updater.autoCheckUpdates
        }
        .sheet(isPresented: $showUpdateWindow) {
            UpdateView()
                .environmentObject(updater)
        }
        .onChange(of: updater.checkCompleted) { _, completed in
            if completed { showUpdateWindow = true }
        }
        .onChange(of: updater.updateAvailable) { _, available in
            if available { showUpdateWindow = true }
        }
    }
}
