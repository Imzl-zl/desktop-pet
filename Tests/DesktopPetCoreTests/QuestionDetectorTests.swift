import XCTest
@testable import DesktopPetCore

final class QuestionDetectorTests: XCTestCase {
    func testEndsWithQuestionMark() {
        XCTAssertTrue(QuestionDetector.looksLikeQuestion("Which approach do you prefer, A or B?"))
    }

    func testTrailingWhitespaceAfterQuestionMarkStillDetected() {
        XCTAssertTrue(QuestionDetector.looksLikeQuestion("Want me to push this too?  \n"))
    }

    func testDirectQuestionWithoutQuestionMark() {
        XCTAssertTrue(QuestionDetector.looksLikeQuestion(
            "Should I go ahead and run the migration now"))
    }

    func testCompletionWithPoliteFollowUpIsNotAQuestion() {
        XCTAssertFalse(QuestionDetector.looksLikeQuestion(
            "I've made the change. Let me know if you'd like any tweaks."))
        XCTAssertFalse(QuestionDetector.looksLikeQuestion(
            "Fixed the spinner and rebuilt the app. Let me know if you need anything else."))
        XCTAssertFalse(QuestionDetector.looksLikeQuestion(
            "All done — shipped the fix. Feel free to ask if you want adjustments."))
    }

    func testCompletionWithActionQuestionInLastSentence() {
        XCTAssertTrue(QuestionDetector.looksLikeQuestion(
            "Fixed the spinner and rebuilt the app. Want me to open it?"))
        XCTAssertTrue(QuestionDetector.looksLikeQuestion(
            "Implemented both dot styles. Which one do you prefer — plain or Claude style?"))
    }

    func testPlainCompletionStatementIsNotAQuestion() {
        XCTAssertFalse(QuestionDetector.looksLikeQuestion(
            "Done — fixed the login bug and added a regression test."))
    }

    func testEmptyAndWhitespaceOnlyAreNotQuestions() {
        XCTAssertFalse(QuestionDetector.looksLikeQuestion(""))
        XCTAssertFalse(QuestionDetector.looksLikeQuestion("   \n  "))
    }
}
