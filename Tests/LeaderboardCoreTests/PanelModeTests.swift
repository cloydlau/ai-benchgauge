import Foundation
import Testing
@testable import LeaderboardCore

struct PanelModeTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "PanelModeTests.\(UUID().uuidString)"))
    }

    @Test
    func testDefaultsToCloseOnBlurAndKeepsBothLegacyModes() throws {
        let defaults = try defaults()
        defer {
            defaults.removeObject(forKey: PanelModePreference.legacyFocusLossKey)
            defaults.removeObject(forKey: PanelModePreference.userDefaultsKey)
        }
        #expect((PanelModePreference.load(from: defaults)) == (.closeOnBlur))
        defaults.set(true, forKey: PanelModePreference.legacyFocusLossKey)
        #expect((PanelModePreference.load(from: defaults)) == (.closeOnBlur))
        defaults.set(false, forKey: PanelModePreference.legacyFocusLossKey)
        #expect((PanelModePreference.load(from: defaults)) == (.clickToClose))
    }

    @Test
    func testAllFourModesPersistAndOverrideTheLegacyPreference() throws {
        let defaults = try defaults()
        defer {
            defaults.removeObject(forKey: PanelModePreference.legacyFocusLossKey)
            defaults.removeObject(forKey: PanelModePreference.userDefaultsKey)
        }
        defaults.set(true, forKey: PanelModePreference.legacyFocusLossKey)
        for mode in PanelMode.allCases {
            PanelModePreference.save(mode, to: defaults)
            #expect((PanelModePreference.load(from: defaults)) == (mode))
        }
        #expect(!(PanelMode.window.closesOnFocusLoss))
        #expect(!(PanelMode.clickToClose.closesOnFocusLoss))
        #expect(!(PanelMode.alwaysOnTop.closesOnFocusLoss))
        #expect(PanelMode.closeOnBlur.closesOnFocusLoss)
        #expect(PanelMode.alwaysOnTop.staysOnTop)
        #expect(!(PanelMode.clickToClose.staysOnTop))
        #expect(!(PanelMode.closeOnBlur.staysOnTop))
        #expect(!(PanelMode.window.staysOnTop))
    }

    @Test
    func testInvalidModeFallsBackToTheExistingPreference() throws {
        let defaults = try defaults()
        defer {
            defaults.removeObject(forKey: PanelModePreference.legacyFocusLossKey)
            defaults.removeObject(forKey: PanelModePreference.userDefaultsKey)
        }
        defaults.set("unknown", forKey: PanelModePreference.userDefaultsKey)
        defaults.set(true, forKey: PanelModePreference.legacyFocusLossKey)
        #expect((PanelModePreference.load(from: defaults)) == (.closeOnBlur))
        defaults.removeObject(forKey: PanelModePreference.legacyFocusLossKey)
        #expect((PanelModePreference.load(from: defaults)) == (.closeOnBlur))
    }
}
