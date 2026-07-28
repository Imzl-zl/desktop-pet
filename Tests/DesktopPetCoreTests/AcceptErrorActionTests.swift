import XCTest
@testable import DesktopPetCore

/// The accept loop must never spin a CPU core at 100% when `accept()` fails
/// repeatedly. `acceptErrorAction` classifies the errno so the loop knows
/// whether to retry, back off, or stop.
final class AcceptErrorActionTests: XCTestCase {
    func testInterruptedRetriesImmediately() {
        XCTAssertEqual(EventSocketServer.acceptErrorAction(errno: EINTR), .retryImmediately)
    }

    func testConnectionAbortedRetriesImmediately() {
        XCTAssertEqual(EventSocketServer.acceptErrorAction(errno: ECONNABORTED), .retryImmediately)
    }

    func testFileDescriptorExhaustionBacksOff() {
        XCTAssertEqual(EventSocketServer.acceptErrorAction(errno: EMFILE), .backoff)
        XCTAssertEqual(EventSocketServer.acceptErrorAction(errno: ENFILE), .backoff)
    }

    func testBadListenSocketStops() {
        XCTAssertEqual(EventSocketServer.acceptErrorAction(errno: EBADF), .stop)
        XCTAssertEqual(EventSocketServer.acceptErrorAction(errno: EINVAL), .stop)
        XCTAssertEqual(EventSocketServer.acceptErrorAction(errno: ENOTSOCK), .stop)
    }

    func testUnknownErrorBacksOffRatherThanSpinning() {
        // An unrecognised errno must never fall through to a tight retry loop.
        XCTAssertEqual(EventSocketServer.acceptErrorAction(errno: 9999), .backoff)
    }
}
