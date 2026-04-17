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
        let startWatchingFolder: (URL, FolderWatchOptions) -> Void
        let presentFolderWatchOptions: (URL, FolderWatchOptions) -> Void
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
            // Defer only while the host window hasn't attached yet. Once it
            // is present, `.none` means the launch config simply requests no
            // action (UI-test mode off, or no matching flag) — mark applied
            // so we don't keep re-running on every handleHostWindowChange().
            guard actions?.hostWindow() != nil else {
                return
            }
        case .simulateGroupedSidebar:
            startGroupedSidebarFlow()
        case .simulateAutoOpenWatchFlow:
            startAutoOpenWatchFlow()
        case .presentWatchFolderSheet(let watchFolderURL):
            applyScreenshotWindowSize()
            var options = FolderWatchOptions.default
            if ProcessInfo.processInfo.environment[
                UITestLaunchConfiguration.screenshotWatchScopeEnvironmentKey
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

    private func resolvedLaunchAction() -> WindowUITestLaunchAction {
        WindowUITestFlowSupport.resolveLaunchAction(
            configuration: UITestLaunchConfiguration.current,
            hostWindowAvailable: actions?.hostWindow() != nil
        )
    }

    private func applyScreenshotWindowSize() {
        guard let sizeStr = ProcessInfo.processInfo.environment[
            UITestLaunchConfiguration.screenshotWindowSizeEnvironmentKey
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
        WindowUITestFlowSupport.startGroupedSidebarFlow { [actions] fileURLs in
            actions?.openFileRequest(FileOpenRequest(
                fileURLs: fileURLs,
                origin: .manual
            ))
        }
    }

    private func startAutoOpenWatchFlow() {
        WindowUITestFlowSupport.startAutoOpenWatchFlow(
            startWatchingFolder: { [actions] watchFolderURL in
                actions?.startWatchingFolder(watchFolderURL, .default)
            },
            cancelExistingTask: { [weak self] in
                self?.watchFlowTask?.cancel()
            },
            waitForFolderWatchStartup: { [actions] in
                await WindowUITestFlowSupport.waitForFolderWatchStartup {
                    actions?.isSessionActive() ?? false
                }
            },
            assignTask: { [weak self] task in
                self?.watchFlowTask = task
            }
        )
    }
}
