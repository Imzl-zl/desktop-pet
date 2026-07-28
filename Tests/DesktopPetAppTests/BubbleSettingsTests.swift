import XCTest
@testable import desktoppet

@MainActor
final class BubbleSettingsTests: XCTestCase {
    private let multiAgentBubbleKey = "desktoppet.bubble.multiAgentBubbleEnabled"
    private let sessionGroupingKey = "desktoppet.bubble.sessionGrouping"
    private let collapseDuplicatesKey = "desktoppet.bubble.collapseDuplicates"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: multiAgentBubbleKey)
        UserDefaults.standard.removeObject(forKey: sessionGroupingKey)
        UserDefaults.standard.removeObject(forKey: collapseDuplicatesKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: multiAgentBubbleKey)
        UserDefaults.standard.removeObject(forKey: sessionGroupingKey)
        UserDefaults.standard.removeObject(forKey: collapseDuplicatesKey)
        super.tearDown()
    }

    func testMultiAgentBubbleDefaultsOn() {
        let settings = BubbleSettings()

        XCTAssertTrue(settings.multiAgentBubbleEnabled)
    }

    func testMultiAgentBubblePersists() {
        let settings = BubbleSettings()

        settings.multiAgentBubbleEnabled = true

        XCTAssertTrue(BubbleSettings().multiAgentBubbleEnabled)
    }

    func testSessionGroupingDefaultsToByKind() {
        XCTAssertEqual(BubbleSettings().sessionGrouping, .byKind)
    }

    func testSessionGroupingPersists() {
        let settings = BubbleSettings()
        settings.sessionGrouping = .allSessions
        XCTAssertEqual(BubbleSettings().sessionGrouping, .allSessions)
    }

    func testSessionGroupingMigratesFromLegacyCollapseOff() {
        UserDefaults.standard.set(false, forKey: collapseDuplicatesKey)
        XCTAssertEqual(BubbleSettings().sessionGrouping, .allSessions)
    }

    func testModelTokenExistsAndHasMetadata() {
        XCTAssertTrue(BubbleToken.allCases.contains(.model))
        XCTAssertEqual(BubbleToken.model.shortName, "Model")
        XCTAssertEqual(BubbleToken.model.chipSymbol, "cpu")
    }

    func testModelTokenVisibilityInPresets() {
        func isVisible(_ layout: BubbleLayout) -> Bool? {
            layout.tokens.first { $0.token == .model }?.isVisible
        }
        XCTAssertEqual(isVisible(.original), false)
        XCTAssertEqual(isVisible(.standard), false)
        XCTAssertEqual(isVisible(.detailed), true)
    }
}
