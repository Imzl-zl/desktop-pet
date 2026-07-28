// Sources/DesktopPetCore/BreakClock.swift
import Foundation

/// Config for `BreakClock`. The app layer rebuilds this from settings each tick
/// so changes apply immediately.
public struct BreakClockConfig: Equatable, Sendable {
    public var enabled: Bool
    /// Seconds of continuous active work before a break is due.
    public var workInterval: TimeInterval
    /// Seconds the rest window lasts; also the absence that counts as a break taken.
    public var breakLength: TimeInterval
    /// A gap between ticks larger than this means the machine slept / the app
    /// stalled — treat as away, reset, and don't fire a stale break.
    public var maxDelta: TimeInterval

    public init(enabled: Bool, workInterval: TimeInterval,
                breakLength: TimeInterval, maxDelta: TimeInterval) {
        self.enabled = enabled
        self.workInterval = workInterval
        self.breakLength = breakLength
        self.maxDelta = maxDelta
    }
}

/// What a tick decided.
public enum BreakTick: Equatable, Sendable {
    case none
    case breakDue
    case breakOver
}

/// Pure, deterministic break-timing core. No wall-clock or IO reads — the caller
/// passes `now` and whether the user is present each tick (mirrors `SessionStore`
/// and `PerKeyThrottle`). Accumulates continuous active time; a long absence
/// resets the clock (counts as a break already taken), so it never nags after
/// the user steps away.
public final class BreakClock {
    private enum Phase: Equatable {
        case working
        case resting(since: Date)
    }

    private var phase: Phase = .working
    private var activeSeconds: TimeInterval = 0
    private var absenceSeconds: TimeInterval = 0
    private var lastTick: Date?

    public init() {}

    /// Clears all timing state (e.g. when the feature is toggled off / on).
    public func reset() {
        phase = .working
        activeSeconds = 0
        absenceSeconds = 0
        lastTick = nil
    }

    /// Advances the clock. `isPresent` = the user did something this tick (input
    /// or an active agent). Returns the action the driver should take.
    public func tick(now: Date, isPresent: Bool, config: BreakClockConfig) -> BreakTick {
        guard config.enabled else { reset(); return .none }

        let delta = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now

        // Sleep / long stall: treat as away, reset, no stale break.
        if delta > config.maxDelta {
            phase = .working
            activeSeconds = 0
            absenceSeconds = 0
            return .none
        }

        switch phase {
        case .resting(let since):
            if now.timeIntervalSince(since) >= config.breakLength {
                phase = .working
                activeSeconds = 0
                absenceSeconds = 0
                return .breakOver
            }
            return .none   // rest is rest; ignore presence during the window

        case .working:
            if isPresent {
                absenceSeconds = 0
                activeSeconds += delta
                if activeSeconds >= config.workInterval {
                    phase = .resting(since: now)
                    return .breakDue
                }
            } else {
                absenceSeconds += delta
                if absenceSeconds >= config.breakLength {   // auto-credit a break
                    activeSeconds = 0
                    absenceSeconds = 0
                }
            }
            return .none
        }
    }
}
