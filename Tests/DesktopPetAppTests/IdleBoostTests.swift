import XCTest
@testable import desktoppet

final class IdleBoostTests: XCTestCase {
    func testLinesKeepPolishedDeveloperTone() {
        XCTAssertTrue(IdleBoost.lines.contains("Let's grill some bugs."))
        XCTAssertTrue(IdleBoost.lines.contains("I miss you. Open a branch for me."))
        XCTAssertTrue(IdleBoost.lines.contains("Tiny commit, tiny dopamine."))
    }

    func testLinesAvoidNoisyPunctuationAndEmoji() {
        for line in IdleBoost.lines {
            XCTAssertFalse(line.contains("!"), line)
            XCTAssertTrue(line.allSatisfy(\.isASCII), line)
        }
    }

    func testLineSelectionIsStableInsideSameMinute() {
        let now = Date(timeIntervalSince1970: 120)

        XCTAssertEqual(
            IdleBoost.line(at: now),
            IdleBoost.line(at: now.addingTimeInterval(59))
        )
    }

    func testLineSelectionRotatesAcrossMinutes() {
        let first = IdleBoost.line(at: Date(timeIntervalSince1970: 0))
        let later = IdleBoost.line(at: Date(timeIntervalSince1970: 60))

        XCTAssertNotEqual(first, later)
    }
}
