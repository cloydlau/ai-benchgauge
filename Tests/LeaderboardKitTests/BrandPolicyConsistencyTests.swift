import Foundation
import Testing
@testable import LeaderboardKit

@Test func bundledModelMarksMatchSharedBrandCatalog() throws {
    struct Catalog: Decodable { let bundledModelMarks: [String] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appending(path: "fc/brand-catalog.json")))
    #expect(LeaderboardBrandPolicy.bundledModelMarks == Set(catalog.bundledModelMarks))
}
