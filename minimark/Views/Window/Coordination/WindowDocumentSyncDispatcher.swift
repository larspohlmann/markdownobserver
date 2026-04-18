/// Syncs the sidebar document list + group state on window appear, disappear,
/// and whenever the document list itself changes. Owns the window's
/// `OpenDocumentPathTracker` because only this dispatcher mutates it.
@MainActor
final class WindowDocumentSyncDispatcher {
    let openDocumentPathTracker = OpenDocumentPathTracker()

    private let shell: WindowShellController
    private let sidebarDocumentController: SidebarDocumentController
    private let settingsStore: SettingsStore
    private let groupStateControllerProvider: () -> SidebarGroupStateController?

    init(
        shell: WindowShellController,
        sidebarDocumentController: SidebarDocumentController,
        settingsStore: SettingsStore,
        groupStateControllerProvider: @escaping () -> SidebarGroupStateController?
    ) {
        self.shell = shell
        self.sidebarDocumentController = sidebarDocumentController
        self.settingsStore = settingsStore
        self.groupStateControllerProvider = groupStateControllerProvider
    }

    func handleWindowAppear() {
        let groupState = groupStateControllerProvider()
        groupState?.configureSortModes(
            sortMode: settingsStore.currentSettings.sidebarGroupSortMode,
            fileSortMode: settingsStore.currentSettings.sidebarSortMode
        )
        groupState?.updateDocuments(
            sidebarDocumentController.documents,
            rowStates: sidebarDocumentController.rowStates
        )
        groupState?.observeRowStates(from: sidebarDocumentController)
        openDocumentPathTracker.update(from: sidebarDocumentController.documents)
        shell.configureDockTile()
    }

    func handleWindowDisappear() {
        shell.clearDockTile()
    }

    func handleDocumentListChange() {
        groupStateControllerProvider()?.updateDocuments(
            sidebarDocumentController.documents,
            rowStates: sidebarDocumentController.rowStates
        )
        openDocumentPathTracker.update(from: sidebarDocumentController.documents)
    }
}
