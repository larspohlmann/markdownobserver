import Combine
import Foundation

@MainActor
final class ReaderFolderWatchAutoOpenWarningCoordinator: ObservableObject {
    @Published var activeFlow: FolderWatchAutoOpenWarningFlow?

    private var queuedWarning: ReaderFolderWatchAutoOpenWarning?
    private var presentationTask: Task<Void, Never>?

    deinit {
        presentationTask?.cancel()
    }

    func handleWarningChange(
        _ warning: ReaderFolderWatchAutoOpenWarning?,
        canPresent: @escaping @MainActor () -> Bool
    ) {
        guard let warning else {
            if activeFlow != nil || queuedWarning != nil {
                schedulePresentationIfNeeded(canPresent: canPresent)
                return
            }

            presentationTask?.cancel()
            presentationTask = nil
            return
        }

        queuedWarning = warning
        schedulePresentationIfNeeded(canPresent: canPresent)
    }

    func dismiss(clearPersistedWarning: () -> Void) {
        presentationTask?.cancel()
        presentationTask = nil
        queuedWarning = nil
        activeFlow = nil
        clearPersistedWarning()
    }

    func selectedFileURLs() -> [URL] {
        guard let flow = activeFlow else {
            return []
        }

        return flow.warning.omittedFileURLs.filter { fileURL in
            flow.selectionModel.selectedFileURLs.contains(fileURL)
        }
    }

    private func schedulePresentationIfNeeded(
        canPresent: @escaping @MainActor () -> Bool
    ) {
        guard queuedWarning != nil,
              activeFlow == nil else {
            return
        }

        presentationTask?.cancel()
        presentationTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let warning = queuedWarning else {
                    presentationTask = nil
                    return
                }

                if canPresent() {
                    queuedWarning = nil
                    presentationTask = nil
                    activeFlow = FolderWatchAutoOpenWarningFlow(warning: warning)
                    return
                }

                try? await Task.sleep(for: .milliseconds(100))
            }

            presentationTask = nil
        }
    }
}