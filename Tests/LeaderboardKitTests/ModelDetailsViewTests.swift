#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import LeaderboardKit

struct ModelDetailsViewTests {
    @Test(arguments: [false, true]) @MainActor func nativeDisclosureAndBackToTopRespondToUserActions(reduceMotion: Bool) async throws {
        _ = NSApplication.shared
        struct Fixture: Decodable { let entry: LeaderboardEntry }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/model-details.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let state = ModelDetailsUI()
        let host = NSHostingView(rootView: ModelDetailsView(entry: fixture.entry, language: .english, state: state,
            copyName: { _ in true }, close: {}).environment(\.accessibilityEnabled, true)
            .environment(\._accessibilityReduceMotion, reduceMotion))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 600, height: 450),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        func accessible(_ object: NSObject) -> [NSObject] {
            var seen = Set<ObjectIdentifier>()
            func walk(_ object: NSObject) -> [NSObject] {
                guard seen.insert(ObjectIdentifier(object)).inserted else { return [] }
                let selector = NSSelectorFromString("accessibilityChildren")
                let children = object.responds(to: selector)
                    ? (object.perform(selector)?.takeUnretainedValue() as? [NSObject] ?? []) : []
                return [object] + (children + ((object as? NSView)?.subviews ?? [])).flatMap(walk)
            }
            return walk(object)
        }
        func label(_ object: NSObject) -> String? {
            for name in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
                let selector = NSSelectorFromString(name)
                if object.responds(to: selector), let text = object.perform(selector)?.takeUnretainedValue() as? String { return text }
            }
            return nil
        }
        func press(_ object: NSObject) -> Bool {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            guard object.responds(to: selector) else { return false }
            let action = unsafeBitCast(object.method(for: selector), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
            return action(object, selector)
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
        // Target the first disclosure in the fixed-width fixture, using the
        // hosting view's coordinates rather than the user's global mouse.
        let point = host.convert(NSPoint(x: 37, y: host.isFlipped ? 218 : host.bounds.height - 218), to: nil)
        func toggle() throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
        }
        try toggle()
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.expanded["limits"] == false, "Host \(String(describing: host.bounds)), window point \(String(describing: point)), scroll \(String(describing: scroll.frame))")
        try toggle()
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.expanded["limits"] == true)
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 1, wheel1: -500, wheel2: 0, wheel3: 0))
        scroll.scrollWheel(with: try #require(NSEvent(cgEvent: wheel)))
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            host.display()
            if state.backToTop { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(state.backToTop, "Scroll offset \(String(describing: scroll.contentView.bounds)), document \(String(describing: scroll.documentView?.bounds))")
        let back = try #require(accessible(host).first { label($0) == ModelDetails.text("backToTop", language: .english) })
        #expect(press(back))
        for _ in 0..<30 {
            host.layoutSubtreeIfNeeded()
            host.display()
            if !state.backToTop { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!state.backToTop)
    }

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
