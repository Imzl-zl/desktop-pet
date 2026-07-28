import XCTest
@testable import DesktopPetCore

/// Hook integration tests for the Factory Droid CLI (`droid`). Droid uses the
/// same nested `~/.factory/hooks.json` shape and snake_case stdin payload as
/// Claude Code, so it reuses the claudeNested installer and ClaudeHookPayload.
final class DroidHookTests: XCTestCase {

    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "desktoppet-test-\(UUID().uuidString)/\(name)"
    }

    func testDroidSpec() {
        let spec = AgentHooks.spec(for: .droid)!
        XCTAssertEqual(spec.style, .claudeNested)
        XCTAssertTrue(spec.settingsPath.hasSuffix("/.factory/hooks.json"))
        // Notification is Droid's permission/approval (human-in-the-loop) signal.
        XCTAssertTrue(spec.events.contains("Notification"))
        XCTAssertTrue(spec.events.contains("PreToolUse"))
        XCTAssertTrue(spec.events.contains("Stop"))
        XCTAssertTrue(spec.events.contains("SessionEnd"))
    }

    func testDroidInstallShapeAndRoundTrip() throws {
        let spec = AgentHooks.spec(for: .droid)!
        let path = tmp("hooks.json")
        let cmd = "\"/x/desktoppet\" hook --agent droid"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .claudeNested)
        let json = try HookInstaller.readSettings(path: path)
        // Nested Claude shape: hooks -> Notification -> [{ hooks: [{type, command}] }].
        let groups = (json["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]
        let inner = groups?.first?["hooks"] as? [[String: Any]]
        XCTAssertEqual(inner?.first?["type"] as? String, "command")
        XCTAssertTrue((inner?.first?["command"] as? String ?? "").contains("desktoppet"))
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .claudeNested))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .claudeNested)
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .claudeNested))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    func testDroidInstallPreservesForeignHooks() throws {
        let spec = AgentHooks.spec(for: .droid)!
        let path = tmp("hooks.json")
        // A user's own Notification hook must survive install + uninstall.
        let foreign: [String: Any] = ["hooks": ["Notification": [["hooks": [["type": "command", "command": "say hi"]]]]]]
        try HookInstaller.writeSettings(foreign, path: path)
        try HookInstaller.installToDisk(command: "\"/x/desktoppet\" hook --agent droid", path: path, events: spec.events, style: .claudeNested)
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .claudeNested)
        let notif = ((try HookInstaller.readSettings(path: path))["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]]
        let cmds = notif?.compactMap { ($0["hooks"] as? [[String: Any]])?.first?["command"] as? String } ?? []
        XCTAssertEqual(cmds, ["say hi"], "foreign Notification hook preserved after our round-trip")
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    func testDroidStates() {
        XCTAssertEqual(StateMapper.state(for: .droid, eventName: "SessionStart"), .registered)
        XCTAssertEqual(StateMapper.state(for: .droid, eventName: "UserPromptSubmit"), .working)
        XCTAssertEqual(StateMapper.state(for: .droid, eventName: "PreToolUse"), .working)
        XCTAssertEqual(StateMapper.state(for: .droid, eventName: "Notification"), .waiting)
        XCTAssertEqual(StateMapper.state(for: .droid, eventName: "Stop"), .done)
        // SubagentStop must not flip a finished session back to working.
        XCTAssertNil(StateMapper.state(for: .droid, eventName: "SubagentStop"))
    }

    func testDroidSessionEnd() {
        XCTAssertTrue(StateMapper.isSessionEnd(for: .droid, eventName: "SessionEnd"))
        XCTAssertFalse(StateMapper.isSessionEnd(for: .droid, eventName: "Stop"))
    }

    func testDroidPayloadDecodesWithKind() {
        let data = Data(#"{"session_id":"d1","cwd":"/proj","hook_event_name":"Notification","message":"Droid needs your permission to run a command","permission_mode":"off"}"#.utf8)
        let event = HookPayload.event(forAgent: .droid, stdin: data, now: Date())
        XCTAssertEqual(event?.agentKind, .droid)
        XCTAssertEqual(event?.eventName, "Notification")
        XCTAssertEqual(event?.sessionId, "d1")
        XCTAssertEqual(event?.project, "/proj")
    }

    func testDroidInCatalog() {
        let droid = AgentCatalog.all.first { $0.kind == .droid }
        XCTAssertNotNil(droid)
        XCTAssertTrue(droid?.isSupported ?? false)
        XCTAssertEqual(droid?.displayName, "Factory Droid")
    }
}
