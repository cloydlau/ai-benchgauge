import Foundation
import Testing
import LeaderboardCore
@testable import leaderboard_menu

@MainActor
struct SnapshotPersistenceTests {
    private final class Writes: @unchecked Sendable {
        private let lock = NSLock()
        private var dates: [Date] = []
        private var mainThreads: [Bool] = []
        func record(_ value: LeaderboardSnapshot) {
            lock.lock(); defer { lock.unlock() }
            dates.append(value.boards[.artificialAnalysis]!.fetchedAt)
            mainThreads.append(Thread.isMainThread)
        }
        func read() -> ([Date], [Bool]) { lock.lock(); defer { lock.unlock() }; return (dates, mainThreads) }
    }
    private func snapshot(_ value: TimeInterval) -> LeaderboardSnapshot {
        .init(boards: [.artificialAnalysis: .init(kind: .artificialAnalysis, title: "Fixture", fetchedAt: Date(timeIntervalSince1970: value), entries: [])])
    }

    @Test func savesRunOffTheMainThreadAndCoalesceToTheLatestPendingSnapshot() async {
        let writes = Writes(), release = DispatchSemaphore(value: 0)
        let (started, signal) = AsyncStream<Void>.makeStream()
        let writer = SnapshotPersistence { value in
            writes.record(value)
            if value.boards[.artificialAnalysis]?.fetchedAt == Date(timeIntervalSince1970: 1) {
                signal.yield(())
                _ = release.wait(timeout: .now() + 5)
            }
        }
        writer.save(snapshot(1))
        for await _ in started { break }
        for value in 2...10 { writer.save(snapshot(Double(value))) }
        release.signal()
        await writer.flush()
        signal.finish()
        let (dates, mainThreads) = writes.read()
        #expect(dates == [Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 10)])
        #expect(mainThreads == [false, false])
        writer.save(snapshot(11))
        await writer.flush()
        #expect(writes.read().0.last == Date(timeIntervalSince1970: 11))
    }

    @Test func theFinalQueuedSnapshotRoundTripsThroughTheExistingAtomicCacheFormat() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "snapshot-writer-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = LeaderboardCache(fileURL: url), writer = SnapshotPersistence(cache: cache)
        writer.save(snapshot(1))
        writer.save(snapshot(2))
        await writer.flush()
        #expect(cache.load() == snapshot(2))
    }
}
