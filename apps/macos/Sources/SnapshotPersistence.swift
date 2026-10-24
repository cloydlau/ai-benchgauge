import Foundation
import LeaderboardCore

/// One serial writer owns the encoder. While a write is in progress, retain
/// only the latest pending snapshot, so a fast source cannot queue large saves.
final class SnapshotPersistence: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.cloydlau.ai-benchgauge.snapshot", qos: .utility)
    private let write: (LeaderboardSnapshot) -> Void
    private var pending: LeaderboardSnapshot?
    private var scheduled = false

    init(cache: LeaderboardCache) {
        write = { cache.save($0) }
    }

    init(write: @escaping (LeaderboardSnapshot) -> Void) {
        self.write = write
    }

    func save(_ snapshot: LeaderboardSnapshot) {
        lock.lock()
        pending = snapshot
        guard !scheduled else { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        queue.async { self.drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let next = pending else {
                scheduled = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            autoreleasepool { write(next) }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}
