import LeaderboardCore
import XCTest

final class LeaderboardCategoryTests: XCTestCase {
    func testCategoriesMapToTheirLeftAndRightBoards() {
        XCTAssertEqual(LeaderboardCategory.general.boardKinds, [.artificialAnalysis, .arenaText])
        XCTAssertEqual(LeaderboardCategory.coding.boardKinds, [.artificialAnalysis, .codeArenaWebDev])
        XCTAssertEqual(LeaderboardCategory.image.boardKinds, [.aaTextToImage, .arenaTextToImage])
        XCTAssertEqual(LeaderboardCategory.video.boardKinds, [.aaTextToVideo, .arenaTextToVideo])
    }

    func testMediaCategoriesUseTextToImageAndTextToVideoSources() {
        XCTAssertEqual(
            LeaderboardKind.aaTextToImage.sourceURL.absoluteString,
            "https://artificialanalysis.ai/image/leaderboard/text-to-image"
        )
        XCTAssertEqual(
            LeaderboardKind.arenaTextToImage.sourceURL.absoluteString,
            "https://arena.ai/leaderboard/text-to-image"
        )
        XCTAssertEqual(
            LeaderboardKind.aaTextToVideo.sourceURL.absoluteString,
            "https://artificialanalysis.ai/video/leaderboard/text-to-video"
        )
        XCTAssertEqual(
            LeaderboardKind.arenaTextToVideo.sourceURL.absoluteString,
            "https://arena.ai/leaderboard/text-to-video"
        )
    }
}
