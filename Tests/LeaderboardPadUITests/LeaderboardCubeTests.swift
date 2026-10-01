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
