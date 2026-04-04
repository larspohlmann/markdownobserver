import XCTest
@testable import minimark

final class FolderWatchExclusionCalculatorTests: XCTestCase {

    // MARK: - countEffectivelyExcludedPaths

    func testDirectExclusionCountsMatchingPaths() {
        let paths = [
            "/root/a",
            "/root/b",
            "/root/c"
        ]
        let excluded: Set<String> = ["/root/a", "/root/c"]

        let count = FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: paths,
            excludedPaths: excluded
        )

        XCTAssertEqual(count, 2)
    }

    func testAncestorExclusionCountsDescendants() {
        let paths = [
            "/root/parent",
            "/root/parent/child",
            "/root/parent/child/grandchild",
            "/root/other"
        ]
        let excluded: Set<String> = ["/root/parent"]

        let count = FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: paths,
            excludedPaths: excluded
        )

        // /root/parent itself + child + grandchild = 3
        XCTAssertEqual(count, 3)
    }

    func testAllPathsExcludedReturnsFullCount() {
        let paths = [
            "/root/a",
            "/root/b",
            "/root/c"
        ]
        let excluded: Set<String> = ["/root/a", "/root/b", "/root/c"]

        let count = FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: paths,
            excludedPaths: excluded
        )

        XCTAssertEqual(count, 3)
    }

    func testEmptyExclusionReturnsZero() {
        let paths = ["/root/a", "/root/b"]
        let excluded: Set<String> = []

        let count = FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: paths,
            excludedPaths: excluded
        )

        XCTAssertEqual(count, 0)
    }

    func testEmptyPathsReturnsZero() {
        let paths: [String] = []
        let excluded: Set<String> = ["/root/a"]

        let count = FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: paths,
            excludedPaths: excluded
        )

        XCTAssertEqual(count, 0)
    }

    func testTrailingSlashNormalizationInExclusionCounting() {
        let paths = [
            "/root/a",
            "/root/b/"
        ]
        let excluded: Set<String> = ["/root/a/", "/root/b"]

        let count = FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: paths,
            excludedPaths: excluded
        )

        XCTAssertEqual(count, 2, "Trailing slash differences should be normalized away")
    }

    // MARK: - isPathExcludedBySelfOrAncestor

    func testDirectMembershipReturnsTrueForExcluded() {
        let excluded: Set<String> = ["/root/target"]

        XCTAssertTrue(
            FolderWatchExclusionCalculator.isPathExcludedBySelfOrAncestor(
                "/root/target",
                excludedSet: excluded
            )
        )
    }

    func testAncestorMembershipReturnsTrueForDescendant() {
        let excluded: Set<String> = ["/root/parent"]

        XCTAssertTrue(
            FolderWatchExclusionCalculator.isPathExcludedBySelfOrAncestor(
                "/root/parent/child/grandchild",
                excludedSet: excluded
            )
        )
    }

    func testUnrelatedPathReturnsFalse() {
        let excluded: Set<String> = ["/root/other"]

        XCTAssertFalse(
            FolderWatchExclusionCalculator.isPathExcludedBySelfOrAncestor(
                "/root/target",
                excludedSet: excluded
            )
        )
    }

    func testEmptyExcludedSetReturnsFalse() {
        XCTAssertFalse(
            FolderWatchExclusionCalculator.isPathExcludedBySelfOrAncestor(
                "/root/target",
                excludedSet: []
            )
        )
    }

    // MARK: - normalizedDirectoryPath

    func testRemovesTrailingSlash() {
        XCTAssertEqual(
            FolderWatchExclusionCalculator.normalizedDirectoryPath("/root/folder/"),
            "/root/folder"
        )
    }

    func testRemovesMultipleTrailingSlashes() {
        XCTAssertEqual(
            FolderWatchExclusionCalculator.normalizedDirectoryPath("/root/folder///"),
            "/root/folder"
        )
    }

    func testPreservesRootSlash() {
        XCTAssertEqual(
            FolderWatchExclusionCalculator.normalizedDirectoryPath("/"),
            "/"
        )
    }

    func testNoTrailingSlashPassesThrough() {
        XCTAssertEqual(
            FolderWatchExclusionCalculator.normalizedDirectoryPath("/root/folder"),
            "/root/folder"
        )
    }

    func testSingleCharacterPathPassesThrough() {
        XCTAssertEqual(
            FolderWatchExclusionCalculator.normalizedDirectoryPath("a"),
            "a"
        )
    }
}
