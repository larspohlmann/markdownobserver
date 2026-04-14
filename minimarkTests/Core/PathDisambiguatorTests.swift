import Foundation
import Testing
@testable import minimark

@Suite
struct PathDisambiguatorTests {

    // MARK: - disambiguatedDisplayNames

    @Test func returnsFolderNamesForDistinctDirectories() {
        let paths = ["/Users/me/project/src", "/Users/me/project/tests"]
        let names = PathDisambiguator.disambiguatedDisplayNames(for: paths)

        #expect(names["/Users/me/project/src"] == "src")
        #expect(names["/Users/me/project/tests"] == "tests")
    }

    @Test func addsParentWhenFolderNamesCollide() {
        let paths = [
            "/Users/me/project/a/docs",
            "/Users/me/project/b/docs"
        ]
        let names = PathDisambiguator.disambiguatedDisplayNames(for: paths)

        #expect(names["/Users/me/project/a/docs"] == "a/docs")
        #expect(names["/Users/me/project/b/docs"] == "b/docs")
    }

    @Test func handlesSinglePath() {
        let paths = ["/Users/me/project/src"]
        let names = PathDisambiguator.disambiguatedDisplayNames(for: paths)

        #expect(names["/Users/me/project/src"] == "src")
    }

    @Test func handlesEmptyPathForUntitled() {
        let paths = ["", "/Users/me/project/src"]
        let names = PathDisambiguator.disambiguatedDisplayNames(for: paths)

        #expect(names[""] == "Untitled")
        #expect(names["/Users/me/project/src"] == "src")
    }

    @Test func handlesEmptyArray() {
        let names = PathDisambiguator.disambiguatedDisplayNames(for: [])
        #expect(names.isEmpty)
    }

    @Test func addsMultipleParentsForDeeperCollisions() {
        let paths = [
            "/Users/me/a/shared/docs",
            "/Users/me/b/shared/docs"
        ]
        let names = PathDisambiguator.disambiguatedDisplayNames(for: paths)

        #expect(names["/Users/me/a/shared/docs"] == "a/shared/docs")
        #expect(names["/Users/me/b/shared/docs"] == "b/shared/docs")
    }

    @Test func leavesNonCollidingPathsShort() {
        let paths = [
            "/Users/me/a/docs",
            "/Users/me/b/docs",
            "/Users/me/src"
        ]
        let names = PathDisambiguator.disambiguatedDisplayNames(for: paths)

        #expect(names["/Users/me/a/docs"] == "a/docs")
        #expect(names["/Users/me/b/docs"] == "b/docs")
        #expect(names["/Users/me/src"] == "src")
    }

    // MARK: - uniqueParentSuffix

    @Test func returnsNilWhenPathHasNoParent() {
        let result = PathDisambiguator.uniqueParentSuffix(for: "/file.md", among: ["/file.md", "/other.md"])
        #expect(result == nil)
    }

    @Test func returnsShortestUniqueSuffix() {
        let paths = [
            "/Users/me/project/a/readme.md",
            "/Users/me/project/b/readme.md"
        ]
        let result = PathDisambiguator.uniqueParentSuffix(
            for: "/Users/me/project/a/readme.md",
            among: paths
        )
        #expect(result == "a")
    }

    @Test func addsDeeperSuffixWhenNeeded() {
        let paths = [
            "/Users/me/x/shared/readme.md",
            "/Users/me/y/shared/readme.md"
        ]
        let result = PathDisambiguator.uniqueParentSuffix(
            for: "/Users/me/x/shared/readme.md",
            among: paths
        )
        #expect(result == "x/shared")
    }

    @Test func returnsNilForSingleSibling() {
        let result = PathDisambiguator.uniqueParentSuffix(
            for: "/Users/me/docs/readme.md",
            among: ["/Users/me/docs/readme.md"]
        )
        #expect(result == "docs")
    }

    // MARK: - parentComponents

    @Test func parentComponentsExtractsDirectoryParts() {
        let components = PathDisambiguator.parentComponents(for: "/Users/me/project/readme.md")
        #expect(components == ["Users", "me", "project"])
    }

    @Test func parentComponentsReturnsEmptyForRootFile() {
        let components = PathDisambiguator.parentComponents(for: "/readme.md")
        #expect(components.isEmpty)
    }
}
