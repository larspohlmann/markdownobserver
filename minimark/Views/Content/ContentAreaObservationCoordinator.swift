import Foundation
import Observation

@MainActor
final class ContentAreaObservationCoordinator {
    private var tasks: [Task<Void, Never>] = []
    private var didSetUp = false

    deinit {
        for task in tasks { task.cancel() }
    }

    func ensureSetup(for viewModel: ContentAreaViewModel) {
        guard !didSetUp else { return }
        didSetUp = true

        track(viewModel: viewModel) { vm in
            vm.document.fileURL?.standardizedFileURL.path
        } react: { vm, _ in
            vm.surfaceViewModel.handleFileIdentityChange()
        }

        track(viewModel: viewModel) { vm in
            vm.document.changedRegions
        } react: { vm, _ in
            vm.surfaceViewModel.changeNavigation.resetForNewRegions()
        }

        track(viewModel: viewModel) { vm in
            vm.surfaceViewModel.previewMode
        } react: { vm, mode in
            vm.surfaceViewModel.handlePreviewModeChange(mode)
        }

        track(viewModel: viewModel) { vm in
            vm.surfaceViewModel.sourceMode
        } react: { vm, mode in
            vm.surfaceViewModel.handleSourceModeChange(mode)
        }

        track(viewModel: viewModel) { vm in
            vm.sourceEditing.documentViewMode
        } react: { vm, mode in
            vm.surfaceViewModel.handleDocumentViewModeChange(mode)
        }

        track(viewModel: viewModel) { vm in
            vm.sourceEditing.sourceEditorSeedMarkdown
        } react: { vm, _ in
            vm.refreshSourceHTMLFromControllers()
        }

        track(viewModel: viewModel) { vm in
            vm.settingsStore.currentSettings
        } react: { vm, _ in
            vm.refreshSourceHTMLFromControllers()
        }

        track(viewModel: viewModel) { vm in
            vm.sourceEditing.isSourceEditing
        } react: { vm, _ in
            vm.refreshSourceHTMLFromControllers()
        }

        track(viewModel: viewModel) { vm in
            vm.folderWatchState.activeFolderWatch?.folderURL.standardizedFileURL.path
        } react: { vm, _ in
            vm.surfaceViewModel.dropTargeting.clearAll()
        }
    }

    private func track<Value: Equatable>(
        viewModel: ContentAreaViewModel,
        read: @escaping @MainActor (ContentAreaViewModel) -> Value,
        react: @escaping @MainActor (ContentAreaViewModel, Value) -> Void
    ) {
        var previous = read(viewModel)
        let task = Task { [weak viewModel] in
            while !Task.isCancelled {
                guard let currentVM = viewModel else { return }
                let cancelled = await Self.awaitObservationChange {
                    _ = read(currentVM)
                }
                if cancelled { return }
                guard let latestVM = viewModel else { return }
                let next = read(latestVM)
                if next != previous {
                    previous = next
                    react(latestVM, next)
                }
            }
        }
        tasks.append(task)
    }

    private static func awaitObservationChange(
        tracking: @escaping @MainActor () -> Void
    ) async -> Bool {
        let box = ObservationContinuationBox()
        return await withTaskCancellationHandler {
            await withUnsafeContinuation { continuation in
                box.store(continuation)
                if Task.isCancelled {
                    box.resume(returning: true)
                    return
                }
                withObservationTracking {
                    tracking()
                } onChange: {
                    box.resume(returning: false)
                }
            }
        } onCancel: {
            box.resume(returning: true)
        }
    }

    private final class ObservationContinuationBox: @unchecked Sendable {
        private nonisolated(unsafe) var continuation: UnsafeContinuation<Bool, Never>?
        private nonisolated let lock = NSLock()

        nonisolated func store(_ continuation: UnsafeContinuation<Bool, Never>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        nonisolated func resume(returning value: Bool) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }
}
