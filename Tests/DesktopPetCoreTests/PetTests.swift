import XCTest
@testable import DesktopPetCore

final class MoodResolverTests: XCTestCase {
    private func session(_ state: AgentState, id: String) -> AgentSession {
        AgentSession(id: id, agentKind: .claude, state: state, source: .hook,
                     updatedAt: Date(timeIntervalSince1970: 0))
    }

    func testEmptyIsIdle() {
        XCTAssertEqual(MoodResolver.aggregate([]), .idle)
    }

    func testWorkingWins() {
        let sessions = [session(.working, id: "a"), session(.waiting, id: "b"), session(.done, id: "c")]
        XCTAssertEqual(MoodResolver.aggregate(sessions), .working, "running work is prioritised")
    }

    func testWaitingBeatsDone() {
        XCTAssertEqual(MoodResolver.aggregate([session(.done, id: "a"), session(.waiting, id: "b")]), .waiting)
    }

    func testRegisteredIsNotWorking() {
        // An agent that is merely open (registered) but not doing anything keeps
        // the pet idle, not "working".
        XCTAssertEqual(MoodResolver.aggregate([session(.registered, id: "a")]), .idle)
        XCTAssertEqual(MoodResolver.aggregate([session(.registered, id: "a"), session(.working, id: "b")]), .working)
    }

    func testDoneOnly() {
        XCTAssertEqual(MoodResolver.aggregate([session(.done, id: "a"), session(.idle, id: "b")]), .done)
    }
}
