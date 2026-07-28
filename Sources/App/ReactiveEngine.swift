import Foundation
import Combine
import DesktopPetCore

// Re-export so test target (import desktoppet) can use PetHunger without importing DesktopPetCore directly
public typealias PetHunger = DesktopPetCore.PetHunger

// MARK: - ReactiveMetric

public enum ReactiveMetric: Hashable {
    case rateLimit
    case dailyTokens
    case sessionCount
    case hunger
    case streak
    case dailyMeals
}

// MARK: - Thresholds

private enum Thresholds {
    enum RateLimit {
        static let silent: Double = 0.5
        static let low: Double = 0.15
        static let high: Double = 0.05
    }
    enum DailyTokens {
        static let silent: Int = 1_000_000
        static let low: Int = 3_000_000
        static let mid: Int = 6_000_000
    }
    enum SessionCount {
        static let silent: Int = 5
        static let low: Int = 8
    }
    enum Streak {
        static let silent: Int = 4
        static let low: Int = 7
        static let mid: Int = 14
    }
    enum DailyMeals {
        static let silent: Int = 20
        static let low: Int = 50
        static let mid: Int = 100
    }
    enum Cooldown {
        static let sameMetric: TimeInterval = 600
        static let crossMetric: TimeInterval = 30
    }
    enum Hunger {
        static let dailyLimit: Int = 2
    }
}

// MARK: - Phrase Pools

private enum Phrases {
    static let rateLimitLow = ["Usage is climbing~", "Take it easy, no rush", "Keep an eye on quota"]
    static let rateLimitHigh = ["Rate limit running low…", "Use sparingly!", "Quota getting thin"]
    static let rateLimitCritical = ["Almost out of quota", "Maybe take a break…", "Quota nearly spent"]

    static let dailyTokensLow = ["Burned quite a few tokens today~", "Eaten a lot of tokens", "Token usage rising"]
    static let dailyTokensMid = ["Big appetite mode!", "Great appetite today~", "Tokens going fast"]
    static let dailyTokensHigh = ["Token usage off the charts today", "Token burn is extreme!", "Heavy burn today"]

    static let sessionCountLow = ["5 agents running at once~", "Lots of agents at work", "Parallelism is up"]
    static let sessionCountHigh = ["Command center mode", "So many sessions!", "Full throttle"]

    static let hungerLow = ["A little hungry…", "Hmm… want food", "Tummy rumbling"]
    static let hungerMid = ["Haven't been fed in a while", "Hungry…", "Want food…"]
    static let hungerHigh = ["Where did you go…", "About to faint from hunger", "So hungry"]

    static let streakLow = ["Days in a row! Keep going", "Going strong~", "Keeping it up"]
    static let streakMid = ["A whole week straight!", "Such persistence~", "So consistent"]
    static let streakHigh = ["Legendary streak!", "Incredible!", "Unstoppable"]

    static let dailyMealsLow = ["Lots of sessions today~", "Good productivity", "Got quite a bit done"]
    static let dailyMealsMid = ["Fifty sessions! Efficiency beast", "50+!", "Super productive"]
    static let dailyMealsHigh = ["Over 100! Not sleeping today?", "100+ sessions!", "Superhuman"]
}

// MARK: - CooldownTracker

private struct CooldownTracker {
    private var lastFiredAt: [ReactiveMetric: Date] = [:]
    private var lastAnyFiredAt: Date? = nil
    private var hungerDayKey: String = ""
    private var hungerDayCount: Int = 0

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func dayKey(for date: Date) -> String {
        let c = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Returns true if allowed to fire. Mutates state if allowed.
    mutating func check(metric: ReactiveMetric, now: Date) -> Bool {
        // Same-metric gate takes priority
        if let last = lastFiredAt[metric] {
            if now.timeIntervalSince(last) < Thresholds.Cooldown.sameMetric {
                return false
            }
        }

        // Cross-metric gate: only applies when a *different* metric fired most recently
        let lastAnyIsOtherMetric = lastAnyFiredAt != nil && lastAnyFiredAt != lastFiredAt[metric]
        if lastAnyIsOtherMetric,
           let lastAny = lastAnyFiredAt,
           now.timeIntervalSince(lastAny) < Thresholds.Cooldown.crossMetric {
            return false
        }

        // Hunger daily limit
        if metric == .hunger {
            let today = dayKey(for: now)
            if hungerDayKey != today {
                hungerDayKey = today
                hungerDayCount = 0
            }
            if hungerDayCount >= Thresholds.Hunger.dailyLimit { return false }
            hungerDayCount += 1
        }

        lastFiredAt[metric] = now
        lastAnyFiredAt = now
        return true
    }
}

// MARK: - ReactiveEngine

@MainActor
public final class ReactiveEngine {

    public static let shared = ReactiveEngine()

    private var cooldown = CooldownTracker()
    private var cancellables = Set<AnyCancellable>()

    public init() {}

    @discardableResult
    public func evaluate(metric: ReactiveMetric, value: AnyHashable?, now: Date = .now) -> String? {
        guard let phrases = phrasePool(metric: metric, value: value) else { return nil }
        guard BubbleSettings.shared.reactiveBubblesEnabled else { return nil }
        guard cooldown.check(metric: metric, now: now) else { return nil }
        guard let phrase = phrases.randomElement() else { return nil }
        return NSLocalizedString(phrase, comment: "reactive bubble")
    }

    // MARK: - Subscriptions

    public func start() {
        // Sink 1: OpenUsageClient
        OpenUsageClient.shared.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                let value = OpenUsageClient.shared.lowestFractionLeft
                if let line = self?.evaluate(metric: .rateLimit, value: value.map { AnyHashable($0) }) {
                    PetController.shared.flashReactiveLine(line)
                }
            }
            .store(in: &cancellables)

        // Sink 2: PetCareController (evaluates 4 metrics)
        PetCareController.shared.$states
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let care = PetCareController.shared
                let current = care.current

                // dailyTokens — use days[todayKey] for real value
                let todayKey = Self.todayKey()
                let realTokens = current.days?[todayKey] ?? 0
                if let line = self.evaluate(metric: .dailyTokens, value: AnyHashable(realTokens)) {
                    PetController.shared.flashReactiveLine(line)
                }

                // streak
                if let line = self.evaluate(metric: .streak, value: AnyHashable(current.streakDays)) {
                    PetController.shared.flashReactiveLine(line)
                }

                // dailyMeals
                if let line = self.evaluate(metric: .dailyMeals, value: AnyHashable(current.mealsToday)) {
                    PetController.shared.flashReactiveLine(line)
                }

                // hunger
                let hunger = care.hunger
                if let line = self.evaluate(metric: .hunger, value: AnyHashable(hunger)) {
                    PetController.shared.flashReactiveLine(line)
                }
            }
            .store(in: &cancellables)

        // Sink 3: AppDaemon sessions
        AppDaemon.shared.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                if let line = self?.evaluate(metric: .sessionCount, value: AnyHashable(sessions.count)) {
                    PetController.shared.flashReactiveLine(line)
                }
            }
            .store(in: &cancellables)
    }

    private static func todayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Tier resolution

    private func phrasePool(metric: ReactiveMetric, value: AnyHashable?) -> [String]? {
        switch metric {
        case .rateLimit:
            guard let v = value.flatMap({ $0.base as? Double }) else { return nil }
            if v > Thresholds.RateLimit.silent { return nil }
            if v > Thresholds.RateLimit.low { return Phrases.rateLimitLow }
            if v > Thresholds.RateLimit.high { return Phrases.rateLimitHigh }
            return Phrases.rateLimitCritical

        case .dailyTokens:
            guard let v = value.flatMap({ $0.base as? Int }) else { return nil }
            if v < Thresholds.DailyTokens.silent { return nil }
            if v < Thresholds.DailyTokens.low { return Phrases.dailyTokensLow }
            if v < Thresholds.DailyTokens.mid { return Phrases.dailyTokensMid }
            return Phrases.dailyTokensHigh

        case .sessionCount:
            guard let v = value.flatMap({ $0.base as? Int }) else { return nil }
            if v < Thresholds.SessionCount.silent { return nil }
            if v < Thresholds.SessionCount.low { return Phrases.sessionCountLow }
            return Phrases.sessionCountHigh

        case .hunger:
            guard let h = value.flatMap({ $0.base as? PetHunger }) else { return nil }
            switch h {
            case .full, .satisfied: return nil
            case .peckish: return Phrases.hungerLow
            case .hungry: return Phrases.hungerMid
            case .starving: return Phrases.hungerHigh
            }

        case .streak:
            guard let v = value.flatMap({ $0.base as? Int }) else { return nil }
            if v < Thresholds.Streak.silent { return nil }
            if v < Thresholds.Streak.low { return Phrases.streakLow }
            if v < Thresholds.Streak.mid { return Phrases.streakMid }
            return Phrases.streakHigh

        case .dailyMeals:
            guard let v = value.flatMap({ $0.base as? Int }) else { return nil }
            if v < Thresholds.DailyMeals.silent { return nil }
            if v < Thresholds.DailyMeals.low { return Phrases.dailyMealsLow }
            if v < Thresholds.DailyMeals.mid { return Phrases.dailyMealsMid }
            return Phrases.dailyMealsHigh
        }
    }
}

