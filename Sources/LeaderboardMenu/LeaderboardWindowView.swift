import SwiftUI

/// Let the native window own its size, including while macOS tiles it.
struct LeaderboardWindowView: View {
    @ObservedObject var state: AppState

    var body: some View {
        GeometryReader { geometry in
            LeaderboardView(state: state, maximumWidth: geometry.size.width, viewportSize: geometry.size)
        }
    }
}
