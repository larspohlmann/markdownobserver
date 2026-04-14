import AppKit
import Foundation
import Observation

@MainActor
private struct ReaderWindowStoreCallbackConfigurator {
    let lockedAppearanceProvider: @MainActor () -> LockedAppearance?
    let onOpenAdditionalDocument: (URL, ReaderFolderWatchSession?, ReaderOpenOrigin, String?) -> Void

    func configure(_ store: ReaderStore) {
        if let lockedAppearance = lockedAppearanceProvider() {
            store.setAppearanceOverride(lockedAppearance)
        }
        store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, folderWatchSession, origin in
            onOpenAdditionalDocument(
                event.fileURL,
                folderWatchSession,
                origin,
                event.kind == .modified ? event.previousMarkdown : nil
            )
        }
    }
}

@MainActor
@Observable
final class ReaderWindowCoordinator {
    private let settingsStore: ReaderSettingsStore
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private let folderWatchOpenCoordinator = ReaderFolderWatchOpenCoordinator()

    init(
        settingsStore: ReaderSettingsStore,
        sidebarDocumentController: ReaderSidebarDocumentController
    ) {
        self.settingsStore = settingsStore
        self.sidebarDocumentController = sidebarDocumentController
    }

    var hasPendingFolderWatchOpenEvents: Bool {
        folderWatchOpenCoordinator.hasPendingEvents
    }

    func configureStoreCallbacks(
        lockedAppearanceProvider: @escaping @MainActor () -> LockedAppearance? = { nil },
        onOpenAdditionalDocument: @escaping (URL, ReaderFolderWatchSession?, ReaderOpenOrigin, String?) -> Void
    ) {
        sidebarDocumentController.setStoreConfigurator { store in
            ReaderWindowStoreCallbackConfigurator(
                lockedAppearanceProvider: lockedAppearanceProvider,
                onOpenAdditionalDocument: onOpenAdditionalDocument
            ).configure(store)
        }
    }

    func sharedFolderWatchState() -> (session: ReaderFolderWatchSession?, canStop: Bool) {
        (
            sidebarDocumentController.folderWatchCoordinator.activeFolderWatchSession,
            sidebarDocumentController.folderWatchCoordinator.canStopFolderWatch
        )
    }

    func resolveWindowTitle(activeFolderWatch: ReaderFolderWatchSession?) -> String {
        ReaderWindowTitleFormatter.resolveWindowTitle(
            documentTitle: sidebarDocumentController.selectedWindowTitle,
            activeFolderWatch: activeFolderWatch,
            hasUnacknowledgedExternalChange: sidebarDocumentController.selectedHasUnacknowledgedExternalChange
        )
    }

    func enqueueFolderWatchOpen(
        _ event: ReaderFolderWatchChangeEvent,
        folderWatchSession: ReaderFolderWatchSession?,
        origin: ReaderOpenOrigin,
        onFlushRequested: @escaping @MainActor () -> Void
    ) {
        folderWatchOpenCoordinator.enqueue(
            event,
            folderWatchSession: folderWatchSession,
            origin: origin,
            onFlushRequested: onFlushRequested
        )
    }

    func consumeQueuedFolderWatchOpenBatchIfPossible(
        canFlushImmediately: Bool,
        onFlushRequested: @escaping @MainActor () -> Void
    ) -> ReaderFolderWatchOpenBatch? {
        folderWatchOpenCoordinator.consumeBatchIfPossible(
            canFlushImmediately: canFlushImmediately,
            onFlushRequested: onFlushRequested
        )
    }

    func registerWindow(
        _ hostWindow: NSWindow?,
        activeFolderWatch: ReaderFolderWatchSession?
    ) {
        ReaderWindowRegistry.shared.registerWindow(
            hostWindow,
            focusDocument: { [sidebarDocumentController] fileURL in
                sidebarDocumentController.focusDocument(at: fileURL)
            },
            watchedFolderURLProvider: {
                activeFolderWatch?.folderURL
            }
        )
    }
}
