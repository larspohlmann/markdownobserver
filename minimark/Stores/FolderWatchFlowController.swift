// minimark/Stores/FolderWatchFlowController.swift
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class FolderWatchFlowController {
    struct PendingFolderWatchRequest {
        let folderURL: URL
        var options: ReaderFolderWatchOptions
    }

    // Presentation state
    var isFolderWatchOptionsPresented = false
    var pendingFolderWatchRequest: PendingFolderWatchRequest?
    var sharedFolderWatchSession: ReaderFolderWatchSession?
    var canStopSharedFolderWatch = false
    var warningCoordinator = ReaderFolderWatchAutoOpenWarningCoordinator()

    var pendingFolderWatchURL: URL? {
        pendingFolderWatchRequest?.folderURL
    }

    private let sidebarDocumentController: ReaderSidebarDocumentController

    init(sidebarDocumentController: ReaderSidebarDocumentController) {
        self.sidebarDocumentController = sidebarDocumentController
    }

    // MARK: - Presentation State

    func presentOptions(for folderURL: URL, options: ReaderFolderWatchOptions) {
        pendingFolderWatchRequest = PendingFolderWatchRequest(
            folderURL: folderURL,
            options: options
        )
        isFolderWatchOptionsPresented = true
    }

    func prepareOptions(for folderURL: URL) {
        presentOptions(for: folderURL, options: .default)
    }

    func prepareRecentWatch(_ entry: ReaderRecentWatchedFolder, settingsStore: ReaderSettingsStore) {
        let resolvedFolderURL = settingsStore.resolvedRecentWatchedFolderURL(matching: entry.folderURL) ?? entry.folderURL
        presentOptions(for: resolvedFolderURL, options: entry.options)
    }

    func cancelPendingWatch() {
        isFolderWatchOptionsPresented = false
        pendingFolderWatchRequest = nil
    }

    func updatePendingRequest(_ update: (inout PendingFolderWatchRequest) -> Void) {
        guard var request = pendingFolderWatchRequest else { return }
        update(&request)
        pendingFolderWatchRequest = request
    }

    // MARK: - Shared State Sync

    func refreshSharedState() {
        sharedFolderWatchSession = sidebarDocumentController.folderWatchCoordinator.activeFolderWatchSession
        canStopSharedFolderWatch = sidebarDocumentController.folderWatchCoordinator.canStopFolderWatch
    }

    // MARK: - Warning Flow

    func handleAutoOpenWarningChange(
        _ warning: ReaderFolderWatchAutoOpenWarning?,
        canPresent: @escaping @MainActor () -> Bool
    ) {
        warningCoordinator.handleWarningChange(warning, canPresent: canPresent)
    }

    func refreshAutoOpenWarningPresentation(canPresent: @escaping @MainActor () -> Bool) {
        let warning = sidebarDocumentController.folderWatchCoordinator.selectedFolderWatchAutoOpenWarning
        handleAutoOpenWarningChange(warning, canPresent: canPresent)
    }

    func dismissAutoOpenWarning() {
        warningCoordinator.dismiss {
            sidebarDocumentController.folderWatchCoordinator.dismissFolderWatchAutoOpenWarnings()
        }
    }

    func openSelectedAutoOpenFiles(using fileOpenCoordinator: FileOpenCoordinator) {
        let selectedFileURLs = warningCoordinator.selectedFileURLs()
        guard !selectedFileURLs.isEmpty else {
            dismissAutoOpenWarning()
            return
        }
        dismissAutoOpenWarning()
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: selectedFileURLs,
            origin: .manual,
            slotStrategy: .alwaysAppend
        ))
    }

    // MARK: - Exclusions

    func closeDocumentsInExcludedPaths(_ excludedPaths: [String]) {
        let excludedPrefixes = excludedPaths.map { path in
            let normalized = ReaderFileRouting.normalizedFileURL(
                URL(fileURLWithPath: path, isDirectory: true)
            ).path
            return normalized.hasSuffix("/") ? normalized : normalized + "/"
        }

        let wasSelectedExcluded = sidebarDocumentController.selectedDocument.flatMap { doc in
            doc.readerStore.document.fileURL.map { url in
                let normalized = ReaderFileRouting.normalizedFileURL(url).path
                return excludedPrefixes.contains { normalized.hasPrefix($0) }
            }
        } ?? false

        let documentsToClose = sidebarDocumentController.documents.filter { doc in
            guard let fileURL = doc.readerStore.document.fileURL else { return false }
            let normalized = ReaderFileRouting.normalizedFileURL(fileURL).path
            return excludedPrefixes.contains { normalized.hasPrefix($0) }
        }

        for doc in documentsToClose {
            sidebarDocumentController.closeDocument(doc.id)
        }

        if wasSelectedExcluded {
            sidebarDocumentController.selectDocumentWithNewestModificationDate()
        }
    }

    func openFilesInNewlyIncludedPaths(
        _ includedPaths: [String],
        fileOpenCoordinator: FileOpenCoordinator
    ) {
        let includedPrefixes = includedPaths.map { path in
            let normalized = ReaderFileRouting.normalizedFileURL(
                URL(fileURLWithPath: path, isDirectory: true)
            ).path
            return normalized.hasSuffix("/") ? normalized : normalized + "/"
        }

        sidebarDocumentController.folderWatchCoordinator.scanCurrentMarkdownFiles { [self] scannedURLs in
            guard let session = sharedFolderWatchSession else { return }

            let alreadyOpenPaths = Set(
                sidebarDocumentController.documents.compactMap {
                    $0.readerStore.document.fileURL.map { ReaderFileRouting.normalizedFileURL($0).path }
                }
            )

            let newFileURLs = scannedURLs.filter { url in
                let normalized = ReaderFileRouting.normalizedFileURL(url).path
                guard !alreadyOpenPaths.contains(normalized) else { return false }
                return includedPrefixes.contains { normalized.hasPrefix($0) }
            }

            if !newFileURLs.isEmpty {
                fileOpenCoordinator.open(FileOpenRequest(
                    fileURLs: newFileURLs,
                    origin: .folderWatchInitialBatchAutoOpen,
                    folderWatchSession: session,
                    slotStrategy: .alwaysAppend,
                    materializationStrategy: .deferThenMaterializeNewest(count: 1)
                ))
            }
        }
    }

    // MARK: - Helpers

    func isWarningPresentationAllowed(hostWindow: NSWindow?) -> Bool {
        let targetWindow = hostWindow ?? NSApp.keyWindow
        return !isFolderWatchOptionsPresented && targetWindow?.attachedSheet == nil
    }
}
