import Foundation
import LeaderboardCore
import Testing

struct LeaderboardCategoryTests {
    @Test
    func testCategoriesMapToTheirLeftAndRightBoards() {
        #expect((LeaderboardCategory.general.boardKinds) == ([.artificialAnalysis, .arenaText, .epochECI]))
        #expect((LeaderboardCategory.coding.boardKinds) == ([.artificialAnalysisCodingAgent, .codeArenaWebDev, .epochSoftwareECI]))
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
    func testLegacyPricePreferenceMigratesToUsage() {
        let suite = "CategoryPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(LeaderboardCategory.price.rawValue, forKey: CategoryPreference.userDefaultsKey)
        #expect(CategoryPreference.load(from: defaults) == .usage)
    }

    @Test
    func testSettingsUseLocalizedTaskNamesAndSources() {
        for (kind, english, chinese, traditional) in [
            (LeaderboardKind.artificialAnalysis, "Artificial Analysis General", "Artificial Analysis 综合", "Artificial Analysis 綜合"),
            (.artificialAnalysisCodingAgent, "Artificial Analysis Coding", "Artificial Analysis 编程", "Artificial Analysis 編程"),
            (.artificialAnalysisTextToImage, "Artificial Analysis Image", "Artificial Analysis 图片", "Artificial Analysis 圖片"),
            (.artificialAnalysisImageEditing, "Artificial Analysis Image", "Artificial Analysis 图片", "Artificial Analysis 圖片"),
            (.artificialAnalysisTextToVideo, "Artificial Analysis Video", "Artificial Analysis 视频", "Artificial Analysis 影片"),
            (.artificialAnalysisImageToVideo, "Artificial Analysis Video", "Artificial Analysis 视频", "Artificial Analysis 影片"),
            (.artificialAnalysisVideoEditing, "Artificial Analysis Video", "Artificial Analysis 视频", "Artificial Analysis 影片"),
            (.arenaText, "Arena Text", "Arena 文本", "Arena 文本"),
            (.codeArenaWebDev, "Arena Coding", "Arena 编程", "Arena 編程"),
            (.arenaTextToImage, "Text to Image Arena", "Arena 文生图", "Arena 文生圖"),
            (.arenaTextToVideo, "Text to Video Arena", "Arena 文生视频", "Arena 文生影片"),
            (.artificialAnalysisSpeechProviderVoice, "Artificial Analysis Speech", "Artificial Analysis 语音", "Artificial Analysis 語音"),
            (.epochECI, "Epoch ECI General", "Epoch ECI 综合", "Epoch ECI 綜合"),
            (.epochMathECI, "Epoch ECI Math", "Epoch ECI 数学", "Epoch ECI 數學"),
            (.epochCyberECI, "Epoch ECI Cybersecurity", "Epoch ECI 网络安全", "Epoch ECI 網路安全"),
            (.epochSoftwareECI, "Epoch ECI Software engineering", "Epoch ECI 软件工程", "Epoch ECI 軟體工程"),
        ] {
            #expect(LeaderboardPresentation.boardSelectionTitle(kind, language: .english) == english)
            #expect(LeaderboardPresentation.boardSelectionTitle(kind, language: .chinese) == chinese)
            #expect(LeaderboardPresentation.boardSelectionTitle(kind, language: .traditionalChinese) == traditional)
        }
        #expect(LeaderboardPresentation.columnTitle(.arenaText, language: .chinese) == "Arena")
        #expect(LeaderboardKind.epochMathECI.mediaVariantTitle(language: .chinese) == "数学")
    }

    @Test
    func testArenaTextAndCodingSourceTitlesOmitCategoryPrefixes() {
        for kind in [LeaderboardKind.arenaText, .arenaTextUncontrolled, .codeArenaWebDev, .codeArenaImageToWebDev] {
            #expect(kind.sourceLinkTitle == "Arena")
            for language in AppLanguage.allCases {
                #expect(LeaderboardPresentation.columnTitle(kind, language: language) == "Arena")
                #expect(LeaderboardPresentation.title(kind, language: language).hasPrefix("Arena | "))
            }
        }
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

