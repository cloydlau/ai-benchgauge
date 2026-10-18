#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
import LeaderboardKit

@MainActor
struct UnknownCountryButtonTests {
    @Test func nativeHelpExplainsUnassignedCountryAndDismisses() async throws {
        _ = NSApplication.shared
        for language in AppLanguage.allCases {
            let host = NSHostingView(rootView: UnknownCountryButton(language: language).frame(width: 100, height: 60))
            let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 100, height: 60),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.display()
            // Deliver events to this test window without global mouse access.
            let point = host.convert(NSPoint(x: host.bounds.midX, y: host.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
            try await waitUntil { window.attachedSheet != nil }
            let sheet = try #require(window.attachedSheet)
            let content = try #require(sheet.contentView)
            let labels = descendants(content).compactMap { ($0 as? NSTextField)?.stringValue }
            #expect(labels.contains(OrganizationRegion.unknownTitle(language: language)))
            #expect(labels.contains(OrganizationRegion.unknownExplanation(language: language)))
            let dismiss = try #require(descendants(content).compactMap { $0 as? NSButton }
                .first { $0.title == language.text("OK", "知道了") })
            dismiss.performClick(nil)
            try await waitUntil { window.attachedSheet == nil }
            #expect(window.attachedSheet == nil)
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func waitUntil(_ ready: () -> Bool) async throws {
        for _ in 0..<40 {
            if ready() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(ready(), "Native country help did not finish presenting or dismissing")
    }
}
#endif
