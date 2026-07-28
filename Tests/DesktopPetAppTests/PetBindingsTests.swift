import XCTest
@testable import desktoppet
@testable import DesktopPetCore

final class PetBindingsTests: XCTestCase {
    func testDefaultsIncludeNewMoods() {
        let b = PetBindings.defaults(clipCount: 9)
        XCTAssertNotNil(b.byMood[PetMood.sleepy.rawValue], "sleepy must get a default clip")
        XCTAssertNotNil(b.byMood[PetMood.levelup.rawValue], "levelup must get a default clip")
    }

    func testDefaultsClampWithinClipBounds() {
        let count = 3
        let b = PetBindings.defaults(clipCount: count)
        for mood in PetMood.allCases {
            let idx = b.clipIndex(for: mood)
            XCTAssertGreaterThanOrEqual(idx, 0)
            XCTAssertLessThanOrEqual(idx, count - 1, "\(mood) clip index must stay within clip bounds")
        }
    }

    func testZeroClipsYieldsZeroIndex() {
        let b = PetBindings.defaults(clipCount: 0)
        for mood in PetMood.allCases {
            XCTAssertEqual(b.clipIndex(for: mood), 0, "\(mood) must fall back to clip 0 with no clips")
        }
    }
}
