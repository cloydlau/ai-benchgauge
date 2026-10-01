import AppKit
import LeaderboardCore
import Sparkle
import Testing
@testable import leaderboard_menu

@Suite(.serialized)
@MainActor
struct PreparedUpdateTests {
    private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func downloadAloneCannotPresentOrInstall() {
        var active: NSWindow?
        var prompts = 0
        var installs = 0
        var confirm: (() -> Void)?
        let driver = PreparedUpdateUserDriver(activeWindow: { active }, present: { _, reply in
            prompts += 1; confirm = reply
        })
        driver.showDownloadInitiated(cancellation: {})
        driver.showDownloadDidReceiveData(ofLength: 1024)
        #expect(prompts == 0)
        driver.showReady(toInstallAndRelaunch: { choice in
            #expect(choice == .install); installs += 1
        })
        driver.presentIfReady()
        #expect(prompts == 0)
        #expect(installs == 0)
        active = window()
        driver.presentIfReady()
        driver.presentIfReady()
        #expect(prompts == 1)
        #expect(installs == 0)
        #expect(driver.isPresentingUpdate)
        confirm?(); confirm?()
        #expect(installs == 1)
        #expect(driver.isPresentingUpdate)
        driver.dismissUpdateInstallation()
    }

    @Test func activeWindowAloneCannotPresent() {
        let active = window()
        var prompts = 0
        let driver = PreparedUpdateUserDriver(activeWindow: { active }, present: { _, _ in prompts += 1 })
        driver.presentIfReady()
        driver.showDownloadDidStartExtractingUpdate()
        driver.showExtractionReceivedProgress(1)
        #expect(prompts == 0)
        driver.dismissUpdateInstallation()
    }

    @Test func preparedAutomaticUpdateWaitsForConfirmation() {
        let active = window()
        var confirms: [() -> Void] = []
        var installs = 0
        let driver = PreparedUpdateUserDriver(activeWindow: { active }, present: { _, confirm in confirms.append(confirm) })
        driver.prepare { installs += 1 }
        driver.prepare { installs += 100 }
        #expect(confirms.count == 1)
        #expect(installs == 0)
        confirms[0]()
        #expect(installs == 1)
        // An authorization fallback continues after this same click, without
        // asking the user to confirm the installation a second time.
        driver.showReady(toInstallAndRelaunch: { choice in #expect(choice == .install); installs += 1 })
        #expect(installs == 2)
        #expect(confirms.count == 1)
        driver.dismissUpdateInstallation()
    }

    @Test func failedPreparationDiscardsPendingPrompt() {
        var active: NSWindow?
        var prompts = 0
        var acknowledgements = 0
        let driver = PreparedUpdateUserDriver(activeWindow: { active }, present: { _, _ in prompts += 1 })
        driver.prepare { Issue.record("Failed update must never install") }
        driver.showUpdaterError(NSError(domain: "fixture", code: 1), acknowledgement: { acknowledgements += 1 })
        active = window(); driver.presentIfReady()
        #expect(prompts == 0)
        #expect(acknowledgements == 1)
        driver.prepare {}
        #expect(prompts == 1)
        driver.dismissUpdateInstallation()
    }

    @Test func mandatoryDialogUsesExactMiniProgramCopyAndRejectsClosing() {
        _ = NSApplication.shared
        var installs = 0
        let dialog = PreparedUpdatePanel(language: .chinese, confirm: { installs += 1 })
        #expect(dialog.title == "发现新版本")
        #expect(!dialog.styleMask.contains(.closable))
        #expect(!dialog.styleMask.contains(.miniaturizable))
        #expect(!dialog.windowShouldClose(dialog))
        dialog.performClose(nil); dialog.cancelOperation(nil)
        #expect(installs == 0)
        let stack = dialog.contentView?.subviews.compactMap { $0 as? NSStackView }.first
        let labels = stack?.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue } ?? []
        #expect(labels == ["发现新版本", "新版本已下载完成，重启后生效。"])
        let buttons = stack?.arrangedSubviews.compactMap { $0 as? NSButton } ?? []
        #expect(buttons.count == 1)
        #expect(buttons.first?.title == "重启升级")
        buttons.first?.performClick(nil)
        #expect(installs == 1)
        #expect(buttons.first?.isEnabled == false)
    }
}
