import Testing
@testable import LeaderboardPadUI

@Test func cubeScrollIntentAndBounds() {
    #expect(!LeaderboardCube.isHorizontal(x: 30, y: 80))
    #expect(!LeaderboardCube.isHorizontal(x: 30, y: 30))
    #expect(LeaderboardCube.isHorizontal(x: -80, y: 15))
    #expect(LeaderboardCube.position(face: 0, translation: 120, width: 300) == 0)
    #expect(LeaderboardCube.position(face: 1, translation: -120, width: 300) == 1)
    #expect(LeaderboardCube.position(face: 0, translation: -150, width: 300) == 0.5)
    #expect(LeaderboardCube.position(face: 1, translation: 150, width: 300) == 0.5)
    #expect(LeaderboardCube.position(face: 1, translation: 150, width: 0) == 1)
}
@Test func cubeSnapsOrCompletesQuickFlicksInBothDirections() {
    #expect(LeaderboardCube.destination(face: 0, translation: -80, predicted: -90, width: 300) == 0)
    #expect(LeaderboardCube.destination(face: 0, translation: -80, predicted: -200, width: 300) == 1)
    #expect(LeaderboardCube.destination(face: 1, translation: 80, predicted: 200, width: 300) == 0)
    #expect(LeaderboardCube.destination(face: 1, translation: 200, predicted: 80, width: 300) == 0)
    #expect(LeaderboardCube.destination(face: 1, translation: 50, predicted: 80, width: 300) == 1)
}

@Test func comparisonRankTracksViewportInsteadOfOffscreenRows() {
    let frames = [
        1: LeaderboardRankFrame(minY: -90, maxY: -46),
        2: LeaderboardRankFrame(minY: -46, maxY: -2),
        3: LeaderboardRankFrame(minY: -2, maxY: 42),
        4: LeaderboardRankFrame(minY: 42, maxY: 86),
        5: LeaderboardRankFrame(minY: 600, maxY: 644),
    ]
    #expect(LeaderboardCube.visibleRank(frames, height: 500) == 4)
    // A single long row may fill the entire visible area. Keep that row,
    // rather than selecting the next rank below the viewport.
    #expect(LeaderboardCube.visibleRank([
        1: LeaderboardRankFrame(minY: -100, maxY: 700),
        2: LeaderboardRankFrame(minY: 700, maxY: 744),
    ], height: 500) == 1)
    #expect(LeaderboardCube.visibleRank([:], height: 500) == nil)
    #expect(LeaderboardCube.visibleRank(frames, height: 0) == nil)
}
