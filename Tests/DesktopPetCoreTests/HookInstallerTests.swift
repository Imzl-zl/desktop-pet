import XCTest
@testable import DesktopPetCore

final class HookInstallerTests: XCTestCase {
    private let cmd = "\"/Applications/DesktopPet.app/Contents/MacOS/desktoppet\" hook"

    private func groups(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
        (settings["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    func testInstallIntoEmptyAddsAllEvents() {
        let result = HookInstaller.install(into: [:], command: cmd)
        XCTAssertTrue(HookInstaller.isInstalled(in: result))
        for event in HookInstaller.events {
            XCTAssertEqual(groups(result, event).count, 1, "event \(event)")
        }
    }

    func testInstallIsIdempotent() {
        let once = HookInstaller.install(into: [:], command: cmd)
        let twice = HookInstaller.install(into: once, command: cmd)
        for event in HookInstaller.events {
            XCTAssertEqual(groups(twice, event).count, 1, "no duplicate on \(event)")
        }
    }

    func testInstallPreservesForeignHooks() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo done"]]]]],
        ]
        let result = HookInstaller.install(into: existing, command: cmd)
        XCTAssertEqual(groups(result, "Stop").count, 2, "foreign + ours")
    }

    func testUninstallRemovesOursKeepsForeign() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo done"]]]]],
        ]
        let installed = HookInstaller.install(into: existing, command: cmd)
        let removed = HookInstaller.uninstall(from: installed)
        XCTAssertFalse(HookInstaller.isInstalled(in: removed))
        XCTAssertEqual(groups(removed, "Stop").count, 1, "foreign hook survives")
        // Events that were only ours are dropped entirely.
        XCTAssertTrue(groups(removed, "SessionStart").isEmpty)
    }

    func testUninstallFromCleanIsNoop() {
        let removed = HookInstaller.uninstall(from: [:])
        XCTAssertNil(removed["hooks"])
    }

    func testDiskRoundTrip() throws {
        let path = NSTemporaryDirectory() + "settings-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try HookInstaller.installToDisk(command: cmd, path: path)
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path))
        try HookInstaller.uninstallFromDisk(path: path)
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path))
    }

    // MARK: - Unreadable settings must never be rewritten

    private func tempFile(_ contents: String) throws -> String {
        let path = NSTemporaryDirectory() + "settings-\(UUID().uuidString).json"
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    func testInstallRefusesToRewriteUnparseableSettings() throws {
        let path = try tempFile("{ not json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertThrowsError(try HookInstaller.installToDisk(command: cmd, path: path)) {
            XCTAssertEqual($0 as? HookInstallerError, .unreadableSettings(path: path))
        }
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "{ not json", "file untouched")
    }

    func testUninstallRefusesToRewriteUnparseableSettings() throws {
        let path = try tempFile("{ not json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertThrowsError(try HookInstaller.uninstallFromDisk(path: path))
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "{ not json", "file untouched")
    }

    func testInstallRefusesNonObjectRoot() throws {
        let path = try tempFile("[1, 2, 3]")
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertThrowsError(try HookInstaller.installToDisk(command: cmd, path: path))
    }

    func testEmptyFileIsTreatedAsEmptySettings() throws {
        let path = try tempFile("")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try HookInstaller.installToDisk(command: cmd, path: path)
        XCTAssertTrue(HookInstaller.isInstalledOnDisk(path: path))
    }

    func testIsInstalledOnDiskIsFalseForUnreadableSettings() throws {
        let path = try tempFile("{ not json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertFalse(HookInstaller.isInstalledOnDisk(path: path))
    }
}
