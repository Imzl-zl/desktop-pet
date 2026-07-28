import Foundation

/// Deterministic per-key rate limiter. `shouldRun(_:now:)` returns `true` at
/// most once per `interval` for a given key, recording when it last allowed a
/// run. Free of wall-clock reads (callers pass `now`) so behaviour is testable.
///
/// Used to collapse per-event transcript work (title/model resolution) that
/// would otherwise re-read and re-parse the transcript on every hook event,
/// pegging the CPU during heavy agent activity.
public final class PerKeyThrottle {
    private let interval: TimeInterval
    private var lastRun: [String: Date] = [:]

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public func shouldRun(_ key: String, now: Date) -> Bool {
        if let last = lastRun[key], now.timeIntervalSince(last) < interval {
            return false
        }
        lastRun[key] = now
        return true
    }
}
