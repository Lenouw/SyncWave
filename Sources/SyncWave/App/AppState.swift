import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0.0
}
