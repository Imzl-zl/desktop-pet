import XCTest
@testable import DesktopPetCore

final class AgentCatalogTests: XCTestCase {
    func testHookAgentsSupported() {
        let byKind = Dictionary(uniqueKeysWithValues: AgentCatalog.all.map { ($0.kind, $0) })
        XCTAssertEqual(byKind[.claude]?.isSupported, true)
        XCTAssertEqual(byKind[.codex]?.isSupported, true)
        XCTAssertEqual(byKind[.gemini]?.isSupported, true)
    }
}
