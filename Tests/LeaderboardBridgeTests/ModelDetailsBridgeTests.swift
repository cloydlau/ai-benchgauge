import Foundation
import Testing
import LeaderboardCore
@testable import benchgauge_engine

@Test func detailsAreFormattedOnDemandOfflineWithoutRefreshingBoards() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "model-detail-bridge-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appending(path: "fixtures/model-details.json"))
    let fixture = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entry = try #require(fixture["entry"] as? [String: Any])
    let metadata = try #require(entry["modelMetadata"] as? [String: Any])
    let text = String(decoding: try JSONSerialization.data(withJSONObject: metadata), as: UTF8.self)
    let model = try JSONDecoder().decode(ModelMetadata.self, from: Data(text.utf8))
    let cache = LeaderboardCache(fileURL: file)
    cache.save(LeaderboardSnapshot(boards: [.artificialAnalysis: Leaderboard(kind: .artificialAnalysis, title: "Fixture", fetchedAt: Date(),
        entries: [LeaderboardEntry(rank: 1, name: "Original ranking name", score: 99, modelMetadata: model)])]))
    let engine = try Engine(cacheFile: file)
    let result = await engine.handle(Request(id: 1, command: "modelDetails", language: "zh", pageText: text))
    #expect(result.error == nil && result.result == nil)
    #expect(result.modelDetails?.first?.title == "模型资料")
    #expect(result.modelDetails?.contains(where: { $0.id == "provider-0" }) == true)
    let missing = await engine.handle(Request(id: 2, command: "modelDetails", pageText: "{}"))
    #expect(missing.modelDetails == [])
    let onDemand = await engine.handle(Request(id: 3, command: "modelDetails", language: "zh", modelID: model.id))
    #expect(onDemand.modelDetails == result.modelDetails)
    let projection = await engine.handle(Request(id: 4, command: "state", boards: ["artificialAnalysis"]))
    #expect(projection.result?.boards.first?.entries.first?.detailID == model.id)
    #expect(projection.result?.boards.first?.entries.first?.modelMetadata == nil)
    #expect(projection.result?.boards.first?.entries.first?.name == "Original ranking name")
}
