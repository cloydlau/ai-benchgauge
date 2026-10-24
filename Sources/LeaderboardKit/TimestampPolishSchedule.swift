import Foundation

/// A completed load starts one short pass, even when the timestamp is unchanged.
/// Ordinary view updates preserve the thirty-second cadence.
public struct TimestampPolishSchedule {
    public static let interval: TimeInterval = 30
    public static let duration: TimeInterval = 1.1
    public private(set) var startedAt: TimeInterval?

    public init() {}

    @discardableResult public mutating func update(now: TimeInterval, ready: Bool) -> Bool {
        guard ready else { startedAt = nil; return false }
        if let startedAt, now - startedAt < Self.interval { return false }
        startedAt = now
        return true
    }

    public func phase(at now: TimeInterval) -> Double? {
        guard let startedAt, now >= startedAt, now - startedAt < Self.duration else { return nil }
        return (now - startedAt) / Self.duration
    }
}
