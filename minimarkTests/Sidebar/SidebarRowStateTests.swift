import Foundation
import Testing
@testable import minimark

@Suite
struct SidebarRowStateTests {
    @Test func storesProvidedValues() {
        let state = SidebarRowState(
            id: UUID(),
            title: "README.md",
            lastModified: Date(timeIntervalSince1970: 1000),
            sortDate: Date(timeIntervalSince1970: 1000),
            isFileMissing: false,
            indicatorState: .none
        )

        #expect(state.title == "README.md")
        #expect(state.lastModified == Date(timeIntervalSince1970: 1000))
        #expect(state.sortDate == Date(timeIntervalSince1970: 1000))
        #expect(state.isFileMissing == false)
        #expect(state.indicatorState == .none)
    }

    @Test func equatableSkipsIdenticalState() {
        let id = UUID()
        let date = Date()
        let a = SidebarRowState(id: id, title: "A.md", lastModified: date, sortDate: date, isFileMissing: false, indicatorState: .none)
        let b = SidebarRowState(id: id, title: "A.md", lastModified: date, sortDate: date, isFileMissing: false, indicatorState: .none)
        #expect(a == b)
    }

    @Test func equatableDetectsChangedTitle() {
        let id = UUID()
        let a = SidebarRowState(id: id, title: "A.md", lastModified: nil, sortDate: nil, isFileMissing: false, indicatorState: .none)
        let b = SidebarRowState(id: id, title: "B.md", lastModified: nil, sortDate: nil, isFileMissing: false, indicatorState: .none)
        #expect(a != b)
    }

    @Test func equatableDetectsChangedIndicator() {
        let id = UUID()
        let a = SidebarRowState(id: id, title: "A.md", lastModified: nil, sortDate: nil, isFileMissing: false, indicatorState: .none)
        let b = SidebarRowState(id: id, title: "A.md", lastModified: nil, sortDate: nil, isFileMissing: false, indicatorState: .externalChange)
        #expect(a != b)
    }
}

@Suite(.serialized)
struct SidebarRowStateDerivationTests {
    @Test @MainActor func controllerDerivesSidebarRowStateFromDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let docID = harness.controller.documents[0].id
        let state = try #require(harness.controller.rowStates[docID])
        #expect(state.isFileMissing == false)
        #expect(state.indicatorState == .none)
    }

    @Test @MainActor func controllerUpdatesRowStatesWhenDocumentsChange() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

        #expect(harness.controller.documents.count == 2)
        #expect(harness.controller.rowStates.count == 2)
    }

    @Test @MainActor func controllerUpdatesRowStateWhenStorePropertyChanges() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        // Open a real file so the store has meaningful state
        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual
        ))

        let docID = harness.controller.documents[0].id
        let store = harness.controller.documents[0].readerStore
        let initialState = harness.controller.rowStates[docID]

        // Simulate an external change notification on the store
        store.noteObservedExternalChange()

        // Allow the RunLoop.main receive to process the objectWillChange → updateRowStateIfNeeded
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let updatedState = harness.controller.rowStates[docID]
        #expect(updatedState?.indicatorState == .externalChange)
        #expect(initialState != updatedState)
    }
}
