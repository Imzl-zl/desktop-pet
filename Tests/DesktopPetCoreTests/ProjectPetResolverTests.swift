import XCTest
@testable import DesktopPetCore

final class ProjectPetResolverTests: XCTestCase {
    private let cat = ProjectPetMapping(projectPath: "/work/foo", petID: "cat")
    private let dog = ProjectPetMapping(projectPath: "/work/foo/api", petID: "dog")

    func testExactMatch() {
        XCTAssertEqual(ProjectPetResolver.mapping(forProject: "/work/foo", mappings: [cat])?.petID, "cat")
    }
    func testSubfolderMatches() {
        XCTAssertEqual(ProjectPetResolver.mapping(forProject: "/work/foo/src", mappings: [cat])?.petID, "cat")
    }
    func testLongestMatchWins() {
        XCTAssertEqual(ProjectPetResolver.mapping(forProject: "/work/foo/api/v1", mappings: [cat, dog])?.petID, "dog")
    }
    func testDirectoryBoundaryNotPrefixString() {
        // "/work/foobar" must NOT match "/work/foo"
        XCTAssertNil(ProjectPetResolver.mapping(forProject: "/work/foobar", mappings: [cat]))
    }
    func testTrailingSlashNormalized() {
        XCTAssertEqual(ProjectPetResolver.mapping(forProject: "/work/foo/", mappings: [cat])?.petID, "cat")
        let catSlash = ProjectPetMapping(projectPath: "/work/foo/", petID: "cat")
        XCTAssertEqual(ProjectPetResolver.mapping(forProject: "/work/foo", mappings: [catSlash])?.petID, "cat")
    }
    func testNilOrEmptyCwdReturnsNil() {
        XCTAssertNil(ProjectPetResolver.mapping(forProject: nil, mappings: [cat]))
        XCTAssertNil(ProjectPetResolver.mapping(forProject: "", mappings: [cat]))
    }
    func testNoMatchReturnsNil() {
        XCTAssertNil(ProjectPetResolver.mapping(forProject: "/other", mappings: [cat]))
    }
}
