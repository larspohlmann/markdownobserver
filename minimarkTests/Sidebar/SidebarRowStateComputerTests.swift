import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct SidebarRowStateComputerTests {
    @MainActor
    private func makeSettingsStore() -> ReaderSettingsStore {
        ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "row-state-tests.\(UUID().uuidString)"
        )
    }

    @MainActor
    private func makeDocument(
        id: UUID = UUID(),
        settingsStore: ReaderSettingsStore
    ) -> ReaderSidebarDocumentController.Document {
        let store = ReaderStore(
            rendering: ReaderRenderingDependencies(
                renderer: TestMarkdownRenderer(), differ: TestChangedRegionDiffer()
            ),
            file: ReaderFileDependencies(
                watcher: TestFileWatcher(), io: ReaderDocumentIOService(), actions: TestReaderFileActions()
            ),
            folderWatch: ReaderFolderWatchDependencies(
                autoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
                settler: ReaderAutoOpenSettler(settlingInterval: 1.0),
                systemNotifier: TestReaderSystemNotifier()
            ),
            settingsStore: settingsStore,
            securityScopeResolver: SecurityScopeResolver(
                securityScope: TestSecurityScopeAccess(),
                settingsStore: settingsStore,
                requestWatchedFolderReauthorization: { _ in nil }
            )
        )
        return ReaderSidebarDocumentController.Document(
            id: id, readerStore: store, normalizedFileURL: nil
        )
    }

    // MARK: - Derive row state

    @Test @MainActor func derivesRowStateFromDocument() {
        let settings = makeSettingsStore()
        let doc = makeDocument(settingsStore: settings)
        let computer = SidebarRowStateComputer()

        let state = computer.deriveRowState(from: doc)

        #expect(state.id == doc.id)
        #expect(state.indicatorState == .none)
        #expect(state.indicatorPulseToken == 0)
        #expect(state.isFileMissing == false)
    }

    @Test @MainActor func derivesUntitledWhenDisplayNameEmpty() {
        let settings = makeSettingsStore()
        let doc = makeDocument(settingsStore: settings)
        let computer = SidebarRowStateComputer()

        let state = computer.deriveRowState(from: doc)

        #expect(state.title == "Untitled")
    }

    // MARK: - Rebuild all

    @Test @MainActor func rebuildAllPopulatesRowStates() {
        let settings = makeSettingsStore()
        let docA = makeDocument(settingsStore: settings)
        let docB = makeDocument(settingsStore: settings)
        let computer = SidebarRowStateComputer()

        computer.rebuildAllRowStates(from: [docA, docB])

        #expect(computer.rowStates.count == 2)
        #expect(computer.rowStates[docA.id] != nil)
        #expect(computer.rowStates[docB.id] != nil)
    }

    @Test @MainActor func rebuildAllIncrementsTokenOnIndicatorTransition() throws {
        let settings = makeSettingsStore()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("row-state-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let fileURL = tmpDir.appendingPathComponent("test.md")
        try "# Test".write(to: fileURL, atomically: true, encoding: .utf8)

        let doc = makeDocument(settingsStore: settings)
        doc.readerStore.openFile(at: fileURL, origin: .manual)
        let computer = SidebarRowStateComputer()

        // First rebuild — no previous state, so no pulse
        computer.rebuildAllRowStates(from: [doc])
        #expect(computer.rowStates[doc.id]?.indicatorPulseToken == 0)

        // Simulate external change -> indicator becomes active
        doc.readerStore.externalChange.noteObservedExternalChange()

        // Second rebuild — indicator transitioned to active, pulse increments
        computer.rebuildAllRowStates(from: [doc])
        #expect(computer.rowStates[doc.id]?.indicatorPulseToken == 1)
        #expect(computer.rowStates[doc.id]?.indicatorState == .externalChange)
    }

    @Test @MainActor func rebuildAllRemovesRowStateForRemovedDocument() {
        let settings = makeSettingsStore()
        let docA = makeDocument(settingsStore: settings)
        let docB = makeDocument(settingsStore: settings)
        let computer = SidebarRowStateComputer()

        computer.rebuildAllRowStates(from: [docA, docB])
        #expect(computer.rowStates.count == 2)

        // Remove docB
        computer.rebuildAllRowStates(from: [docA])

        #expect(computer.rowStates.count == 1)
        #expect(computer.rowStates[docB.id] == nil)

        // Re-add docB — pulse token should start fresh at 0
        computer.rebuildAllRowStates(from: [docA, docB])
        #expect(computer.rowStates[docB.id]?.indicatorPulseToken == 0)
    }

    @Test @MainActor func rebuildAllSkipsCallbackWhenUnchanged() {
        let settings = makeSettingsStore()
        let doc = makeDocument(settingsStore: settings)
        let computer = SidebarRowStateComputer()
        computer.rebuildAllRowStates(from: [doc])

        var callbackCount = 0
        computer.onRowStatesChanged = { _ in callbackCount += 1 }

        // Rebuild with same state — should not fire
        computer.rebuildAllRowStates(from: [doc])

        #expect(callbackCount == 0)
    }

    @Test @MainActor func rebuildAllFiresBothCallbacksWhenChanged() {
        let settings = makeSettingsStore()
        let doc = makeDocument(settingsStore: settings)
        let computer = SidebarRowStateComputer()

        var receivedStates: [UUID: SidebarRowState]?
        var dockTileCallbackFired = false
        computer.onRowStatesChanged = { states in receivedStates = states }
        computer.onDockTileRowStatesChanged = { _ in dockTileCallbackFired = true }

        computer.rebuildAllRowStates(from: [doc])

        #expect(receivedStates != nil)
        #expect(receivedStates?.count == 1)
        #expect(dockTileCallbackFired)
    }

    // MARK: - Update single row

    @Test @MainActor func updateRowStateIgnoresUnknownDocumentID() {
        let computer = SidebarRowStateComputer()

        // Should not crash or change state
        computer.updateRowStateIfNeeded(for: UUID(), in: [])
        #expect(computer.rowStates.isEmpty)
    }

    @Test @MainActor func updateRowStateFiresCallbackOnChange() throws {
        let settings = makeSettingsStore()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("row-state-update-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let fileURL = tmpDir.appendingPathComponent("test.md")
        try "# Test".write(to: fileURL, atomically: true, encoding: .utf8)

        let doc = makeDocument(settingsStore: settings)
        doc.readerStore.openFile(at: fileURL, origin: .manual)
        let computer = SidebarRowStateComputer()
        computer.rebuildAllRowStates(from: [doc])

        var callbackFired = false
        var dockTileCallbackFired = false
        computer.onRowStatesChanged = { _ in callbackFired = true }
        computer.onDockTileRowStatesChanged = { _ in dockTileCallbackFired = true }

        doc.readerStore.externalChange.noteObservedExternalChange()
        computer.updateRowStateIfNeeded(for: doc.id, in: [doc])

        #expect(callbackFired)
        #expect(dockTileCallbackFired)
        #expect(computer.rowStates[doc.id]?.indicatorState == .externalChange)
    }
}
