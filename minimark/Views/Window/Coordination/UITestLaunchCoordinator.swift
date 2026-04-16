import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UITestLaunchCoordinator {
    var hasAppliedConfiguration = false
    var watchFlowTask: Task<Void, Never>?

    struct Actions {
        let hostWindow: () -> NSWindow?
        let startWatchingFolder: (URL, ReaderFolderWatchOptions) -> Void
        let presentFolderWatchOptions: (URL, ReaderFolderWatchOptions) -> Void
        let openFileRequest: (FileOpenRequest) -> Void
        let isSessionActive: () -> Bool
    }

    private var actions: Actions?

    func configure(actions: Actions) {
        self.actions = actions
    }

    func applyConfigurationIfNeeded() {
        guard !hasAppliedConfiguration, actions != nil else {
            return
        }

        let action = resolvedLaunchAction()
        switch action {
        case .none:
            // Configuration not yet applicable — either the launch config
            // requests no action, or the host window isn't attached yet.
            // Leave the flag unset so a later trigger (window attach, or
            // configure() once actions are wired) can retry.
            return
        case .simulateGroupedSidebar:
            startGroupedSidebarFlow()
        case .simulateAutoOpenWatchFlow:
            startAutoOpenWatchFlow()
        case .presentWatchFolderSheet(let watchFolderURL):
            applyScreenshotWindowSize()
            var options = ReaderFolderWatchOptions.default
            if ProcessInfo.processInfo.environment[
                ReaderUITestLaunchConfiguration.screenshotWatchScopeEnvironmentKey
            ] == "includeSubfolders" {
                options.scope = .includeSubfolders
            }
            actions?.presentFolderWatchOptions(watchFolderURL, options)
        case .startWatchingFolder(let watchFolderURL):
            actions?.startWatchingFolder(watchFolderURL, .default)
        }
        hasAppliedConfiguration = true
    }

    // MARK: - Private

    private func resolvedLaunchAction() -> ReaderWindowUITestLaunchAction {
        ReaderWindowUITestFlowSupport.resolveLaunchAction(
            configuration: ReaderUITestLaunchConfiguration.current,
            hostWindowAvailable: actions?.hostWindow() != nil
        )
    }

    private func applyScreenshotWindowSize() {
        guard let sizeStr = ProcessInfo.processInfo.environment[
            ReaderUITestLaunchConfiguration.screenshotWindowSizeEnvironmentKey
        ], !sizeStr.isEmpty else { return }

        let parts = sizeStr.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return }

        if let window = actions?.hostWindow() {
            let frame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y,
                width: parts[0],
                height: parts[1]
            )
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func startGroupedSidebarFlow() {
        ReaderWindowUITestFlowSupport.startGroupedSidebarFlow { [actions] fileURLs in
            actions?.openFileRequest(FileOpenRequest(
                fileURLs: fileURLs,
                origin: .manual
            ))
        }
    }

    private func startAutoOpenWatchFlow() {
        ReaderWindowUITestFlowSupport.startAutoOpenWatchFlow(
            startWatchingFolder: { [actions] watchFolderURL in
                actions?.startWatchingFolder(watchFolderURL, .default)
            },
            cancelExistingTask: { [weak self] in
                self?.watchFlowTask?.cancel()
            },
            waitForFolderWatchStartup: { [actions] in
                await ReaderWindowUITestFlowSupport.waitForFolderWatchStartup {
                    actions?.isSessionActive() ?? false
                }
            },
            assignTask: { [weak self] task in
                self?.watchFlowTask = task
            }
        )
    }
}
