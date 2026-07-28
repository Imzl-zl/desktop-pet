// Tests/DesktopPetCoreTests/BreakClockTests.swift
import XCTest
@testable import DesktopPetCore

final class BreakClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)
    private func cfg(enabled: Bool = true, work: TimeInterval, brk: TimeInterval,
                     maxDelta: TimeInterval = 300) -> BreakClockConfig {
        BreakClockConfig(enabled: enabled, workInterval: work, breakLength: brk, maxDelta: maxDelta)
    }

    func testFiresBreakDueAfterWorkInterval() {
        let c = BreakClock()
        let k = cfg(work: 120, brk: 30)
        XCTAssertEqual(c.tick(now: t0, isPresent: true, config: k), .none)        // active 0
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k), .none)  // active 60
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(120), isPresent: true, config: k), .breakDue) // active 120
    }

    func testAbsenceResetsClockSoNoNagAfterLunch() {
        let c = BreakClock()
        let k = cfg(work: 120, brk: 30)
        _ = c.tick(now: t0, isPresent: true, config: k)                       // active 0
        _ = c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k) // active 60
        _ = c.tick(now: t0.addingTimeInterval(75), isPresent: false, config: k) // absence 15
        _ = c.tick(now: t0.addingTimeInterval(90), isPresent: false, config: k) // absence 30 → reset
        // back, present again: clock restarted, must NOT be due
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(105), isPresent: true, config: k), .none)
    }

    func testFiresBreakOverAfterBreakLength() {
        let c = BreakClock()
        let k = cfg(work: 60, brk: 30)
        _ = c.tick(now: t0, isPresent: true, config: k)                        // active 0
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k), .breakDue) // resting since +60
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(80), isPresent: true, config: k), .none)     // 20 < 30
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(90), isPresent: true, config: k), .breakOver) // 30 >= 30
    }

    func testHugeDeltaResetsAndDoesNotFire() {
        let c = BreakClock()
        let k = cfg(work: 120, brk: 30, maxDelta: 300)
        _ = c.tick(now: t0, isPresent: true, config: k)
        _ = c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k)  // active 60
        // machine slept 600s > maxDelta → reset, no break
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(660), isPresent: true, config: k), .none)
        _ = c.tick(now: t0.addingTimeInterval(720), isPresent: true, config: k) // active 60
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(780), isPresent: true, config: k), .breakDue) // active 120
    }

    func testDisabledNeverFires() {
        let c = BreakClock()
        let k = cfg(enabled: false, work: 1, brk: 1)
        XCTAssertEqual(c.tick(now: t0, isPresent: true, config: k), .none)
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(10_000), isPresent: true, config: k), .none)
    }

    func testIntervalShrinkMidFlightFiresNextTick() {
        let c = BreakClock()
        var k = cfg(work: 600, brk: 30)
        _ = c.tick(now: t0, isPresent: true, config: k)
        _ = c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k)   // active 60
        _ = c.tick(now: t0.addingTimeInterval(120), isPresent: true, config: k)  // active 120
        k.workInterval = 100
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(180), isPresent: true, config: k), .breakDue) // 180 >= 100
    }

    func testShortAbsenceKeepsAccumulatedTime() {
        let c = BreakClock()
        let k = cfg(work: 120, brk: 60)
        _ = c.tick(now: t0, isPresent: true, config: k)                         // active 0
        _ = c.tick(now: t0.addingTimeInterval(60), isPresent: true, config: k)  // active 60
        _ = c.tick(now: t0.addingTimeInterval(75), isPresent: false, config: k) // absence 15 (<60), active kept
        _ = c.tick(now: t0.addingTimeInterval(90), isPresent: true, config: k)  // active 60+15=75
        XCTAssertEqual(c.tick(now: t0.addingTimeInterval(135), isPresent: true, config: k), .breakDue) // 75+45=120
    }
}
