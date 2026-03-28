import SwiftUI
import UniformTypeIdentifiers

struct ImportDropZone: View {
    @EnvironmentObject var appState: AppState
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack").font(.system(size: 48)).foregroundStyle(.tertiary)
            Text("Glissez vos fichiers vidéo et audio ici").font(.title3).foregroundStyle(.secondary)
            Text("MOV, MP4, WAV, AIFF, MP3...").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
            .foregroundStyle(isTargeted ? Color.blue : Color.gray.opacity(0.3)).padding(20))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in await appState.importFiles(urls: [url]) }
                }
            }
            return true
        }
    }
}
