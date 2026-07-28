import XCTest
@testable import desktoppet

@MainActor
final class ReactiveEngineTests: XCTestCase {

    private func makeEngine() -> ReactiveEngine {
        ReactiveEngine()
    }

    func testRateLimitAbove50PercentIsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.6)
        XCTAssertNil(result)
    }

    func testRateLimitBetween15And50PercentIsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.30)
        XCTAssertNotNil(result)
    }

    func testRateLimitBetween5And15PercentIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.10)
        XCTAssertNotNil(result)
    }

    func testRateLimitBelow5PercentIsCritical() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.03)
        XCTAssertNotNil(result)
    }

    func testRateLimitNilValueReturnsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: nil as Double?)
        XCTAssertNil(result)
    }

    func testDailyTokensBelow1MIsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyTokens, value: 800_000)
        XCTAssertNil(result)
    }

    func testDailyTokensBetween1MAnd3MIsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyTokens, value: 2_000_000)
        XCTAssertNotNil(result)
    }

    func testDailyTokensBetween3MAnd6MIsMid() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyTokens, value: 4_500_000)
        XCTAssertNotNil(result)
    }

    func testDailyTokensAbove6MIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyTokens, value: 7_000_000)
        XCTAssertNotNil(result)
    }

    func testSessionCount1To4IsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .sessionCount, value: 3)
        XCTAssertNil(result)
    }

    func testSessionCount5To7IsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .sessionCount, value: 6)
        XCTAssertNotNil(result)
    }

    func testSessionCount8OrMoreIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .sessionCount, value: 8)
        XCTAssertNotNil(result)
    }

    func testHungerFullIsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.full)
        XCTAssertNil(result)
    }

    func testHungerSatisfiedIsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.satisfied)
        XCTAssertNil(result)
    }

    func testHungerPeckishIsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.peckish)
        XCTAssertNotNil(result)
    }

    func testHungerHungryIsMid() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.hungry)
        XCTAssertNotNil(result)
    }

    func testHungerStarvingIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .hunger, value: PetHunger.starving)
        XCTAssertNotNil(result)
    }

    func testStreak1To3IsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 2)
        XCTAssertNil(result)
    }

    func testStreak4To6IsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 5)
        XCTAssertNotNil(result)
    }

    func testStreak7To13IsMid() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 10)
        XCTAssertNotNil(result)
    }

    func testStreak14OrMoreIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 14)
        XCTAssertNotNil(result)
    }

    func testDailyMealsBelow20IsSilent() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyMeals, value: 10)
        XCTAssertNil(result)
    }

    func testDailyMeals20To50IsLow() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyMeals, value: 35)
        XCTAssertNotNil(result)
    }

    func testDailyMeals50To100IsMid() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyMeals, value: 75)
        XCTAssertNotNil(result)
    }

    func testDailyMeals100OrMoreIsHigh() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .dailyMeals, value: 100)
        XCTAssertNotNil(result)
    }

    func testSameMetricBlockedWithin600Seconds() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let first = engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        XCTAssertNotNil(first)
        let secondNow = now.addingTimeInterval(599)
        let second = engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: secondNow)
        XCTAssertNil(second)
    }

    func testSameMetricAllowedAfter600Seconds() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        let laterNow = now.addingTimeInterval(600)
        let result = engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: laterNow)
        XCTAssertNotNil(result)
    }

    func testCrossMetricBlockedWithin30Seconds() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        let laterNow = now.addingTimeInterval(29)
        let result = engine.evaluate(metric: .sessionCount, value: 6, now: laterNow)
        XCTAssertNil(result)
    }

    func testCrossMetricAllowedAfter30Seconds() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        let laterNow = now.addingTimeInterval(30)
        let result = engine.evaluate(metric: .sessionCount, value: 6, now: laterNow)
        XCTAssertNotNil(result)
    }

    func testSameMetricGateTakesPriorityOverCrossMetricGate() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: now)
        let laterNow = now.addingTimeInterval(35)
        let result = engine.evaluate(metric: .dailyTokens, value: 2_000_000, now: laterNow)
        XCTAssertNil(result)
    }

    func testHungerDailyLimitBlocksThirdTriggerSameDay() {
        let engine = makeEngine()
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let t1 = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: base)
        XCTAssertNotNil(t1)
        let t2 = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: base.addingTimeInterval(600))
        XCTAssertNotNil(t2)
        let t3 = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: base.addingTimeInterval(1200))
        XCTAssertNil(t3)
    }

    func testHungerDailyLimitResetsNextDay() {
        let engine = makeEngine()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let day1 = formatter.date(from: "2026-06-17 10:00")!
        let day2 = formatter.date(from: "2026-06-18 10:00")!
        engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: day1)
        engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: day1.addingTimeInterval(600))
        let blocked = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: day1.addingTimeInterval(1200))
        XCTAssertNil(blocked)
        let tomorrow = engine.evaluate(metric: .hunger, value: PetHunger.hungry, now: day2)
        XCTAssertNotNil(tomorrow)
    }

    func testSilentTierReturnsNil() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: 0.9)
        XCTAssertNil(result)
    }

    func testNonSilentTierReturnsNonNilString() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .streak, value: 14)
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.isEmpty ?? true)
    }

    func testNilValueReturnsNil() {
        let engine = makeEngine()
        let result = engine.evaluate(metric: .rateLimit, value: nil as Double?)
        XCTAssertNil(result)
    }

    func testCooldownBlockReturnsNil() {
        let engine = makeEngine()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let first = engine.evaluate(metric: .streak, value: 14, now: now)
        XCTAssertNotNil(first)
        let second = engine.evaluate(metric: .streak, value: 14, now: now.addingTimeInterval(1))
        XCTAssertNil(second)
    }
}

private extension ReactiveEngine {
    @discardableResult
    func evaluate(metric: ReactiveMetric, value: Double?, now: Date = .now) -> String? {
        evaluate(metric: metric, value: value.map { AnyHashable($0) }, now: now)
    }

    @discardableResult
    func evaluate(metric: ReactiveMetric, value: Double, now: Date = .now) -> String? {
        evaluate(metric: metric, value: AnyHashable(value), now: now)
    }

    @discardableResult
    func evaluate(metric: ReactiveMetric, value: Int, now: Date = .now) -> String? {
        evaluate(metric: metric, value: AnyHashable(value), now: now)
    }

    @discardableResult
    func evaluate(metric: ReactiveMetric, value: PetHunger, now: Date = .now) -> String? {
        evaluate(metric: metric, value: AnyHashable(value), now: now)
    }
}
