#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import LeaderboardKit

struct ModelDetailsViewTests {
    @Test @MainActor func nativeDetailsRenderMissingAndLoadedFactsAndKeepCopyFeedbackAccurate() throws {
        struct Fixture: Decodable { let entry: LeaderboardEntry }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/model-details.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let state = ModelDetailsUI()
        var copied: [String] = [], closed = 0, succeeds = false
        let view = ModelDetailsView(entry: fixture.entry, language: .english, state: state,
            copyName: { name in copied.append(name); return succeeds }, close: { closed += 1 })
        view.copyModelName()
        #expect(!state.copied)
        succeeds = true
        view.copyModelName()
        #expect(state.copied)
        view.close()
        #expect(copied == [fixture.entry.name, fixture.entry.name])
        #expect(closed == 1)
        func layout<V: View>(_ view: V) {
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(x: 0, y: 0, width: 600, height: 12000)
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize.width > 0)
        }
        layout(view)
        state.copied = false
        layout(view)
        layout(ModelDetailsView(entry: LeaderboardEntry(rank: 1, name: "Missing", score: 1), language: .chinese,
            copyName: { _ in false }, close: {}))
        // Exercise the row renderer with every supported label/link shape,
        // independently of a provider disclosure's initial collapsed state.
        layout(view.detailRows([.init(label: "Link", value: "Source", url: "https://models.dev"),
            .init(label: "", value: "Notice", url: nil), .init(label: "Malformed", value: "Text", url: "https://[")]))
    }
}
#endif
