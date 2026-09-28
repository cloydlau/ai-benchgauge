import Foundation
import LeaderboardCore
import Testing

struct LeaderboardCategoryTests {
    @Test
    func testCategoriesMapToTheirLeftAndRightBoards() {
        #expect((LeaderboardCategory.general.boardKinds) == ([.artificialAnalysis, .arenaText]))
        #expect((LeaderboardCategory.coding.boardKinds) == ([.artificialAnalysisCodingAgent, .codeArenaWebDev]))
        #expect((LeaderboardCategory.image.boardKinds) == ([.artificialAnalysisTextToImage, .arenaTextToImage]))
        #expect((LeaderboardCategory.video.boardKinds) == ([.artificialAnalysisTextToVideo, .arenaTextToVideo]))
    }

    @Test
    func testMediaCategoriesUseTextToImageAndTextToVideoSources() {
        #expect((LeaderboardKind.artificialAnalysisTextToImage.sourceURL.absoluteString) == ("https://artificialanalysis.ai/image/leaderboard/text-to-image"))
        #expect((LeaderboardKind.arenaTextToImage.sourceURL.absoluteString) == ("https://arena.ai/leaderboard/text-to-image"))
        #expect((LeaderboardKind.artificialAnalysisTextToVideo.sourceURL.absoluteString) == ("https://artificialanalysis.ai/video/leaderboard/text-to-video"))
        #expect((LeaderboardKind.arenaTextToVideo.sourceURL.absoluteString) == ("https://arena.ai/leaderboard/text-to-video"))
    }

    @Test
    func testCodingCategoryUsesDedicatedArtificialAnalysisSource() {
        #expect((LeaderboardKind.artificialAnalysisCodingAgent.sourceURL.absoluteString) == ("https://artificialanalysis.ai/agents/coding-agents"))
    }

    @Test
    func testCategoryPreferenceRestoresLastSelectionAndFallsBack() {
        let suite = "CategoryPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect((CategoryPreference.load(from: defaults)) == (.general))

        CategoryPreference.save(.video, to: defaults)
        #expect((CategoryPreference.load(from: defaults)) == (.video))

        defaults.set("not-a-category", forKey: CategoryPreference.userDefaultsKey)
        #expect((CategoryPreference.load(from: defaults)) == (.general))
        #expect((defaults.string(forKey: CategoryPreference.userDefaultsKey)) == nil)
    }

    @Test
    func testArtificialAnalysisLabelsUseTheFullName() {
        let kinds: [LeaderboardKind] = [
            .artificialAnalysis,
            .artificialAnalysisCodingAgent,
            .artificialAnalysisTextToImage,
            .artificialAnalysisTextToVideo,
        ]
        for kind in kinds {
            #expect((kind.sourcePrefix) == ("Artificial Analysis"))
            #expect(!(kind.sourceLinkTitle.contains("AA")))
            #expect(kind.sourceLinkTitle.hasPrefix("Artificial Analysis"))
        }
    }

    @Test
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

        #expect((Set(snapshot.boards.keys)) == ([
                .artificialAnalysisCodingAgent,
                .artificialAnalysisTextToImage,
                .artificialAnalysisTextToVideo,
            ]))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let boards = try #require(object["boards"] as? [String: Any])
        #expect((boards["aaCodingAgent"]) == nil)
        #expect((boards["artificialAnalysisCodingAgent"]) != nil)
        #expect((boards["artificialAnalysisTextToImage"]) != nil)
        #expect((boards["artificialAnalysisTextToVideo"]) != nil)
    }
}

