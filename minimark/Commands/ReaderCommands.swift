import AppKit
import SwiftUI

struct ReaderCommands: Commands {
    var settingsStore: ReaderSettingsStore
    let multiFileDisplayMode: MultiFileDisplayMode

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.readerOpenDocument) private var openDocument
    @FocusedValue(\.readerOpenDocumentInCurrentWindow) private var openInCurrentWindow
    @FocusedValue(\.readerOpenAdditionalDocument) private var openAdditionalDocument
    @FocusedValue(\.readerWatchFolder) private var watchFolder
    @FocusedValue(\.readerStartRecentFolderWatch) private var startRecentFolderWatch
    @FocusedValue(\.readerStopFolderWatch) private var stopFolderWatch
    @FocusedValue(\.readerHasActiveFolderWatch) private var hasActiveFolderWatch
    @FocusedValue(\.readerDocumentViewModeContext) private var documentViewModeContext
    @FocusedValue(\.readerChangedRegionNavigation) private var changedRegionNavigation
    @FocusedValue(\.readerSourceEditingContext) private var sourceEditingContext
    @FocusedValue(\.readerToggleTOC) private var toggleTOC

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Markdown...") {
                openMarkdown()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Open Markdown in Current Window...") {
                openMarkdownInCurrentWindow()
            }

            Button(multiFileDisplayMode.secondaryActionLabel) {
                openMarkdownInSidebar()
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button("Open Markdown File(s) in New Window(s)...") {
                openMarkdownInNewWindows()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Menu("Recent Opened Files") {
                recentOpenedFilesMenuContent()
            }
            .disabled(settingsStore.currentSettings.recentManuallyOpenedFiles.isEmpty)

            Divider()

            Button("Watch Folder...") {
                watchFolderFromPicker()
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(watchFolder == nil)

            Button("Stop Watching Folder") {
                stopFolderWatch?()
            }
            .disabled(!(hasActiveFolderWatch ?? false))
        }

        CommandMenu("Watch") {
            Button("Watch Folder...") {
                watchFolderFromPicker()
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(watchFolder == nil)

            Button("Stop Watching Folder") {
                stopFolderWatch?()
            }
            .disabled(!(hasActiveFolderWatch ?? false))

            Menu("Recent Watched Folders") {
                recentWatchedFoldersMenuContent()
            }
            .disabled(settingsStore.currentSettings.recentWatchedFolders.isEmpty)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Source Changes") {
                sourceEditingContext?.saveIfAvailable()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!(sourceEditingContext?.canSave ?? false))
        }

        CommandGroup(after: .toolbar) {
            Button("Edit Source") {
                sourceEditingContext?.startIfAvailable()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!(sourceEditingContext?.canStartEditing ?? false))

            Divider()

            Button("Show Preview") {
                documentViewModeContext?.setMode(.preview)
            }
            .disabled(!(documentViewModeContext?.canSetMode ?? false) || documentViewModeContext?.currentMode == .preview)

            Button("Show Split") {
                documentViewModeContext?.setMode(.split)
            }
            .disabled(!(documentViewModeContext?.canSetMode ?? false) || documentViewModeContext?.currentMode == .split)

            Button("Show Source") {
                documentViewModeContext?.setMode(.source)
            }
            .disabled(!(documentViewModeContext?.canSetMode ?? false) || documentViewModeContext?.currentMode == .source)

            Button("Cycle Document View") {
                documentViewModeContext?.toggleMode()
            }
            .disabled(!(documentViewModeContext?.canSetMode ?? false))

            Divider()

            Button("Previous Change") {
                changedRegionNavigation?(.previous)
            }
            .disabled(!(changedRegionNavigation?.canNavigate ?? false))

            Button("Next Change") {
                changedRegionNavigation?(.next)
            }
            .disabled(!(changedRegionNavigation?.canNavigate ?? false))

            Divider()

            Button("Table of Contents") {
                toggleTOC?()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!(toggleTOC?.canToggle ?? false))
        }

        CommandGroup(replacing: .appInfo) {
            Button("About MarkdownObserver") {
                openWindow(id: AppWindowID.about.rawValue)
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openWindow(id: AppWindowID.settings.rawValue)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }

    private func openMarkdown() {
        openPickedMarkdown(
            usingPrimaryAction: openDocumentAction,
            additionalAction: openAdditionalDocumentAction
        )
    }

    private func openMarkdownInCurrentWindow() {
        openPickedMarkdown(
            usingPrimaryAction: openInCurrentWindowAction,
            additionalAction: openAdditionalDocumentAction
        )
    }

    private func openMarkdownInSidebar() {
        openPickedMarkdown(usingPrimaryAction: openAdditionalDocumentAction)
    }

    private func openMarkdownInNewWindows() {
        guard let urls = MarkdownOpenPanel.pickFiles(allowsMultipleSelection: true) else {
            return
        }

        for url in urls {
            openMarkdownInNewWindow(url)
        }
    }

    @ViewBuilder
    private func recentOpenedFilesMenuContent() -> some View {
        let recentFiles = settingsStore.currentSettings.recentManuallyOpenedFiles
        if recentFiles.isEmpty {
            Text("No recent manually opened files")
        } else {
            let titlesByPath = ReaderRecentHistory.menuTitles(for: recentFiles)
            ForEach(recentFiles) { entry in
                Button(titlesByPath[entry.filePath] ?? entry.displayName) {
                    openRecentOpenedFile(entry)
                }
            }

            Divider()

            Button("Clear History") {
                settingsStore.clearRecentManuallyOpenedFiles()
            }
        }
    }

    @ViewBuilder
    private func recentWatchedFoldersMenuContent() -> some View {
        let recentFolders = settingsStore.currentSettings.recentWatchedFolders
        if recentFolders.isEmpty {
            Text("No recent watched folders")
        } else {
            let titlesByPath = ReaderRecentHistory.menuTitles(for: recentFolders)
            ForEach(recentFolders) { entry in
                Button(titlesByPath[entry.folderPath] ?? entry.displayName) {
                    startRecentWatchedFolder(entry)
                }
            }

            Divider()

            Button("Clear History") {
                settingsStore.clearRecentWatchedFolders()
            }
        }
    }

    private func openRecentOpenedFile(_ entry: RecentOpenedFile) {
        guard let targetWindowNumber else {
            openWindow(value: WindowSeed(recentOpenedFile: entry))
            return
        }

        let payload = ReaderCommandNotification.Payload(
            targetWindowNumber: targetWindowNumber,
            recentFileEntry: entry
        )
        NotificationCenter.default.post(
            name: ReaderCommandNotification.openRecentFile,
            object: nil,
            userInfo: payload.asUserInfo
        )
    }

    private func startRecentWatchedFolder(_ entry: RecentWatchedFolder) {
        guard let targetWindowNumber else {
            openWindow(value: WindowSeed(recentWatchedFolder: entry))
            return
        }

        let payload = ReaderCommandNotification.Payload(
            targetWindowNumber: targetWindowNumber,
            recentWatchedFolderEntry: entry
        )
        NotificationCenter.default.post(
            name: ReaderCommandNotification.prepareRecentWatchedFolder,
            object: nil,
            userInfo: payload.asUserInfo
        )
    }

    private func openPickedMarkdown(
        usingPrimaryAction primaryAction: ((URL) -> Void)?,
        additionalAction: ((URL) -> Void)? = nil
    ) {
        guard let urls = MarkdownOpenPanel.pickFiles(allowsMultipleSelection: true),
              let first = urls.first else {
            return
        }

        routePickedMarkdown(first, using: primaryAction)

        if urls.count == 1 {
            return
        }

        let effectiveAdditionalAction = additionalAction ?? primaryAction
        for url in urls.dropFirst() {
            routePickedMarkdown(url, using: effectiveAdditionalAction)
        }
    }

    private func routePickedMarkdown(_ url: URL, using action: ((URL) -> Void)?) {
        if let action {
            action(url)
            return
        }

        openMarkdownInNewWindow(url)
    }

    private func openMarkdownInNewWindow(_ url: URL) {
        settingsStore.addRecentManuallyOpenedFile(url)
        openWindow(value: WindowSeed(fileURL: url))
    }

    private var targetWindowNumber: Int? {
        NSApp.mainWindow?.windowNumber
    }

    private var openDocumentAction: ((URL) -> Void)? {
        openDocument.map { action in
            action.callAsFunction
        }
    }

    private var openInCurrentWindowAction: ((URL) -> Void)? {
        openInCurrentWindow.map { action in
            action.callAsFunction
        }
    }

    private var openAdditionalDocumentAction: ((URL) -> Void)? {
        openAdditionalDocument.map { action in
            action.callAsFunction
        }
    }

    private func watchFolderFromPicker() {
        guard let folderURL = pickFolder() else {
            return
        }

        watchFolder?(folderURL)
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder to Watch"
        panel.message = "Select a folder, then choose watch options."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose Folder"

        return panel.runModal() == .OK ? panel.url : nil
    }
}
