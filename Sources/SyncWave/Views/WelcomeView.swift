import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 32) {
            // Title
            VStack(spacing: 8) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("SyncWave")
                    .font(.largeTitle.bold())
                Text("Synchronisation audio/vidéo multi-caméra")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Mode cards
            HStack(spacing: 20) {
                ModeCard(
                    icon: "bolt.fill",
                    iconColor: .blue,
                    title: "Sync rapide",
                    description: "Glissez tous vos fichiers, la synchronisation est automatique.\nIdéal pour un enregistrement continu.",
                    action: { appState.setMode(.simple) }
                )

                ModeCard(
                    icon: "rectangle.stack.fill",
                    iconColor: .green,
                    title: "Multi-clips",
                    description: "Organisez vos fichiers par piste (V1, V2, A1...).\nIdéal pour les tournages avec coupures.",
                    action: { appState.setMode(.multiClip) }
                )
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct ModeCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.title2.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isHovered ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
