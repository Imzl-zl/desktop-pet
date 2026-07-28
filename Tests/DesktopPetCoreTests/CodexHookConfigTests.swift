import XCTest
@testable import DesktopPetCore

final class CodexHookConfigTests: XCTestCase {
    func testEmptyConfigAddsFeaturesTable() {
        let out = CodexHookConfig.enableHooks(in: "")
        XCTAssertEqual(out, "\n[features]\nhooks = true\n")
        XCTAssertTrue(CodexHookConfig.alreadyEnabled(out!))
    }

    func testAlreadyEnabledHooksIsNoOp() {
        XCTAssertNil(CodexHookConfig.enableHooks(in: "[features]\nhooks = true\n"))
    }

    func testCodexHooksAliasAloneStillAddsModernKey() {
        // `codex_hooks` is a deprecated alias recent Codex (Desktop 5.x) ignores,
        // so a config with only that must still get a real `hooks = true`.
        let out = CodexHookConfig.enableHooks(in: "[features]\ncodex_hooks = true\n")
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("hooks = true"))
        XCTAssertTrue(CodexHookConfig.alreadyEnabled(out!))
    }

    func testFlipsHooksFalseToTrue() {
        let out = CodexHookConfig.enableHooks(in: "[features]\nhooks = false\n")
        XCTAssertEqual(out, "[features]\nhooks = true\n")
    }

    func testFlipsCodexHooksFalseToTrueWithoutDuplicate() {
        let out = CodexHookConfig.enableHooks(in: "[features]\ncodex_hooks = false\n")!
        XCTAssertEqual(out.components(separatedBy: "true").count - 1, 1, "exactly one truthy flag, no duplicate")
        XCTAssertTrue(CodexHookConfig.alreadyEnabled(out))
    }

    func testInsertsUnderExistingFeaturesPreservingOtherKeys() {
        let out = CodexHookConfig.enableHooks(in: "model = \"o3\"\n\n[features]\nweb_search = true\n")!
        XCTAssertTrue(out.contains("hooks = true"))
        XCTAssertTrue(out.contains("web_search = true"), "existing key kept")
        XCTAssertTrue(out.contains("model = \"o3\""), "unrelated key kept")
        XCTAssertTrue(CodexHookConfig.alreadyEnabled(out))
    }

    func testAppendsFeaturesWhenAbsentPreservingContent() {
        let out = CodexHookConfig.enableHooks(in: "model = \"o3\"")!
        XCTAssertTrue(out.contains("model = \"o3\""))
        XCTAssertTrue(out.contains("[features]"))
        XCTAssertTrue(out.contains("hooks = true"))
    }

    func testCommentedFlagIsNotTreatedAsEnabled() {
        XCTAssertFalse(CodexHookConfig.alreadyEnabled("# hooks = true\n"))
    }
}
