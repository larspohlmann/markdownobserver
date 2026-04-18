import Testing
import Foundation
@testable import minimark

@MainActor
struct SidebarSelectionActionsTests {
    @Test
    func openInDefaultApp_forwardsDocumentIDs() {
        var captured: Set<UUID> = []
        let idA = UUID()
        let idB = UUID()
        let actions = makeActions(openInDefaultApp: { captured = $0 })

        actions.openInDefaultApp([idA, idB])

        #expect(captured == [idA, idB])
    }

    @Test
    func openInApplication_forwardsApplicationAndIDs() {
        var capturedApp: ExternalApplication?
        var capturedIDs: Set<UUID> = []
        let app = ExternalApplication(
            id: "com.example.test",
            displayName: "Test Editor",
            bundleIdentifier: "com.example.test",
            bundleURL: URL(fileURLWithPath: "/Applications/TestEditor.app")
        )
        let id = UUID()
        let actions = makeActions(openInApplication: { application, ids in
            capturedApp = application
            capturedIDs = ids
        })

        actions.openInApplication(app, [id])

        #expect(capturedApp == app)
        #expect(capturedIDs == [id])
    }

    @Test
    func revealInFinder_forwardsDocumentIDs() {
        var captured: Set<UUID> = []
        let id = UUID()
        let actions = makeActions(revealInFinder: { captured = $0 })

        actions.revealInFinder([id])

        #expect(captured == [id])
    }

    @Test
    func stopWatchingFolders_forwardsDocumentIDs() {
        var captured: Set<UUID> = []
        let id = UUID()
        let actions = makeActions(stopWatchingFolders: { captured = $0 })

        actions.stopWatchingFolders([id])

        #expect(captured == [id])
    }

    @Test
    func closeDocuments_forwardsDocumentIDs() {
        var captured: Set<UUID> = []
        let id = UUID()
        let actions = makeActions(closeDocuments: { captured = $0 })

        actions.closeDocuments([id])

        #expect(captured == [id])
    }

    @Test
    func closeOtherDocuments_forwardsDocumentIDs() {
        var captured: Set<UUID> = []
        let id = UUID()
        let actions = makeActions(closeOtherDocuments: { captured = $0 })

        actions.closeOtherDocuments([id])

        #expect(captured == [id])
    }

    @Test
    func closeAll_invokesClosure() {
        var invoked = false
        let actions = makeActions(closeAll: { invoked = true })

        actions.closeAll()

        #expect(invoked)
    }

    // MARK: - Helpers

    private func makeActions(
        openInDefaultApp: @escaping (Set<UUID>) -> Void = { _ in },
        openInApplication: @escaping (ExternalApplication, Set<UUID>) -> Void = { _, _ in },
        revealInFinder: @escaping (Set<UUID>) -> Void = { _ in },
        stopWatchingFolders: @escaping (Set<UUID>) -> Void = { _ in },
        closeDocuments: @escaping (Set<UUID>) -> Void = { _ in },
        closeOtherDocuments: @escaping (Set<UUID>) -> Void = { _ in },
        closeAll: @escaping () -> Void = {}
    ) -> SidebarSelectionActions {
        SidebarSelectionActions(
            openInDefaultApp: openInDefaultApp,
            openInApplication: openInApplication,
            revealInFinder: revealInFinder,
            stopWatchingFolders: stopWatchingFolders,
            closeDocuments: closeDocuments,
            closeOtherDocuments: closeOtherDocuments,
            closeAll: closeAll
        )
    }
}
