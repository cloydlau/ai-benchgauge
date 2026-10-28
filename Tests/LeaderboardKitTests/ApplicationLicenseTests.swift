import Testing
@testable import LeaderboardKit

@Test func applicationLicenseLoadsBundledIdentity() {
    #expect(ApplicationLicense.name == "PolyForm Perimeter License 1.0.0")
    #expect(ApplicationLicense.shortName == "PolyForm Perimeter")
}
