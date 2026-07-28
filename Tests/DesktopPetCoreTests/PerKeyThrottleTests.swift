import XCTest
@testable import DesktopPetCore

final class PerKeyThrottleTests: XCTestCase {
    func testFirstCallForKeyRuns() {
        let throttle = PerKeyThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(throttle.shouldRun("a", now: t0), "the first call for a key must run")
    }

    func testSecondCallWithinIntervalIsSkipped() {
        let throttle = PerKeyThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = throttle.shouldRun("a", now: t0)
        XCTAssertFalse(throttle.shouldRun("a", now: t0.addingTimeInterval(9)),
                       "a call before the interval elapses must be skipped")
    }

    func testCallAfterIntervalRunsAgain() {
        let throttle = PerKeyThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = throttle.shouldRun("a", now: t0)
        XCTAssertTrue(throttle.shouldRun("a", now: t0.addingTimeInterval(10)),
                      "once the interval has elapsed the key runs again")
    }

    func testKeysAreIndependent() {
        let throttle = PerKeyThrottle(interval: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        _ = throttle.shouldRun("a", now: t0)
        XCTAssertTrue(throttle.shouldRun("b", now: t0),
                      "throttling one key must not block a different key")
    }
}
