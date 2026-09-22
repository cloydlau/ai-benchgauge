import LeaderboardCore
import XCTest

final class LeaderboardCategoryTests: XCTestCase {
    func testCategoriesMapToTheirLeftAndRightBoards() {
        XCTAssertEqual(LeaderboardCategory.general.boardKinds, [.artificialAnalysis, .arenaText])
        XCTAssertEqual(LeaderboardCategory.coding.boardKinds, [.artificialAnalysisCodingAgent, .codeArenaWebDev])
        XCTAssertEqual(LeaderboardCategory.image.boardKinds, [.artificialAnalysisTextToImage, .arenaTextToImage])
        XCTAssertEqual(LeaderboardCategory.video.boardKinds, [.artificialAnalysisTextToVideo, .arenaTextToVideo])
    }

    func testMediaCategoriesUseTextToImageAndTextToVideoSources() {
        XCTAssertEqual(
            LeaderboardKind.artificialAnalysisTextToImage.sourceURL.absoluteString,
            "https://artificialanalysis.ai/image/leaderboard/text-to-image"
        )
        XCTAssertEqual(
            LeaderboardKind.arenaTextToImage.sourceURL.absoluteString,
            "https://arena.ai/leaderboard/text-to-image"
        )
        XCTAssertEqual(
            LeaderboardKind.artificialAnalysisTextToVideo.sourceURL.absoluteString,
            "https://artificialanalysis.ai/video/leaderboard/text-to-video"
        )
        XCTAssertEqual(
            LeaderboardKind.arenaTextToVideo.sourceURL.absoluteString,
            "https://arena.ai/leaderboard/text-to-video"
        )
    }

    func testCodingCategoryUsesDedicatedArtificialAnalysisSource() {
        XCTAssertEqual(
            LeaderboardKind.artificialAnalysisCodingAgent.sourceURL.absoluteString,
            "https://artificialanalysis.ai/agents/coding-agents"
        )
    }

    func testCategoryPreferenceRestoresLastSelectionAndFallsBack() {
        let suite = "CategoryPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(CategoryPreference.load(from: defaults), .general)

        CategoryPreference.save(.video, to: defaults)
        XCTAssertEqual(CategoryPreference.load(from: defaults), .video)

        defaults.set("not-a-category", forKey: CategoryPreference.userDefaultsKey)
        XCTAssertEqual(CategoryPreference.load(from: defaults), .general)
        XCTAssertNil(defaults.string(forKey: CategoryPreference.userDefaultsKey))
    }

    func testArtificialAnalysisLabelsUseTheFullName() {
        let kinds: [LeaderboardKind] = [
            .artificialAnalysis,
            .artificialAnalysisCodingAgent,
            .artificialAnalysisTextToImage,
            .artificialAnalysisTextToVideo,
        ]
        for kind in kinds {
            XCTAssertEqual(kind.sourcePrefix, "Artificial Analysis")
            XCTAssertFalse(kind.sourceLinkTitle.contains("AA"))
            XCTAssertTrue(kind.sourceLinkTitle.hasPrefix("Artificial Analysis"))
        }
    }

    func testLegacyAbbreviatedCacheKeysStillDecode() throws {
        let json = """
        {
          "boards": {
            "aaCodingAgent": {
              "kind": "aaCodingAgent",
              "title": "Artificial Analysis Coding Agent Index",
              "fetchedAt": "2026-09-22T10:00:00Z",
              "entries": []
            },
            "aaTextToImage": {
              "kind": "aaTextToImage",
              "title": "Artificial Analysis | 文生图",
              "fetchedAt": "2026-09-22T10:00:00Z",
              "entries": []
            },
            "aaTextToVideo": {
              "kind": "aaTextToVideo",
              "title": "Artificial Analysis | 文生视频",
              "fetchedAt": "2026-09-22T10:00:00Z",
              "entries": []
            }
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LeaderboardSnapshot.self, from: json)

        XCTAssertEqual(
            Set(snapshot.boards.keys),
            [
                .artificialAnalysisCodingAgent,
                .artificialAnalysisTextToImage,
                .artificialAnalysisTextToVideo,
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let boards = try XCTUnwrap(object["boards"] as? [String: Any])
        XCTAssertNil(boards["aaCodingAgent"])
        XCTAssertNotNil(boards["artificialAnalysisCodingAgent"])
        XCTAssertNotNil(boards["artificialAnalysisTextToImage"])
        XCTAssertNotNil(boards["artificialAnalysisTextToVideo"])
    }
}

