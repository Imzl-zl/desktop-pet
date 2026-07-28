import XCTest
@testable import DesktopPetCore

final class AchievementTests: XCTestCase {

    // MARK: - Shared helpers (mirror PetCareTests pattern)

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }

    // MARK: - 1. First meal

    func testFirstMealUnlocksOnFirstFeeding() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        PetCare.recordMeal(state: &state, now: now, calendar: calendar)

        let newly = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)

        XCTAssertTrue(newly.contains(.firstMeal),
                      "first meal should unlock .firstMeal; got \(newly)")
    }

    // MARK: - 2. Level milestones

    func testLevelMilestones() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        // XP to reach internal level 6 (display level 5) = xpToReach(6) = 60*6*5 = 1800
        // Feed enough meals to exceed that XP threshold.
        let targetXP = PetCare.xpToReach(level: 6)   // 1800
        let mealsNeeded = Int(ceil(Double(targetXP) / Double(PetCare.mealXP)))
        for _ in 0..<mealsNeeded {
            PetCare.recordMeal(state: &state, now: now, calendar: calendar)
        }

        let newly = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)

        XCTAssertTrue(newly.contains(.level5),
                      "display level ≥ 5 should unlock .level5; got \(newly)")
    }

    // MARK: - 3. Token milestones

    func testTokenMilestones() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        // Feed 1M tokens total
        PetCare.feedTokens(1_000_000, state: &state, now: now, calendar: calendar)

        let newly = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)

        XCTAssertTrue(newly.contains(.tokens1M),
                      "1M total tokens should unlock .tokens1M; got \(newly)")
    }

    // MARK: - 4. Streak milestones

    func testStreakMilestones() {
        var state = PetCareState()
        // Simulate 7 consecutive days of feeding
        for day in 1...7 {
            let d = date(String(format: "2026-06-%02d 10:00", day))
            PetCare.recordMeal(state: &state, now: d, calendar: calendar)
        }
        let lastDay = date("2026-06-07 10:00")

        let newly = PetCare.unlockNewAchievements(state: &state, now: lastDay, calendar: calendar)

        XCTAssertTrue(newly.contains(.streak7),
                      "7-day streak should unlock .streak7; got \(newly)")
    }

    // MARK: - 5. Night owl

    func testNightOwl() {
        var state = PetCareState()
        // Feed at 2am UTC
        let nightTime = date("2026-06-18 02:00")
        PetCare.recordMeal(state: &state, now: nightTime, calendar: calendar)

        let newly = PetCare.unlockNewAchievements(state: &state, now: nightTime, calendar: calendar)

        XCTAssertTrue(newly.contains(.nightOwl),
                      "feeding at 2am should unlock .nightOwl; got \(newly)")
    }

    // MARK: - 6. No double unlock

    func testNoDoubleUnlock() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        PetCare.recordMeal(state: &state, now: now, calendar: calendar)

        // First call — should contain firstMeal
        let first = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)
        XCTAssertTrue(first.contains(.firstMeal))

        // Second call with same state — firstMeal is already stored, must not appear again
        let second = PetCare.unlockNewAchievements(state: &state, now: now, calendar: calendar)
        XCTAssertFalse(second.contains(.firstMeal),
                       "already-unlocked achievements must not be returned a second time")
    }

    // MARK: - 7. Backward compat

    func testBackwardCompat() throws {
        // JSON produced before unlockedAchievements field was added
        let legacy = """
        {"xp":200,"tokenCarry":0,"tokensToday":0,"mealsToday":0,\
        "totalTokens":200000,"totalMeals":5,"dayKey":"2026-06-18",\
        "streakDays":3}
        """
        let state = try JSONDecoder().decode(
            PetCareState.self,
            from: legacy.data(using: .utf8)!
        )
        XCTAssertNil(state.unlockedAchievements,
                     "legacy JSON without achievements field must decode to nil")
        XCTAssertEqual(state.xp, 200)
    }

    // MARK: - 8. checkAchievements is pure

    func testCheckAchievementsIsPure() {
        var state = PetCareState()
        let now = date("2026-06-18 10:00")
        PetCare.feedTokens(1_000_000, state: &state, now: now, calendar: calendar)

        let resultA = PetCare.checkAchievements(state: state, hour: 10)
        let resultB = PetCare.checkAchievements(state: state, hour: 10)

        XCTAssertEqual(resultA, resultB,
                       "checkAchievements must return identical sets for identical inputs")
        // State must not have been mutated
        XCTAssertNil(state.unlockedAchievements,
                     "checkAchievements must not mutate state")
    }
}
