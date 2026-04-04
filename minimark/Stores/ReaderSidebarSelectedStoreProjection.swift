import Foundation
import Combine

@MainActor
final class ReaderSidebarSelectedStoreProjection {
    @MainActor
    struct State {
        let windowTitle: String
        let fileURL: URL?
        let hasUnacknowledgedExternalChange: Bool
        let folderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning?

        init(readerStore: ReaderStore) {
            windowTitle = readerStore.windowTitle
            fileURL = readerStore.fileURL
            hasUnacknowledgedExternalChange = readerStore.hasUnacknowledgedExternalChange
            folderWatchAutoOpenWarning = readerStore.folderWatchAutoOpenWarning
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    func bind(
        to readerStore: ReaderStore,
        apply: @escaping @MainActor (State) -> Void
    ) {
        cancellables.removeAll()

        func publishState() {
            apply(State(readerStore: readerStore))
        }

        publishState()

        readerStore.$document
            .sink { _ in
                publishState()
            }
            .store(in: &cancellables)

        readerStore.$folderWatchAutoOpenWarning
            .sink { _ in
                publishState()
            }
            .store(in: &cancellables)
    }
}
