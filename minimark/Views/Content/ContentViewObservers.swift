import SwiftUI

struct ContentViewObservers: ViewModifier {
    let viewModel: ContentAreaViewModel

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.document.fileURL?.standardizedFileURL.path) { _, _ in
                viewModel.surfaceViewModel.handleFileIdentityChange()
            }
            .onChange(of: viewModel.document.changedRegions) { _, _ in
                viewModel.surfaceViewModel.changeNavigation.resetForNewRegions()
            }
            .onChange(of: viewModel.surfaceViewModel.previewMode) { _, newValue in
                viewModel.surfaceViewModel.handlePreviewModeChange(newValue)
            }
            .onChange(of: viewModel.surfaceViewModel.sourceMode) { _, newValue in
                viewModel.surfaceViewModel.handleSourceModeChange(newValue)
            }
            .onChange(of: viewModel.sourceEditing.documentViewMode) { _, newValue in
                viewModel.surfaceViewModel.handleDocumentViewModeChange(newValue)
            }
            .onChange(of: viewModel.sourceEditing.sourceEditorSeedMarkdown) { _, _ in
                viewModel.refreshSourceHTMLFromControllers()
            }
            .onChange(of: viewModel.settingsStore.currentSettings) { _, _ in
                viewModel.refreshSourceHTMLFromControllers()
            }
            .onChange(of: viewModel.sourceEditing.isSourceEditing) { _, _ in
                viewModel.refreshSourceHTMLFromControllers()
            }
            .onChange(of: viewModel.folderWatchState.activeFolderWatch?.folderURL.standardizedFileURL.path) { _, _ in
                viewModel.surfaceViewModel.dropTargeting.clearAll()
            }
    }
}
