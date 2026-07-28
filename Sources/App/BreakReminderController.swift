// Sources/App/BreakReminderController.swift
import AppKit
import DesktopPetCore

/// Drives the break reminder: a low-rate timer reads whether the user is present
/// (input activity or an active agent), advances the pure `BreakClock`, and
/// nudges the default pet to rest when a break is due. The timer only runs while
/// the feature is enabled, so a disabled reminder costs nothing.
@MainActor
final class BreakReminderController {
    static let shared = BreakReminderController()

    private let clock = BreakClock()
    private let settings = BreakReminderSettings.shared
    private var timer: Timer?

    private static let tickInterval: TimeInterval = 60
    /// A gap larger than this between ticks means the machine slept / the app
    /// stalled — `BreakClock` resets instead of firing a stale break.
    private static let maxDelta: TimeInterval = 300

    func start() {
        settings.onChange = { [weak self] in self?.applyEnabled() }
        applyEnabled()
    }

    /// Starts or stops the tick timer to match the enabled flag, resetting the
    /// clock on every flip so a re-enable counts from zero.
    private func applyEnabled() {
        clock.reset()
        PetController.shared.cancelBreakRest()
        timer?.invalidate()
        timer = nil
        guard settings.enabled else { return }
        let t = Timer(timeInterval: Self.tickInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func config() -> BreakClockConfig {
        BreakClockConfig(
            enabled: settings.enabled,
            workInterval: TimeInterval(settings.workIntervalMinutes) * 60,
            breakLength: TimeInterval(settings.breakLengthMinutes) * 60,
            maxDelta: Self.maxDelta
        )
    }

    /// Present if the user generated input within the last tick OR an agent is
    /// actively running (you may be watching a long run without touching keys).
    private func isPresent() -> Bool {
        // kCGAnyInputEventType (UInt32.max) covers all input classes.
        let anyInput = CGEventType(rawValue: UInt32.max)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle < Self.tickInterval { return true }
        return AppDaemon.shared.sessions.contains { $0.state == .working || $0.state == .waiting }
    }

    private func tick() {
        switch clock.tick(now: Date(), isPresent: isPresent(), config: config()) {
        case .none:
            break
        case .breakDue:
            let mins = settings.workIntervalMinutes
            let brk = settings.breakLengthMinutes
            NotificationManager.shared.notify(
                title: "Time for a break",
                body: "You've worked \(mins) min — rest \(brk) min")
            NSSound(named: "Purr")?.play()
            PetController.shared.beginBreakRest(
                line: "Worked \(mins) min — let's rest \(brk) min")
        case .breakOver:
            PetController.shared.endBreakRest(line: "Break's over — back to it!")
        }
    }
}
