import Foundation
import Testing
@testable import minimark

@Suite
struct ReaderSidebarGroupingTests {

    // MARK: - Display Name Disambiguation

    @Test @MainActor func disambiguatedDisplayNamesReturnsFolderNamesForDistinctDirectories() {
        let paths = ["/Users/me/project/src", "/Users/me/project/tests"]
        let names = ReaderSidebarGrouping.disambiguatedDisplayNames(for: paths)

        #expect(names["/Users/me/project/src"] == "src")
        #expect(names["/Users/me/project/tests"] == "tests")
    }

    @Test @MainActor func disambiguatedDisplayNamesAddsParentWhenFolderNamesCollide() {
        let paths = [
            "/Users/me/project/a/docs",
            "/Users/me/project/b/docs"
        ]
        let names = ReaderSidebarGrouping.disambiguatedDisplayNames(for: paths)

        #expect(names["/Users/me/project/a/docs"] == "a/docs")
        #expect(names["/Users/me/project/b/docs"] == "b/docs")
    }

    @Test @MainActor func disambiguatedDisplayNamesHandlesSinglePath() {
        let paths = ["/Users/me/project/src"]
        let names = ReaderSidebarGrouping.disambiguatedDisplayNames(for: paths)

        #expect(names["/Users/me/project/src"] == "src")
    }

    @Test @MainActor func disambiguatedDisplayNamesHandlesEmptyPathForUntitled() {
        let paths = ["", "/Users/me/project/src"]
        let names = ReaderSidebarGrouping.disambiguatedDisplayNames(for: paths)

        #expect(names[""] == "Untitled")
        #expect(names["/Users/me/project/src"] == "src")
    }

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

    @Test @MainActor func aggregatedIndicatorReturnsNoneWhenNoChanges() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["docs"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        let state = ReaderSidebarGrouping.aggregatedIndicatorState(for: harness.documents)
        #expect(state == .none)
    }

    @Test @MainActor func aggregatedIndicatorReturnsExternalChangeWhenAnyDocumentHasChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["docs"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        harness.documents[0].readerStore.testSetHasUnacknowledgedExternalChange(true)

        let state = ReaderSidebarGrouping.aggregatedIndicatorState(for: harness.documents)
        #expect(state == .externalChange)
    }

    @Test @MainActor func aggregatedIndicatorReturnsDeletedWhenAnyDocumentIsMissing() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["docs"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        harness.documents[0].readerStore.testSetHasUnacknowledgedExternalChange(true)
        harness.documents[0].readerStore.testSetIsCurrentFileMissing(true)

        let state = ReaderSidebarGrouping.aggregatedIndicatorState(for: harness.documents)
        #expect(state == .deletedExternalChange)
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

    @Test @MainActor func aggregatedIndicatorDeletedTakesPriorityOverExternalChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["docs"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        // One doc has external change, another has deleted change
        harness.documents[0].readerStore.testSetHasUnacknowledgedExternalChange(true)
        harness.documents[1].readerStore.testSetHasUnacknowledgedExternalChange(true)
        harness.documents[1].readerStore.testSetIsCurrentFileMissing(true)

        let state = ReaderSidebarGrouping.aggregatedIndicatorState(for: harness.documents)
        #expect(state == .deletedExternalChange)
    }

    // MARK: - Indicator Aggregation from Pre-Computed States

    @Test @MainActor func aggregatedIndicatorFromStatesReturnsNoneWhenAllNone() {
        let result = ReaderSidebarGrouping.aggregatedIndicatorState(
            from: [.none, .none, .none]
        )
        #expect(result == .none)
    }

    @Test @MainActor func aggregatedIndicatorFromStatesReturnsExternalChangeWhenPresent() {
        let result = ReaderSidebarGrouping.aggregatedIndicatorState(
            from: [.none, .externalChange, .none]
        )
        #expect(result == .externalChange)
    }

    @Test @MainActor func aggregatedIndicatorFromStatesReturnsDeletedWhenPresent() {
        let result = ReaderSidebarGrouping.aggregatedIndicatorState(
            from: [.none, .deletedExternalChange]
        )
        #expect(result == .deletedExternalChange)
    }

    @Test @MainActor func aggregatedIndicatorFromStatesDeletedTakesPriority() {
        let result = ReaderSidebarGrouping.aggregatedIndicatorState(
            from: [.externalChange, .deletedExternalChange, .none]
        )
        #expect(result == .deletedExternalChange)
    }

    @Test @MainActor func aggregatedIndicatorFromStatesHandlesEmptyArray() {
        let result = ReaderSidebarGrouping.aggregatedIndicatorState(from: [])
        #expect(result == .none)
    }

    @Test @MainActor func groupUsesPrecomputedIndicatorStatesWhenProvided() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let srcPath = harness.directoryPath(for: "src")
        let testsPath = harness.directoryPath(for: "tests")

        let precomputed: [String: ReaderDocumentIndicatorState] = [
            srcPath: .externalChange,
            testsPath: .none
        ]

        let grouping = ReaderSidebarGrouping.group(
            harness.documents,
            precomputedIndicatorStates: precomputed
        )

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }

        let srcGroup = try #require(groups.first { $0.id == srcPath })
        let testsGroup = try #require(groups.first { $0.id == testsPath })
        #expect(srcGroup.indicatorState == .externalChange)
        #expect(testsGroup.indicatorState == .none)
    }

    @Test @MainActor func groupFallsBackToLiveComputationWhenNoPrecomputedStates() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        harness.documentsInSubdirectory("src").first!.readerStore
            .testSetHasUnacknowledgedExternalChange(true)

        let grouping = ReaderSidebarGrouping.group(harness.documents)

        guard case .grouped(let groups) = grouping else {
            Issue.record("Expected grouped result")
            return
        }

        let srcPath = harness.directoryPath(for: "src")
        let srcGroup = try #require(groups.first { $0.id == srcPath })
        #expect(srcGroup.indicatorState == .externalChange)
    }
}

// MARK: - Test Harness

@MainActor
private struct ReaderSidebarGroupingTestHarness {
    let temporaryDirectoryURL: URL
    let documents: [ReaderSidebarDocumentController.Document]

    init(subdirectories: [String], filesPerSubdirectory: Int) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-grouping-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectoryURL = directory

        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.grouping.tests.\(UUID().uuidString)"
        )

        var allDocuments: [ReaderSidebarDocumentController.Document] = []

        for subdirectory in subdirectories {
            let subURL = directory.appendingPathComponent(subdirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: subURL, withIntermediateDirectories: true)

            for i in 0..<filesPerSubdirectory {
                let fileURL = subURL.appendingPathComponent("file\(i).md")
                try "# File \(i)".write(to: fileURL, atomically: true, encoding: .utf8)

                let store = ReaderStore(
                    renderer: TestMarkdownRenderer(),
                    differ: TestChangedRegionDiffer(),
                    fileWatcher: TestFileWatcher(),
                    folderWatcher: TestFolderWatcher(),
                    settingsStore: settingsStore,
                    securityScope: TestSecurityScopeAccess(),
                    fileActions: TestReaderFileActions(),
                    systemNotifier: TestReaderSystemNotifier(),
                    folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
                    settler: ReaderAutoOpenSettler(settlingInterval: 1.0),
                    requestWatchedFolderReauthorization: { _ in nil }
                )
                store.testSetFileURL(fileURL)
                store.testSetFileDisplayName(fileURL.lastPathComponent)

                allDocuments.append(
                    ReaderSidebarDocumentController.Document(id: UUID(), readerStore: store)
                )
            }
        }

        documents = allDocuments
    }

    func documentsInSubdirectory(_ name: String) -> [ReaderSidebarDocumentController.Document] {
        let subURL = temporaryDirectoryURL.appendingPathComponent(name, isDirectory: true)
        return documents.filter { doc in
            doc.readerStore.fileURL?.deletingLastPathComponent().path(percentEncoded: false) == subURL.path(percentEncoded: false)
        }
    }

    func directoryPath(for subdirectory: String) -> String {
        temporaryDirectoryURL.appendingPathComponent(subdirectory, isDirectory: true).path(percentEncoded: false)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}
