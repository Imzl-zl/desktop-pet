import XCTest
@testable import DesktopPetCore

/// Hook integration tests for GitHub Copilot CLI and Kiro CLI. Verifies the
/// on-disk config shape matches each tool's documented format, that install is
/// idempotent + reversible, and that events map to the right states.
final class KiroCopilotHookTests: XCTestCase {

    private func tmp(_ name: String) -> String {
        NSTemporaryDirectory() + "desktoppet-test-\(UUID().uuidString)/\(name)"
    }

    // MARK: - GitHub Copilot (~/.copilot/hooks/*.json, cursor-flat shape)

    func testCopilotSpec() {
        let spec = AgentHooks.spec(for: .copilot)!
        XCTAssertEqual(spec.style, .cursorFlat)
        XCTAssertTrue(spec.settingsPath.hasSuffix("/.copilot/hooks/desktoppet.json"))
        // PreToolUse must NOT be registered: its command hook is fail-closed and
        // a crash there would block the user's tools.
        XCTAssertFalse(spec.events.contains("PreToolUse"))
        XCTAssertTrue(spec.events.contains("PostToolUse"))
        XCTAssertTrue(spec.events.contains("Stop"))
    }

    func testCopilotInstallShapeAndRoundTrip() throws {
        let spec = AgentHooks.spec(for: .copilot)!
        let path = tmp("desktoppet.json")
        let cmd = "\"/x/desktoppet\" hook --agent copilot"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .cursorFlat)
        let json = try HookInstaller.readSettings(path: path)
        XCTAssertEqual(json["version"] as? Int, 1)
        let stop = (json["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.first?["type"] as? String, "command")
        XCTAssertTrue((stop?.first?["command"] as? String ?? "").contains("desktoppet"))
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .cursorFlat))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .cursorFlat)
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .cursorFlat))
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    func testCopilotStates() {
        XCTAssertEqual(StateMapper.state(for: .copilot, eventName: "SessionStart"), .registered)
        XCTAssertEqual(StateMapper.state(for: .copilot, eventName: "PostToolUse"), .working)
        XCTAssertEqual(StateMapper.state(for: .copilot, eventName: "Stop"), .done)
    }

    func testCopilotPayloadDecodesWithKind() {
        let data = Data(#"{"session_id":"s1","cwd":"/proj","hook_event_name":"PostToolUse","tool_name":"bash"}"#.utf8)
        let event = HookPayload.event(forAgent: .copilot, stdin: data, now: Date())
        XCTAssertEqual(event?.agentKind, .copilot)
        XCTAssertEqual(event?.eventName, "PostToolUse")
        XCTAssertEqual(event?.sessionId, "s1")
    }

    // MARK: - Kiro CLI (~/.kiro/agents/default.json, hooks merged into agent)

    func testKiroSpec() {
        let spec = AgentHooks.spec(for: .kiroCLI)!
        XCTAssertEqual(spec.style, .kiroFlat)
        XCTAssertTrue(spec.settingsPath.hasSuffix("/.kiro/agents/default.json"))
        XCTAssertFalse(spec.events.contains("preToolUse"))
    }

    func testKiroInstallShapePreservesAgentFields() throws {
        let spec = AgentHooks.spec(for: .kiroCLI)!
        let path = tmp("default.json")
        // Pre-existing agent file with real fields that must survive.
        try HookInstaller.writeSettings(["name": "default", "prompt": "be helpful"], path: path)
        let cmd = "\"/x/desktoppet\" hook --agent kiroCLI"
        try HookInstaller.installToDisk(command: cmd, path: path, events: spec.events, style: .kiroFlat)
        let json = try HookInstaller.readSettings(path: path)
        XCTAssertEqual(json["name"] as? String, "default", "agent name preserved")
        XCTAssertEqual(json["prompt"] as? String, "be helpful", "agent prompt preserved")
        XCTAssertNil(json["version"], "Kiro agent file has no version field")
        let stop = (json["hooks"] as? [String: Any])?["stop"] as? [[String: Any]]
        XCTAssertEqual(stop?.count, 1)
        XCTAssertNil(stop?.first?["type"], "Kiro hook items are plain {command}")
        XCTAssertNil(stop?.first?["show_output"])
        XCTAssertTrue((stop?.first?["command"] as? String ?? "").contains("desktoppet"))
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .kiroFlat))
        try HookInstaller.uninstallFromDisk(path: path, events: spec.events, style: .kiroFlat)
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path, events: spec.events, style: .kiroFlat))
        XCTAssertEqual((try HookInstaller.readSettings(path: path))["name"] as? String, "default", "agent survives uninstall")
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    func testKiroSeedsNameWhenCreatingFresh() throws {
        let spec = AgentHooks.spec(for: .kiroCLI)!
        let path = tmp("default.json")
        try HookInstaller.installToDisk(command: "\"/x/desktoppet\" hook --agent kiroCLI", path: path, events: spec.events, style: .kiroFlat)
        XCTAssertEqual((try HookInstaller.readSettings(path: path))["name"] as? String, "default",
                       "a fresh Kiro agent file gets a name so it is a valid agent")
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    func testKiroStates() {
        XCTAssertEqual(StateMapper.state(for: .kiroCLI, eventName: "agentSpawn"), .registered)
        XCTAssertEqual(StateMapper.state(for: .kiroCLI, eventName: "postToolUse"), .working)
        XCTAssertEqual(StateMapper.state(for: .kiroCLI, eventName: "stop"), .done)
        // Tolerate PascalCase too, in case Kiro reports event names that way.
        XCTAssertEqual(StateMapper.state(for: .kiroCLI, eventName: "Stop"), .done)
    }
}
