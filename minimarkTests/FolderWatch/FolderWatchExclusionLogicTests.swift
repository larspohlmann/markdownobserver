import Testing
@testable import minimark

@Suite("FolderWatchExclusionLogic")
struct FolderWatchExclusionLogicTests {

    // MARK: - toggleExclusion

    @Test func toggleExcludesPath() {
        let result = FolderWatchExclusionLogic.toggleExclusion(
            for: "/root/sub1",
            in: []
        )

        #expect(result == ["/root/sub1"])
    }

    @Test func toggleUnexcludesPath() {
        let result = FolderWatchExclusionLogic.toggleExclusion(
            for: "/root/sub1",
            in: ["/root/sub1"]
        )

        #expect(result == [])
    }

    @Test func toggleExcludeRemovesDescendantExclusions() {
        let result = FolderWatchExclusionLogic.toggleExclusion(
            for: "/root/sub1",
            in: ["/root/sub1/child1", "/root/sub1/child2"]
        )

        #expect(result == ["/root/sub1"])
    }

    @Test func toggleUnexcludeRemovesDescendantExclusions() {
        let result = FolderWatchExclusionLogic.toggleExclusion(
            for: "/root/sub1",
            in: ["/root/sub1", "/root/sub1/child1"]
        )

        #expect(result == [])
    }

    @Test func toggleDoesNotAffectSiblings() {
        let result = FolderWatchExclusionLogic.toggleExclusion(
            for: "/root/sub1",
            in: ["/root/sub2"]
        )

        #expect(result == ["/root/sub1", "/root/sub2"])
    }

    @Test func toggleResultIsSorted() {
        let result = FolderWatchExclusionLogic.toggleExclusion(
            for: "/root/alpha",
            in: ["/root/charlie", "/root/bravo"]
        )

        #expect(result == ["/root/alpha", "/root/bravo", "/root/charlie"])
    }

    @Test func consecutiveTogglesReturnToOriginalState() {
        let original = ["/root/sub2"]
        let after = FolderWatchExclusionLogic.toggleExclusion(for: "/root/sub1", in: original)
        let restored = FolderWatchExclusionLogic.toggleExclusion(for: "/root/sub1", in: after)

        #expect(restored == original)
    }

    // MARK: - exclusionState

    @Test func exclusionStateNoneWhenNoExclusions() {
        let state = FolderWatchExclusionLogic.exclusionState(
            for: "/root/sub1",
            excludedPaths: []
        )

        #expect(state.isExplicit == false)
        #expect(state.isByAncestor == false)
        #expect(state.isActive == true)
        #expect(state.canToggle == true)
    }

    @Test func exclusionStateExplicit() {
        let state = FolderWatchExclusionLogic.exclusionState(
            for: "/root/sub1",
            excludedPaths: ["/root/sub1"]
        )

        #expect(state.isExplicit == true)
        #expect(state.isByAncestor == false)
        #expect(state.isActive == false)
        #expect(state.canToggle == true)
    }

    @Test func exclusionStateByAncestor() {
        let state = FolderWatchExclusionLogic.exclusionState(
            for: "/root/sub1/child",
            excludedPaths: ["/root/sub1"]
        )

        #expect(state.isExplicit == false)
        #expect(state.isByAncestor == true)
        #expect(state.isActive == false)
        #expect(state.canToggle == false)
    }

    // MARK: - isExcludedByAncestor

    @Test func notExcludedByAncestorWhenSetEmpty() {
        let result = FolderWatchExclusionLogic.isExcludedByAncestor(
            nodePath: "/root/sub1",
            excludedSet: []
        )

        #expect(result == false)
    }

    @Test func excludedByDirectParent() {
        let result = FolderWatchExclusionLogic.isExcludedByAncestor(
            nodePath: "/root/sub1/child1",
            excludedSet: ["/root/sub1"]
        )

        #expect(result == true)
    }

    @Test func excludedByGrandparent() {
        let result = FolderWatchExclusionLogic.isExcludedByAncestor(
            nodePath: "/root/sub1/child1/deep",
            excludedSet: ["/root/sub1"]
        )

        #expect(result == true)
    }

    @Test func notExcludedByAncestorWhenSelfIsExcluded() {
        let result = FolderWatchExclusionLogic.isExcludedByAncestor(
            nodePath: "/root/sub1",
            excludedSet: ["/root/sub1"]
        )

        #expect(result == false)
    }

    @Test func notExcludedByAncestorWhenOnlySiblingExcluded() {
        let result = FolderWatchExclusionLogic.isExcludedByAncestor(
            nodePath: "/root/sub1",
            excludedSet: ["/root/sub2"]
        )

        #expect(result == false)
    }
}
