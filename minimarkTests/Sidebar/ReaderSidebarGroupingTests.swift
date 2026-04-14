import Foundation
import Testing
@testable import minimark

@Suite
struct ReaderSidebarGroupingTests {

    // MARK: - Grouping Logic

    @Test @MainActor func singleDirectoryReturnsFlat() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["docs"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        let grouping = ReaderSidebarGrouping.group(harness.documents)

        guard case .flat(let documents) = grouping else {
            Issue.record("Expected flat grouping for single directory")
            return
        }
        #expect(documents.count == 2)
    }

    @Test @MainActor func multipleDirectoriesReturnsGrouped() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        let grouping = ReaderSidebarGrouping.group(harness.documents)

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result for multiple directories")
            return
        }
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.documents.count == 2 })
    }

    @Test @MainActor func groupsSortByNewestModificationDate() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["older", "newer"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        // Set modification dates: "newer" group has a more recent date
        let olderDoc = harness.documentsInSubdirectory("older").first!
        let newerDoc = harness.documentsInSubdirectory("newer").first!
        olderDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
        newerDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 2000))

        let grouping = ReaderSidebarGrouping.group(harness.documents)

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.count == 2)
        #expect(groups[0].displayName == "newer")
        #expect(groups[1].displayName == "older")
    }

    @Test @MainActor func groupsSortByNameAscendingWhenConfigured() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["zeta", "alpha"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let grouping = ReaderSidebarGrouping.group(
            harness.documents,
            sortMode: .nameAscending
        )

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.map(\.displayName) == ["alpha", "zeta"])
    }

    @Test @MainActor func groupsSortByOpenOrderUsesFirstEncounteredDirectory() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let betaDoc = try #require(harness.documentsInSubdirectory("beta").first)
        let alphaDoc = try #require(harness.documentsInSubdirectory("alpha").first)
        let reorderedDocuments = [betaDoc, alphaDoc]

        let grouping = ReaderSidebarGrouping.group(
            reorderedDocuments,
            sortMode: .openOrder
        )

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.map(\.displayName) == ["beta", "alpha"])
    }

    @Test @MainActor func groupsSortByOpenOrderCanUseIndependentDirectoryOrderSource() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let alphaDoc = try #require(harness.documentsInSubdirectory("alpha").first)
        let betaDoc = try #require(harness.documentsInSubdirectory("beta").first)

        // Simulate file sort order (documents array) differing from group open-order source.
        let fileSortedDocuments = [alphaDoc, betaDoc]
        let openOrderSourceDocuments = [betaDoc, alphaDoc]

        let grouping = ReaderSidebarGrouping.group(
            fileSortedDocuments,
            sortMode: .openOrder,
            directoryOrderSourceDocuments: openOrderSourceDocuments
        )

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.map(\.displayName) == ["beta", "alpha"])
    }

    @Test @MainActor func groupsSortByNewestFirstUsesDisplayNameAsTieBreaker() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["zeta", "alpha"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let sharedDate = Date(timeIntervalSince1970: 1000)
        for document in harness.documents {
            document.readerStore.testSetFileLastModifiedAt(sharedDate)
        }

        let zetaDoc = try #require(harness.documentsInSubdirectory("zeta").first)
        let alphaDoc = try #require(harness.documentsInSubdirectory("alpha").first)

        // Intentionally reverse incoming order to ensure tie-break is deterministic by display name.
        let grouping = ReaderSidebarGrouping.group(
            [zetaDoc, alphaDoc],
            sortMode: .lastChangedNewestFirst
        )

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.map(\.displayName) == ["alpha", "zeta"])
    }

    @Test @MainActor func groupSortUpdatesWhenModificationDateChanges() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let alphaDoc = harness.documentsInSubdirectory("alpha").first!
        let betaDoc = harness.documentsInSubdirectory("beta").first!

        // Initially beta is newer
        alphaDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
        betaDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 2000))

        let grouping1 = ReaderSidebarGrouping.group(harness.documents)
        guard case .grouped(let groups1) = grouping1 else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups1[0].displayName == "beta")

        // Now alpha gets modified more recently
        alphaDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 3000))

        let grouping2 = ReaderSidebarGrouping.group(harness.documents)
        guard case .grouped(let groups2) = grouping2 else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups2[0].displayName == "alpha")
    }

    // MARK: - Indicator Aggregation

    @Test @MainActor func indicatorsReturnEmptyWhenNoChanges() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["docs"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        let states = ReaderSidebarGrouping.indicators(for: harness.documents)
        #expect(states.isEmpty)
    }

    @Test @MainActor func indicatorsReturnExternalChangeWhenAnyDocumentHasChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["docs"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        harness.documents[0].readerStore.testSetHasUnacknowledgedExternalChange(true)
        harness.documents[0].readerStore.content.unacknowledgedExternalChangeKind = .modified

        let states = ReaderSidebarGrouping.indicators(for: harness.documents)
        #expect(states == [.externalChange])
    }

    @Test @MainActor func indicatorsReturnDeletedWhenAnyDocumentIsMissing() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["docs"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        harness.documents[0].readerStore.testSetHasUnacknowledgedExternalChange(true)
        harness.documents[0].readerStore.content.unacknowledgedExternalChangeKind = .modified
        harness.documents[0].readerStore.testSetIsCurrentFileMissing(true)

        let states = ReaderSidebarGrouping.indicators(for: harness.documents)
        #expect(states == [.deletedExternalChange])
    }

    // MARK: - Group Pinning

    @Test @MainActor func pinnedGroupsSortBeforeUnpinnedGroups() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        // Give all groups the same mod date so only pinning affects order
        for doc in harness.documents {
            doc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
        }

        let gammaPath = harness.directoryPath(for: "gamma")
        let grouping = ReaderSidebarGrouping.group(harness.documents, pinnedGroupIDs: [gammaPath])

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups[0].displayName == "gamma")
        #expect(groups[0].isPinned == true)
        #expect(groups[1].isPinned == false)
        #expect(groups[2].isPinned == false)
    }

    @Test @MainActor func pinnedGroupsSortByModificationDateAmongThemselves() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let alphaDoc = harness.documentsInSubdirectory("alpha").first!
        let gammaDoc = harness.documentsInSubdirectory("gamma").first!
        let betaDoc = harness.documentsInSubdirectory("beta").first!

        alphaDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 3000))
        gammaDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
        betaDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 2000))

        let alphaPath = harness.directoryPath(for: "alpha")
        let gammaPath = harness.directoryPath(for: "gamma")

        let grouping = ReaderSidebarGrouping.group(
            harness.documents,
            pinnedGroupIDs: [alphaPath, gammaPath]
        )

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }
        // Pinned first (alpha newer than gamma), then unpinned
        #expect(groups[0].displayName == "alpha")
        #expect(groups[0].isPinned == true)
        #expect(groups[1].displayName == "gamma")
        #expect(groups[1].isPinned == true)
        #expect(groups[2].displayName == "beta")
        #expect(groups[2].isPinned == false)
    }

    @Test @MainActor func unpinnedGroupsStillSortByModificationDate() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let alphaDoc = harness.documentsInSubdirectory("alpha").first!
        let betaDoc = harness.documentsInSubdirectory("beta").first!

        alphaDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
        betaDoc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 2000))

        let grouping = ReaderSidebarGrouping.group(harness.documents, pinnedGroupIDs: [])

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups[0].displayName == "beta")
        #expect(groups[1].displayName == "alpha")
    }

    @Test @MainActor func indicatorsIncludeAllKindsWhenPresent() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["docs"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        // One doc has modified change, another has deleted-added change.
        harness.documents[0].readerStore.testSetHasUnacknowledgedExternalChange(true)
        harness.documents[0].readerStore.content.unacknowledgedExternalChangeKind = .modified
        harness.documents[1].readerStore.testSetHasUnacknowledgedExternalChange(true)
        harness.documents[1].readerStore.content.unacknowledgedExternalChangeKind = .added
        harness.documents[1].readerStore.testSetIsCurrentFileMissing(true)

        let documentStates = harness.documents.map { document in
            ReaderDocumentIndicatorState(
                hasUnacknowledgedExternalChange: document.readerStore.hasUnacknowledgedExternalChange,
                isCurrentFileMissing: document.readerStore.isCurrentFileMissing,
                unacknowledgedExternalChangeKind: document.readerStore.content.unacknowledgedExternalChangeKind
            )
        }
        #expect(documentStates.contains(.externalChange))
        #expect(documentStates.contains(.deletedExternalChange))

        let states = ReaderSidebarGrouping.indicators(for: harness.documents)
        #expect(states == [.externalChange, .deletedExternalChange])
    }

    // MARK: - Indicator Aggregation from Pre-Computed States

    @Test @MainActor func indicatorsFromStatesReturnsEmptyWhenAllNone() {
        let result = ReaderSidebarGrouping.indicators(
            from: [.none, .none, .none]
        )
        #expect(result.isEmpty)
    }

    @Test @MainActor func indicatorsFromStatesReturnsExternalChangeWhenPresent() {
        let result = ReaderSidebarGrouping.indicators(
            from: [.none, .externalChange, .none]
        )
        #expect(result == [.externalChange])
    }

    @Test @MainActor func indicatorsFromStatesKeepsAddedAndModifiedDistinct() {
        let result = ReaderSidebarGrouping.indicators(
            from: [.none, .addedExternalChange, .none]
        )
        #expect(result == [.addedExternalChange])
    }

    @Test @MainActor func indicatorsFromStatesReturnsDeletedWhenPresent() {
        let result = ReaderSidebarGrouping.indicators(
            from: [.none, .deletedExternalChange]
        )
        #expect(result == [.deletedExternalChange])
    }

    @Test @MainActor func indicatorsFromStatesReturnsAllKindsInStableOrder() {
        let result = ReaderSidebarGrouping.indicators(
            from: [.externalChange, .deletedExternalChange, .addedExternalChange, .none]
        )
        #expect(result == [.addedExternalChange, .externalChange, .deletedExternalChange])
    }

    @Test @MainActor func indicatorsFromStatesHandlesEmptyArray() {
        let result = ReaderSidebarGrouping.indicators(from: [])
        #expect(result.isEmpty)
    }

    @Test @MainActor func groupUsesPrecomputedIndicatorStatesWhenProvided() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let srcPath = harness.directoryPath(for: "src")
        let testsPath = harness.directoryPath(for: "tests")

        let precomputed: [String: [ReaderDocumentIndicatorState]] = [
            srcPath: [.addedExternalChange, .externalChange],
            testsPath: []
        ]
        let pulseTokens: [String: Int] = [
            srcPath: 2,
            testsPath: 0
        ]

        let grouping = ReaderSidebarGrouping.group(
            harness.documents,
            precomputedIndicatorStates: precomputed,
            precomputedIndicatorPulseTokens: pulseTokens
        )

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }

        let srcGroup = try #require(groups.first { $0.id == srcPath })
        let testsGroup = try #require(groups.first { $0.id == testsPath })
        #expect(srcGroup.indicatorStates == [.addedExternalChange, .externalChange])
        #expect(srcGroup.indicatorPulseToken == 2)
        #expect(testsGroup.indicatorStates.isEmpty)
        #expect(testsGroup.indicatorPulseToken == 0)
    }

    @Test @MainActor func groupFallsBackToLiveComputationWhenNoPrecomputedStates() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        harness.documentsInSubdirectory("src").first!.readerStore
            .testSetHasUnacknowledgedExternalChange(true)
        harness.documentsInSubdirectory("src").first!.readerStore.content.unacknowledgedExternalChangeKind = .modified

        let grouping = ReaderSidebarGrouping.group(harness.documents)

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }

        let srcPath = harness.directoryPath(for: "src")
        let srcGroup = try #require(groups.first { $0.id == srcPath })
        #expect(srcGroup.indicatorStates == [.externalChange])
        #expect(srcGroup.indicatorPulseToken == 0)
    }

    @Test @MainActor func groupFallsBackToAddedIndicatorWhenKindIsAdded() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        harness.documentsInSubdirectory("src").first!.readerStore
            .testSetHasUnacknowledgedExternalChange(true)
        harness.documentsInSubdirectory("src").first!.readerStore.content.unacknowledgedExternalChangeKind = .added

        let grouping = ReaderSidebarGrouping.group(harness.documents)

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }

        let srcPath = harness.directoryPath(for: "src")
        let srcGroup = try #require(groups.first { $0.id == srcPath })
        #expect(srcGroup.indicatorStates == [.addedExternalChange])
        #expect(srcGroup.indicatorPulseToken == 0)
    }
}
