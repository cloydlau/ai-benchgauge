import Testing
import Combine
import Foundation
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

@Test func cubeLocksScrollIntentUntilTheTouchEndsAndIgnoresSidewaysJitter() {
    for sign in [-1.0, 1.0] {
        var axis = LeaderboardCube.dragAxis(current: .undecided, x: sign * 10, y: 3)
        #expect(axis == .undecided)
        axis = LeaderboardCube.dragAxis(current: axis, x: sign * 15, y: 12)
        #expect(axis == .vertical)
        axis = LeaderboardCube.dragAxis(current: axis, x: sign * 220, y: 40)
        #expect(axis == .vertical)
        #expect(LeaderboardCube.dragAxis(current: .undecided, x: sign * 20, y: 4) == .horizontal)
        #expect(LeaderboardCube.dragAxis(current: .undecided, x: sign * 30, y: 20) == .vertical)
        #expect(LeaderboardCube.dragAxis(current: .horizontal, x: 40, y: 100) == .horizontal)
    }
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

@Test @MainActor func cubeEntranceRunsOnlyOnceAndReturnsToItsOriginalFace() {
    let cube = LeaderboardCubeState()
    let serial = cube.beginEntrance(reduceMotion: false)!
    #expect(cube.entranceActive && cube.entranceHintVisible)
    #expect(cube.position > 0 && cube.position < 0.5)
    #expect(cube.face == 0 && cube.scroll.rank == nil)
    cube.settleEntrance(serial)
    #expect(!cube.entranceActive && cube.entranceHintVisible)
    cube.finishEntrance(serial)
    #expect(cube.position == 0 && cube.entranceProgress == 1)
    #expect(!cube.entranceHintVisible)
    #expect(cube.beginEntrance(reduceMotion: false) == nil)
}

@Test @MainActor func cancellingEntranceInvalidatesPendingStepsWithoutOverwritingUserNavigation() {
    let cube = LeaderboardCubeState()
    let serial = cube.beginEntrance(reduceMotion: false)!
    cube.finishEntrance()
    cube.face = 1
    cube.position = 1
    #expect(!cube.isCurrentEntrance(serial))
    cube.settleEntrance(serial)
    cube.finishEntrance(serial)
    #expect(cube.position == 1 && cube.face == 1)
    #expect(cube.beginEntrance(reduceMotion: false) == nil)
}

@Test @MainActor func interactingBeforeContentArrivesConsumesEntranceWithoutMovingTheBoard() {
    let cube = LeaderboardCubeState()
    cube.finishEntrance()
    #expect(cube.beginEntrance(reduceMotion: false) == nil)
    #expect(cube.position == 0 && cube.entranceProgress == 1)
}

@Test @MainActor func reducedMotionEntranceShowsTheHintWithoutRotatingAndDoesNotInterruptTurns() {
    let cube = LeaderboardCubeState()
    cube.turning = true
    #expect(cube.beginEntrance(reduceMotion: true) == nil)
    #expect(!cube.entrancePlayed)
    cube.turning = false
    let serial = cube.beginEntrance(reduceMotion: true)!
    #expect(cube.position == 0 && cube.entranceHintVisible)
    cube.finishEntrance(serial)
    #expect(cube.position == 0 && cube.entranceProgress == 1)
}

@Test func comparisonRankExcludesRowsCoveredByPinnedColumnHeaders() {
    let frames = [
        1: LeaderboardRankFrame(minY: -20, maxY: 24),
        2: LeaderboardRankFrame(minY: 24, maxY: 68),
        3: LeaderboardRankFrame(minY: 68, maxY: 112),
    ]
    #expect(LeaderboardCube.visibleRank(frames, height: 500, topInset: 40) == 2)
    #expect(LeaderboardCube.visibleRank(frames, height: 40, topInset: 40) == nil)
}

@Test @MainActor func continuousScrollingDoesNotInvalidateTheCubeOrRepeatHiddenTabUpdates() {
    let cube = LeaderboardCubeState()
    var cubeUpdates = 0
    var overlayUpdates = 0
    let cubeSubscription = cube.objectWillChange.sink { cubeUpdates += 1 }
    let scrollSubscription = cube.scroll.objectWillChange.sink { overlayUpdates += 1 }
    defer { cubeSubscription.cancel(); scrollSubscription.cancel() }

    // Three seconds of geometry at 120 Hz, crossing many comparison rows.
    var frames: [Int: LeaderboardRankFrame] = [:]
    for frame in 0..<360 {
        let travel = CGFloat(frame * 4)
        frames = [0: LeaderboardRankFrame(minY: 48 - travel, maxY: 4000 - travel),
                  -1: LeaderboardRankFrame(minY: 0, maxY: 40)]
        for rank in 1...80 {
            let top = 200 + CGFloat((rank - 1) * 44) - travel
            frames[rank] = LeaderboardRankFrame(minY: top, maxY: top + 44)
        }
        cube.scroll.update(frames: frames, height: 700)
    }
    #expect(cubeUpdates == 0)
    #expect(overlayUpdates <= 14)
    #expect(cube.scroll.sourceTabsOffset == 48)
    #expect(cube.scroll.canReturnToTop)
    #expect(cube.scroll.rank == 30)
    #expect(cube.scroll.columnHeaderHeight == 40)
    #expect(cube.scroll.comparisonRowHeight == 44)

    let settledUpdates = overlayUpdates
    for _ in 0..<120 { cube.scroll.update(frames: frames, height: 700) }
    #expect(overlayUpdates == settledUpdates)
    cube.position = 1
    #expect(cubeUpdates == 1, "Cube animations must still notify their own observers")

    cube.scroll.reset()
    #expect(cube.scroll.rank == nil)
    #expect(cube.scroll.sourceTabsOffset == 0)
    #expect(!cube.scroll.canReturnToTop)
}

@Test @MainActor func comparisonScrollKeepsTopAndVariableRowHeightsWhenReturning() {
    let scroll = LeaderboardCubeScrollState()
    scroll.update(frames: [0: LeaderboardRankFrame(minY: -100, maxY: 1200),
        -1: LeaderboardRankFrame(minY: 0, maxY: 48),
        1: LeaderboardRankFrame(minY: -50, maxY: 30),
        2: LeaderboardRankFrame(minY: 30, maxY: 110)], height: 700)
    #expect(scroll.rank == 2 && scroll.canReturnToTop)
    #expect(scroll.comparisonRowHeight == 80)
    scroll.update(frames: [0: LeaderboardRankFrame(minY: 48, maxY: 1400)], height: 700)
    #expect(scroll.rank == 0 && !scroll.canReturnToTop)
    #expect(scroll.sourceTabsOffset == 0)
}
