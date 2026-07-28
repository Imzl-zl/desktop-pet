import XCTest
@testable import DesktopPetCore

final class TickerFormatterTests: XCTestCase {

    // MARK: agentLabel

    func testAgentLabelKnownKinds() {
        XCTAssertEqual(TickerFormatter.agentLabel(for: .claude),   "Claude")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .cursor),   "Cursor")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .codex),    "Codex")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .gemini),   "Gemini")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .opencode), "Opencode")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .windsurf), "Windsurf")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .antigravity), "Antigravity")
    }

    func testAgentLabelFallbacks() {
        XCTAssertEqual(TickerFormatter.agentLabel(for: .cli),     "Agent")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .unknown), "Agent")
    }

    // MARK: line(for:)

    func testLineWithMessage() {
        let session = AgentSession(
            id: "claude-abc",
            agentKind: .claude,
            project: "/Users/me/desktoppet",
            state: .working,
            message: "running bash…",
            source: .hook,
            updatedAt: Date()
        )
        XCTAssertEqual(TickerFormatter.line(for: session), "Claude [desktoppet] → running bash…")
    }

    func testLineWithoutMessage() {
        let session = AgentSession(
            id: "cursor-xyz",
            agentKind: .cursor,
            project: "/Users/me/my-api",
            state: .waiting,
            message: nil,
            source: .hook,
            updatedAt: Date()
        )
        XCTAssertEqual(TickerFormatter.line(for: session), "Cursor [my-api] → Waiting")
    }

    func testLineWithWhitespaceOnlyMessage() {
        let session = AgentSession(
            id: "gemini-1",
            agentKind: .gemini,
            project: "/Users/me/frontend",
            state: .working,
            message: "   ",
            source: .hook,
            updatedAt: Date()
        )
        XCTAssertEqual(TickerFormatter.line(for: session), "Gemini [frontend] → Working")
    }

    func testLineFallsBackToIdWhenNoProject() {
        let session = AgentSession(
            id: "my-session-id",
            agentKind: .cli,
            project: nil,
            state: .working,
            message: "running",
            source: .hook,
            updatedAt: Date()
        )
        XCTAssertEqual(TickerFormatter.line(for: session), "Agent [my-session-id] → running")
    }

    // MARK: sorted(_:)

    func testSortedWaitingFirst() {
        let t = Date()
        let working = AgentSession(id: "a", agentKind: .claude, state: .working, source: .hook, updatedAt: t)
        let waiting = AgentSession(id: "b", agentKind: .cursor, state: .waiting, source: .hook, updatedAt: t)
        let done    = AgentSession(id: "c", agentKind: .codex,  state: .done,    source: .hook, updatedAt: t)

        let result = TickerFormatter.sorted([done, working, waiting])
        XCTAssertEqual(result.map(\.id), ["b", "a", "c"])
    }

    func testSortedWorkingByMostRecentFirst() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 10)
        let older = AgentSession(id: "old",   agentKind: .claude, state: .working, source: .hook, updatedAt: t0)
        let newer = AgentSession(id: "newer", agentKind: .cursor, state: .working, source: .hook, updatedAt: t1)

        let result = TickerFormatter.sorted([older, newer])
        XCTAssertEqual(result.first?.id, "newer", "most recently updated working agent comes first")
    }
}
