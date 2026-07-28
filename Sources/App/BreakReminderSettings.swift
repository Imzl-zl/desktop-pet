// Sources/App/BreakReminderSettings.swift
import Foundation

/// User config for the break reminder (tab General). UserDefaults-backed and
/// `@Published`, matching the other settings objects. `onChange` lets the
/// controller (re)start its timer whenever a value flips.
@MainActor
final class BreakReminderSettings: ObservableObject {
    static let shared = BreakReminderSettings()

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); onChange?() }
    }
    @Published var workIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(workIntervalMinutes, forKey: Self.workKey); onChange?() }
    }
    @Published var breakLengthMinutes: Int {
        didSet { UserDefaults.standard.set(breakLengthMinutes, forKey: Self.breakKey); onChange?() }
    }

    /// Invoked on any change so `BreakReminderController` can react.
    var onChange: (() -> Void)?

    private static let enabledKey = "desktoppet.breakReminder.enabled"
    private static let workKey = "desktoppet.breakReminder.workIntervalMinutes"
    private static let breakKey = "desktoppet.breakReminder.breakLengthMinutes"

    init() {
        let d = UserDefaults.standard
        enabled = (d.object(forKey: Self.enabledKey) as? Bool) ?? false
        workIntervalMinutes = (d.object(forKey: Self.workKey) as? Int) ?? 90
        breakLengthMinutes = (d.object(forKey: Self.breakKey) as? Int) ?? 5
    }
}
