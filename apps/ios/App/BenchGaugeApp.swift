import SwiftUI
import LeaderboardPadUI

@main
@MainActor
struct BenchGaugeApp: App {
    @StateObject private var store: LeaderboardPadStore
    init() {
        #if DEBUG
        _store = StateObject(wrappedValue: DebugFixtures.makeStoreIfRequested() ?? LeaderboardPadStore())
        #else
        _store = StateObject(wrappedValue: LeaderboardPadStore())
        #endif
    }
    var body: some Scene {
        WindowGroup { LeaderboardPadView(store: store) }
    }
}
