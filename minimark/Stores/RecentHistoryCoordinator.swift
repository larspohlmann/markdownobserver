import Foundation
import Observation

@MainActor
@Observable
final class RecentHistoryCoordinator {
    private let settingsStore: ReaderSettingsStore
    private var folderWatchFlowController: FolderWatchFlowController?

    init(settingsStore: ReaderSettingsStore) {
        self.settingsStore = settingsStore
    }

    func configure(folderWatchFlowController: FolderWatchFlowController) {
        self.folderWatchFlowController = folderWatchFlowController
    }

    // MARK: - Recent Folder Watch

    func startRecentFolderWatch(_ entry: ReaderRecentWatchedFolder) {
        folderWatchFlowController?.prepareRecentWatch(entry)
    }

    func clearRecentWatchedFolders() {
        settingsStore.clearRecentWatchedFolders()
    }

    // MARK: - Recent Files

    func clearRecentManuallyOpenedFiles() {
        settingsStore.clearRecentManuallyOpenedFiles()
    }

    func openRecentFile(
        _ entry: ReaderRecentOpenedFile,
        using fileOpenCoordinator: FileOpenCoordinator,
        session: ReaderFolderWatchSession?
    ) {
        let resolvedURL = settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [resolvedURL],
            origin: .manual,
            folderWatchSession: session,
            slotStrategy: .replaceSelectedSlot
        ))
    }

    // MARK: - Notification Handling

    func handleOpenRecentFileNotification(
        _ notification: Notification,
        hostWindowNumber: Int?,
        openDocumentInCurrentWindow: (URL) -> Void
    ) {
        guard let payload = ReaderCommandNotification.Payload(notification: notification),
              payload.targetWindowNumber == hostWindowNumber else { return }
        guard let entry = payload.recentFileEntry else { return }
        let resolvedURL = settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
        openDocumentInCurrentWindow(resolvedURL)
    }

    func handlePrepareRecentWatchedFolderNotification(
        _ notification: Notification,
        hostWindowNumber: Int?
    ) {
        guard let payload = ReaderCommandNotification.Payload(notification: notification),
              payload.targetWindowNumber == hostWindowNumber else { return }
        guard let entry = payload.recentWatchedFolderEntry else { return }
        startRecentFolderWatch(entry)
    }
}
