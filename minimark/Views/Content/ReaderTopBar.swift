import AppKit
import SwiftUI

private func abbreviatePathWithTilde(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}

struct ReaderTopBar: View {
    @ObservedObject var readerStore: ReaderStore
    let documentViewMode: ReaderDocumentViewMode
    let showSourceEditingControls: Bool
    let activeFolderWatch: ReaderFolderWatchSession?
    let isFolderWatchInitialScanInProgress: Bool
    let didFolderWatchInitialScanFail: Bool
    let folderWatchHighlightColor: Color
    let canNavigateChangedRegions: Bool
    let canStopFolderWatch: Bool
    let isCurrentWatchAFavorite: Bool
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let onNavigateChangedRegion: (ReaderChangedRegionNavigationDirection) -> Void
    let onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void
    let onOpenFile: (URL) -> Void
    let onRequestFolderWatch: (URL) -> Void
    let onStopFolderWatch: () -> Void
    let onSaveFolderWatchAsFavorite: (String) -> Void
    let onRemoveCurrentWatchFromFavorites: () -> Void
    let onStartFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
    let onClearFavoriteWatchedFolders: () -> Void
    let onRenameFavoriteWatchedFolder: (UUID, String) -> Void
    let onRemoveFavoriteWatchedFolder: (UUID) -> Void
    let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onClearRecentManuallyOpenedFiles: () -> Void
    let onStartSourceEditing: () -> Void
    let onSaveSourceDraft: () -> Void
    let onDiscardSourceDraft: () -> Void

    private enum Metrics {
        static let barHorizontalPadding: CGFloat = 12
        static let mainBarHeight: CGFloat = 44
        static let watchStripHeight: CGFloat = 30
        static let watchButtonMinWidth: CGFloat = 120
        static let controlHeight: CGFloat = 28
        static let watchButtonToDocSpacing: CGFloat = 16
        static let editingBannerVerticalPadding: CGFloat = 3
        static let editingBannerTextSpacing: CGFloat = 6
        static let editingBannerLabelSize: CGFloat = 10
        static let editingBannerIconSize: CGFloat = 8
        static let editingBannerButtonIconSize: CGFloat = 8
        static let editingBannerButtonHeight: CGFloat = 16
        static let editingBannerCornerRadius: CGFloat = 8
        static let trailingControlSpacing: CGFloat = 5
        static let watchStripHorizontalPadding: CGFloat = 14
        static let watchStripButtonHeight: CGFloat = 22
    }

    @State private var isEditingFavorites = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                FolderWatchToolbarButton(
                    activeFolderWatch: activeFolderWatch,
                    favoriteWatchedFolders: favoriteWatchedFolders,
                    recentWatchedFolders: recentWatchedFolders,
                    onActivate: handleFolderWatchToolbarButton,
                    onStartFavoriteWatch: onStartFavoriteWatch,
                    onStartRecentFolderWatch: onStartRecentFolderWatch,
                    onClearFavoriteWatchedFolders: onClearFavoriteWatchedFolders,
                    onEditFavoriteWatchedFolders: { isEditingFavorites = true },
                    onClearRecentWatchedFolders: onClearRecentWatchedFolders
                )

                Spacer().frame(width: Metrics.watchButtonToDocSpacing)

                BreadcrumbDocumentContext(
                    readerStore: readerStore,
                    onRevealInFinder: { readerStore.revealCurrentFileInFinder() }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: Metrics.trailingControlSpacing) {
                    if canNavigateChangedRegions {
                        ChangeNavigationControls(
                            canNavigate: canNavigateChangedRegions,
                            onNavigateChangedRegion: onNavigateChangedRegion
                        )
                    }

                    if showSourceEditingControls && !readerStore.isSourceEditing {
                        SourceEditingControls(
                            canStartEditing: readerStore.canStartSourceEditing,
                            onStartEditing: onStartSourceEditing
                        )
                    }

                    DocumentViewModeSwitch(
                        hasFile: readerStore.fileURL != nil,
                        documentViewMode: documentViewMode,
                        onSetDocumentViewMode: onSetDocumentViewMode
                    )

                    OpenInMenuButton(
                        hasFile: readerStore.fileURL != nil,
                        hasActiveFolderWatch: canStopFolderWatch,
                        apps: readerStore.openInApplications,
                        favoriteWatchedFolders: favoriteWatchedFolders,
                        recentWatchedFolders: recentWatchedFolders,
                        recentManuallyOpenedFiles: recentManuallyOpenedFiles,
                        iconProvider: appIconImage(for:),
                        onOpenFile: onOpenFile,
                        onOpenApp: { app in
                            readerStore.openCurrentFileInApplication(app)
                        },
                        onRevealInFinder: {
                            readerStore.revealCurrentFileInFinder()
                        },
                        onRequestFolderWatch: onRequestFolderWatch,
                        onStopFolderWatch: onStopFolderWatch,
                        onStartFavoriteWatch: onStartFavoriteWatch,
                        onClearFavoriteWatchedFolders: onClearFavoriteWatchedFolders,
                        onEditFavoriteWatchedFolders: { isEditingFavorites = true },
                        onStartRecentManuallyOpenedFile: onStartRecentManuallyOpenedFile,
                        onStartRecentFolderWatch: onStartRecentFolderWatch,
                        onClearRecentWatchedFolders: onClearRecentWatchedFolders,
                        onClearRecentManuallyOpenedFiles: onClearRecentManuallyOpenedFiles
                    )
                    .accessibilityLabel("Open in and watch actions")
                    .accessibilityHint("Open a file, choose an app, reveal in Finder, or manage folder watch")
                    .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                    .fixedSize()
                }
            }
            .padding(.horizontal, Metrics.barHorizontalPadding)
            .frame(height: Metrics.mainBarHeight)

            if let activeWatch = activeFolderWatch {
                WatchStrip(
                    activeFolderWatch: activeWatch,
                    isCurrentWatchAFavorite: isCurrentWatchAFavorite,
                    highlightColor: folderWatchHighlightColor,
                    canStop: canStopFolderWatch,
                    onStop: onStopFolderWatch,
                    onSaveFavorite: onSaveFolderWatchAsFavorite,
                    onRemoveFavorite: onRemoveCurrentWatchFromFavorites,
                    onRevealInFinder: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: activeWatch.folderURL.path)
                    }
                )
            }

            if readerStore.isSourceEditing {
                SourceEditingStatusBar(
                    hasUnsavedChanges: readerStore.hasUnsavedDraftChanges,
                    canSave: readerStore.canSaveSourceDraft,
                    canDiscard: readerStore.canDiscardSourceDraft,
                    onSave: onSaveSourceDraft,
                    onDiscard: onDiscardSourceDraft
                )
            }
        }
        .background {
            Rectangle()
                .fill(.regularMaterial)
        }
        .overlay(alignment: .bottom) {
            Divider()
                .overlay(Color.primary.opacity(0.10))
        }
        .task(id: readerStore.fileURL) {
            readerStore.refreshOpenInApplications()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            readerStore.refreshOpenInApplications()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            readerStore.refreshOpenInApplications()
        }
        .sheet(isPresented: $isEditingFavorites) {
            EditFavoritesSheet(
                favorites: favoriteWatchedFolders,
                onRename: onRenameFavoriteWatchedFolder,
                onDelete: onRemoveFavoriteWatchedFolder,
                onDismiss: { isEditingFavorites = false }
            )
        }
    }

    private func handleFolderWatchToolbarButton() {
        promptForFolderWatch()
    }

    private func promptForFolderWatch() {
        guard let folderURL = pickFolderToWatch() else {
            return
        }

        onRequestFolderWatch(folderURL)
    }

    private func pickFolderToWatch() -> URL? {
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

    private struct FolderWatchToolbarButton: View {
        let activeFolderWatch: ReaderFolderWatchSession?
        let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
        let recentWatchedFolders: [ReaderRecentWatchedFolder]
        let onActivate: () -> Void
        let onStartFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
        let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
        let onClearFavoriteWatchedFolders: () -> Void
        let onEditFavoriteWatchedFolders: () -> Void
        let onClearRecentWatchedFolders: () -> Void

        @Environment(\.colorScheme) private var colorScheme
        @State private var isMenuPresented = false

        private var isActive: Bool { activeFolderWatch != nil }

        private var activeButtonColor: Color {
            colorScheme == .dark
                ? Color(red: 0.59, green: 0.49, blue: 1.0)
                : Color(red: 0.34, green: 0.24, blue: 0.71)
        }

        private var backgroundFill: Color {
            isActive ? activeButtonColor.opacity(colorScheme == .dark ? 0.10 : 0.07) : Color.primary.opacity(0.04)
        }

        private var borderColor: Color {
            isActive ? activeButtonColor.opacity(colorScheme == .dark ? 0.20 : 0.18) : Color.primary.opacity(0.08)
        }

        var body: some View {
            HStack(spacing: 0) {
                Button {
                    onActivate()
                } label: {
                    mainButtonLabel
                }
                .buttonStyle(.plain)
                .help(isActive ? "Watch a different folder" : "Watch Folder...")
                .accessibilityIdentifier("folder-watch-toolbar-button")
                .accessibilityLabel("Watch folder")
                .accessibilityValue(isActive ? "Active" : "Inactive")
                .accessibilityHint("Opens the folder picker for starting folder watch")

                Rectangle()
                    .fill(isActive ? activeButtonColor.opacity(0.18) : Color.primary.opacity(0.08))
                    .frame(width: 1, height: 16)

                Button {
                    isMenuPresented = true
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 22, height: Metrics.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Favorites and recent watches")
                .accessibilityLabel("Watch menu")
                .popover(isPresented: $isMenuPresented, arrowEdge: .bottom) {
                    watchMenuPopover
                }
            }
            .foregroundStyle(isActive ? AnyShapeStyle(activeButtonColor) : AnyShapeStyle(.primary))
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(backgroundFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: true)
        }

        private var mainButtonLabel: some View {
            HStack(spacing: 6) {
                Image(systemName: "binoculars.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))

                Text(isActive ? "Watching" : "Watch Folder")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .frame(minWidth: Metrics.watchButtonMinWidth, alignment: .leading)
            .frame(height: Metrics.controlHeight)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .contentShape(Rectangle())
        }

        @ViewBuilder
        private var watchMenuPopover: some View {
            VStack(alignment: .leading, spacing: 0) {
                if !favoriteWatchedFolders.isEmpty {
                    menuSectionHeader("Favorites")

                    ForEach(favoriteWatchedFolders) { entry in
                        Button {
                            isMenuPresented = false
                            onStartFavoriteWatch(entry)
                        } label: {
                            Label {
                                Text(entry.name)
                                    .lineLimit(1)
                            } icon: {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }

                    Divider().padding(.vertical, 4)

                    Button("Edit Favorites\u{2026}") {
                        isMenuPresented = false
                        onEditFavoriteWatchedFolders()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }

                if !recentWatchedFolders.isEmpty {
                    if !favoriteWatchedFolders.isEmpty {
                        Divider().padding(.vertical, 4)
                    }

                    menuSectionHeader("Recent")

                    let titlesByPath = ReaderRecentHistory.menuTitles(for: recentWatchedFolders)
                    ForEach(recentWatchedFolders) { entry in
                        Button {
                            isMenuPresented = false
                            onStartRecentFolderWatch(entry)
                        } label: {
                            Text(titlesByPath[entry.folderPath] ?? entry.displayName)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }

                    Button("Clear History") {
                        isMenuPresented = false
                        onClearRecentWatchedFolders()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }

                if favoriteWatchedFolders.isEmpty && recentWatchedFolders.isEmpty {
                    Text("No favorites or recent watches")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .font(.system(size: 13))
            .padding(.vertical, 8)
            .frame(minWidth: 220, maxWidth: 320)
        }

        private func menuSectionHeader(_ title: String) -> some View {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        }
    }

    private struct ChangeNavigationControls: View {
        let canNavigate: Bool
        let onNavigateChangedRegion: (ReaderChangedRegionNavigationDirection) -> Void

        var body: some View {
            HStack(spacing: 4) {
                navigationButton(
                    symbolName: "arrow.up",
                    label: "Previous change",
                    direction: .previous
                )

                navigationButton(
                    symbolName: "arrow.down",
                    label: "Next change",
                    direction: .next
                )
            }
            .accessibilityElement(children: .contain)
        }

        private func navigationButton(
            symbolName: String,
            label: String,
            direction: ReaderChangedRegionNavigationDirection
        ) -> some View {
            Button {
                onNavigateChangedRegion(direction)
            } label: {
                Image(systemName: symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(
                        width: Metrics.controlHeight,
                        height: Metrics.controlHeight
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(canNavigate ? 0.06 : 0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(canNavigate ? 0.10 : 0.05), lineWidth: 1)
            }
            .foregroundStyle(canNavigate ? .primary : .tertiary)
            .disabled(!canNavigate)
            .help(label)
            .accessibilityLabel(label)
            .accessibilityHint("Jumps to a changed region in the current preview")
        }
    }

    private struct BreadcrumbDocumentContext: View {
        @ObservedObject var readerStore: ReaderStore
        let onRevealInFinder: () -> Void

        private var hasFile: Bool { readerStore.fileURL != nil }

        private var titleText: String {
            if readerStore.fileDisplayName.isEmpty {
                return "No document open"
            }
            return readerStore.fileDisplayName
        }

        private var breadcrumbPath: String {
            guard let url = readerStore.fileURL else { return "" }
            let path = url.deletingLastPathComponent().path
            return abbreviatePathWithTilde(path)
                .split(separator: "/", omittingEmptySubsequences: true)
                .joined(separator: " \u{203A} ")
        }

        var body: some View {
            if hasFile {
                Button {
                    onRevealInFinder()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(titleText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        BreadcrumbTimestampLine(
                            breadcrumbPath: breadcrumbPath,
                            statusTimestamp: readerStore.statusBarTimestamp,
                            hasFile: true,
                            isCurrentFileMissing: readerStore.isCurrentFileMissing
                        )
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .help("Reveal in Finder")
                .accessibilityLabel("Current document")
                .accessibilityValue(titleText)
                .accessibilityHint("Reveals this file in Finder")
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("No document open")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("Open a Markdown file to start reading")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .accessibilityLabel("No document open")
            }
        }
    }

    private struct BreadcrumbTimestampLine: View {
        let breadcrumbPath: String
        let statusTimestamp: ReaderStatusBarTimestamp?
        let hasFile: Bool
        let isCurrentFileMissing: Bool

        var body: some View {
            TimelineView(.periodic(from: .now, by: 20)) { context in
                Text(lineText(relativeTo: context.date))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }

        private func lineText(relativeTo now: Date) -> String {
            var parts = breadcrumbPath
            if isCurrentFileMissing {
                parts += " \u{00B7} File deleted externally"
            } else if let statusTimestamp {
                let date: Date
                switch statusTimestamp {
                case let .updated(d), let .lastModified(d):
                    date = d
                }
                let relative = ReaderStatusFormatting.relativeText(for: date, relativeTo: now)
                parts += " \u{00B7} \(relative)"
            }
            return parts
        }
    }

    private struct WatchStrip: View {
        let activeFolderWatch: ReaderFolderWatchSession
        let isCurrentWatchAFavorite: Bool
        let highlightColor: Color
        let canStop: Bool
        let onStop: () -> Void
        let onSaveFavorite: (String) -> Void
        let onRemoveFavorite: () -> Void
        let onRevealInFinder: () -> Void

        @Environment(\.colorScheme) private var colorScheme

        private var stripGreen: Color {
            colorScheme == .dark
                ? Color(red: 0.30, green: 0.81, blue: 0.49)
                : Color(red: 0.13, green: 0.54, blue: 0.33)
        }

        private var stripBackground: Color {
            stripGreen.opacity(colorScheme == .dark ? 0.055 : 0.06)
        }

        private var stripBorder: Color {
            stripGreen.opacity(colorScheme == .dark ? 0.10 : 0.12)
        }

        private var tildeAbbreviatedPath: String {
            abbreviatePathWithTilde(activeFolderWatch.folderURL.path)
        }

        private var filteredCount: Int {
            activeFolderWatch.excludedSubdirectoryRelativePaths.count
        }

        var body: some View {
            HStack(spacing: 8) {
                Text("WATCHING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(stripGreen.opacity(0.55))
                    .tracking(0.4)

                Button {
                    onRevealInFinder()
                } label: {
                    HStack(spacing: 5) {
                        Text(tildeAbbreviatedPath)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(stripGreen.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if filteredCount > 0 {
                            Text("[\(filteredCount) filtered]")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(stripGreen.opacity(0.45))
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .help("Reveal in Finder")
                .accessibilityLabel("Watched folder path")
                .accessibilityValue(tildeAbbreviatedPath)
                .accessibilityHint("Opens the watched folder in Finder")

                Spacer(minLength: 0)

                FavoriteStarToggle(
                    isCurrentWatchAFavorite: isCurrentWatchAFavorite,
                    folderDisplayName: activeFolderWatch.detailSummaryTitle,
                    onSave: onSaveFavorite,
                    onRemove: onRemoveFavorite
                )

                Button {
                    onStop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 7, weight: .bold))
                        Text("Stop")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: Metrics.watchStripButtonHeight)
                    .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(0.4))
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.08)))
                .disabled(!canStop)
                .accessibilityLabel("Stop watching folder")
                .accessibilityHint("Stops monitoring the current folder")
            }
            .padding(.horizontal, Metrics.watchStripHorizontalPadding)
            .frame(minHeight: Metrics.watchStripHeight)
            .background(stripBackground)
            .overlay(alignment: .top) {
                Rectangle().fill(stripBorder).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(stripBorder).frame(height: 1)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private struct FavoriteStarToggle: View {
        let isCurrentWatchAFavorite: Bool
        let folderDisplayName: String
        let onSave: (String) -> Void
        let onRemove: () -> Void

        @State private var isShowingSaveSheet = false
        @State private var favoriteName = ""

        var body: some View {
            Button {
                if isCurrentWatchAFavorite {
                    onRemove()
                } else {
                    favoriteName = folderDisplayName
                    isShowingSaveSheet = true
                }
            } label: {
                Image(systemName: isCurrentWatchAFavorite ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isCurrentWatchAFavorite ? .yellow : .secondary)
                    .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCurrentWatchAFavorite ? "Remove from favorites" : "Save as favorite")
            .accessibilityLabel(isCurrentWatchAFavorite ? "Remove from favorites" : "Save as favorite")
            .sheet(isPresented: $isShowingSaveSheet) {
                SaveFavoriteSheet(
                    name: $favoriteName,
                    onSave: { name in
                        onSave(name)
                        isShowingSaveSheet = false
                    },
                    onCancel: {
                        isShowingSaveSheet = false
                    }
                )
            }
        }
    }

    private struct SourceEditingControls: View {
        let canStartEditing: Bool
        let onStartEditing: () -> Void

        var body: some View {
            editButton
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityElement(children: .contain)
        }

        private var editButton: some View {
            Button {
                onStartEditing()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))

                    Text("Edit")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 12)
                .frame(height: Metrics.controlHeight)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canStartEditing)
            .foregroundStyle(canStartEditing ? .primary : .tertiary)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(canStartEditing ? 0.10 : 0.06), lineWidth: 1)
            }
            .help("Edit Source")
            .accessibilityLabel("Edit source")
        }
    }

    private struct SourceEditingStatusBar: View {
        let hasUnsavedChanges: Bool
        let canSave: Bool
        let canDiscard: Bool
        let onSave: () -> Void
        let onDiscard: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                HStack(spacing: Metrics.editingBannerTextSpacing) {
                    Image(systemName: hasUnsavedChanges ? "pencil.and.list.clipboard" : "pencil")
                        .font(.system(size: Metrics.editingBannerIconSize, weight: .semibold))

                    Text(hasUnsavedChanges ? "Editing source with unsaved changes" : "Editing source")
                        .font(.system(size: Metrics.editingBannerLabelSize, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.black.opacity(0.82))

                Spacer(minLength: 0)

                statusActionButton(
                    title: "Save",
                    systemImage: "square.and.arrow.down",
                    isEnabled: canSave,
                    isPrimary: true,
                    action: onSave
                )
                .accessibilityLabel("Save source changes")

                statusActionButton(
                    title: "Exit without saving",
                    systemImage: "xmark",
                    isEnabled: canDiscard,
                    isPrimary: false,
                    action: onDiscard
                )
                .accessibilityLabel(hasUnsavedChanges ? "Exit source editing and discard source changes" : "Exit source editing")
            }
            .padding(.horizontal, Metrics.barHorizontalPadding)
            .padding(.vertical, Metrics.editingBannerVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Rectangle()
                    .fill(editingBannerBackground)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black.opacity(0.14))
                    .frame(height: 1)
            }
            .help(hasUnsavedChanges ? "Editing Source With Unsaved Changes" : "Editing Source")
        }

        private func statusActionButton(
            title: String,
            systemImage: String,
            isEnabled: Bool,
            isPrimary: Bool,
            action: @escaping () -> Void
        ) -> some View {
            Button {
                action()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: Metrics.editingBannerButtonIconSize, weight: .semibold))

                    Text(title)
                        .font(.system(size: Metrics.editingBannerLabelSize, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 10)
                .frame(height: Metrics.editingBannerButtonHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .foregroundStyle(statusActionForegroundStyle(isEnabled: isEnabled, isPrimary: isPrimary))
            .background(buttonBackground(isEnabled: isEnabled, isPrimary: isPrimary), in: RoundedRectangle(cornerRadius: Metrics.editingBannerCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.editingBannerCornerRadius, style: .continuous)
                    .strokeBorder(buttonBorder(isEnabled: isEnabled, isPrimary: isPrimary), lineWidth: 1)
            }
        }

        private func statusActionForegroundStyle(isEnabled: Bool, isPrimary: Bool) -> AnyShapeStyle {
            if !isEnabled {
                return AnyShapeStyle(Color.black.opacity(0.55))
            }

            return AnyShapeStyle(isPrimary ? Color.white : Color.black.opacity(0.82))
        }

        private func buttonBackground(isEnabled: Bool, isPrimary: Bool) -> some ShapeStyle {
            if !isEnabled {
                return Color.black.opacity(isPrimary ? 0.18 : 0.08)
            }

            if isPrimary {
                return Color.black.opacity(0.88)
            }

            return Color.white.opacity(0.58)
        }

        private func buttonBorder(isEnabled: Bool, isPrimary: Bool) -> Color {
            if !isEnabled {
                return Color.black.opacity(isPrimary ? 0.18 : 0.12)
            }

            return isPrimary ? Color.black.opacity(0.24) : Color.black.opacity(0.14)
        }

        private var editingBannerBackground: some ShapeStyle {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.92, blue: 0.58),
                    Color(red: 0.94, green: 0.79, blue: 0.29)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private struct DocumentViewModeSwitch: View {
        let hasFile: Bool
        let documentViewMode: ReaderDocumentViewMode
        let onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void

        var body: some View {
            HStack(spacing: 2) {
                ForEach(ReaderDocumentViewMode.allCases, id: \.self) { mode in
                    modeButton(mode: mode)
                }
            }
            .padding(2)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.thinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Document view mode")
            .accessibilityHint("Switch between rendered preview, split view, and markdown source")
        }

        private func modeButton(mode: ReaderDocumentViewMode) -> some View {
            let isSelected = documentViewMode == mode

            return Button {
                onSetDocumentViewMode(mode)
            } label: {
                Text(mode.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .frame(height: Metrics.controlHeight)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor.opacity(0.28) : .clear,
                                lineWidth: 1
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!hasFile || isSelected)
            .foregroundStyle(hasFile ? (isSelected ? .primary : .secondary) : .tertiary)
            .help(mode.displayName)
            .accessibilityLabel(mode.displayName)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
        }
    }

    private func appIconImage(for app: ReaderExternalApplication) -> NSImage? {
        let iconPath: String
        if let bundleIdentifier = app.bundleIdentifier,
           let installedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            iconPath = installedURL.path
        } else {
            iconPath = app.bundleURL.path
        }

        guard FileManager.default.fileExists(atPath: iconPath) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: "App")
        }

        let icon = NSWorkspace.shared.icon(forFile: iconPath)
        icon.size = NSSize(width: 16, height: 16)
        icon.isTemplate = false
        return icon
    }
}

struct FolderWatchDetailsPopover: View {
    let activeFolderWatch: ReaderFolderWatchSession
    var isCurrentWatchAFavorite: Bool = false
    var onSaveFolderWatchAsFavorite: ((String) -> Void)?

    @State private var isShowingSaveSheet = false
    @State private var favoriteName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Watching folder")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    Text(activeFolderWatch.detailSummaryTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if onSaveFolderWatchAsFavorite != nil {
                    favoriteStarButton
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Path")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(activeFolderWatch.detailPathText)
                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(activeFolderWatch.detailRows, id: \.title) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)

                        Text(row.value)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !activeFolderWatch.excludedSubdirectoryRelativePaths.isEmpty {
                ExcludedSubdirectoriesSection(
                    relativePaths: activeFolderWatch.excludedSubdirectoryRelativePaths
                )
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .sheet(isPresented: $isShowingSaveSheet) {
            SaveFavoriteSheet(
                name: $favoriteName,
                onSave: { name in
                    onSaveFolderWatchAsFavorite?(name)
                    isShowingSaveSheet = false
                },
                onCancel: {
                    isShowingSaveSheet = false
                }
            )
        }
    }

    @ViewBuilder
    private var favoriteStarButton: some View {
        if isCurrentWatchAFavorite {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.yellow)
                .help("This watch configuration is saved as a favorite")
                .accessibilityLabel("Favorite saved")
        } else {
            Button {
                favoriteName = activeFolderWatch.detailSummaryTitle
                isShowingSaveSheet = true
            } label: {
                Image(systemName: "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Save as favorite")
            .accessibilityLabel("Save as favorite")
        }
    }
}

struct SaveFavoriteSheet: View {
    @Binding var name: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Save as Favorite")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onSave(name.trimmingCharacters(in: .whitespaces))
                }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(name.trimmingCharacters(in: .whitespaces))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}

private struct ExcludedSubdirectoriesSection: View {
    let relativePaths: [String]

    private static let collapsedLimit = 10

    @State private var isExpanded = false

    private var visiblePaths: [String] {
        if isExpanded || relativePaths.count <= Self.collapsedLimit {
            return relativePaths
        }
        return Array(relativePaths.prefix(Self.collapsedLimit))
    }

    private var hasMore: Bool {
        !isExpanded && relativePaths.count > Self.collapsedLimit
    }

    var body: some View {
        Divider()

        DisclosureGroup("Filtered subdirectories", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(visiblePaths, id: \.self) { path in
                    Text(path)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if hasMore {
                    Button("and \(relativePaths.count - Self.collapsedLimit) more...") {
                        isExpanded = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tint)
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}

private struct OpenInMenuButton: NSViewRepresentable {
    let hasFile: Bool
    let hasActiveFolderWatch: Bool
    let apps: [ReaderExternalApplication]
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let iconProvider: (ReaderExternalApplication) -> NSImage?
    let onOpenFile: (URL) -> Void
    let onOpenApp: (ReaderExternalApplication) -> Void
    let onRevealInFinder: () -> Void
    let onRequestFolderWatch: (URL) -> Void
    let onStopFolderWatch: () -> Void
    let onStartFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
    let onClearFavoriteWatchedFolders: () -> Void
    let onEditFavoriteWatchedFolders: () -> Void
    let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onClearRecentManuallyOpenedFiles: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More actions")
        button.contentTintColor = .labelColor
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
        button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        button.layer?.masksToBounds = true
        button.setAccessibilityLabel("Open in and watch actions")
        button.toolTip = "Open a file, choose an app, reveal in Finder, or manage folder watch"
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.appByID = apps.reduce(into: [:]) { result, app in
            result[app.id] = app
        }
        button.alphaValue = hasFile ? 1 : 0.9
        button.layer?.backgroundColor = hasFile
            ? NSColor.labelColor.withAlphaComponent(0.09).cgColor
            : NSColor.labelColor.withAlphaComponent(0.06).cgColor
        button.layer?.borderColor = NSColor.labelColor.withAlphaComponent(hasFile ? 0.14 : 0.10).cgColor
    }

    final class Coordinator: NSObject {
        var parent: OpenInMenuButton
        var appByID: [String: ReaderExternalApplication] = [:]
        weak var button: NSButton?

        init(parent: OpenInMenuButton) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()

            let openFile = NSMenuItem(title: "Open File...", action: #selector(openFileFromPicker), keyEquivalent: "")
            openFile.target = self
            menu.addItem(openFile)

            menu.addItem(makeRecentFilesMenuItem())

            menu.addItem(.separator())

            let heading = NSMenuItem(title: "Open in:", action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            menu.addItem(.separator())

            if parent.hasFile {
                if parent.apps.isEmpty {
                    let empty = NSMenuItem(title: "No compatible apps found", action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                    menu.addItem(empty)
                } else {
                    for app in parent.apps {
                        let item = NSMenuItem(title: app.displayName, action: #selector(openApp(_:)), keyEquivalent: "")
                        item.target = self
                        item.representedObject = app.id
                        if let icon = parent.iconProvider(app) {
                            icon.size = NSSize(width: 16, height: 16)
                            icon.isTemplate = false
                            item.image = icon
                        }
                        menu.addItem(item)
                    }
                }

                menu.addItem(.separator())

                let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
                reveal.target = self
                menu.addItem(reveal)
            } else {
                let noFile = NSMenuItem(title: "No file selected", action: nil, keyEquivalent: "")
                noFile.isEnabled = false
                menu.addItem(noFile)
                menu.addItem(.separator())

                let reveal = NSMenuItem(title: "Reveal in Finder", action: nil, keyEquivalent: "")
                reveal.isEnabled = false
                menu.addItem(reveal)
            }

            menu.addItem(.separator())

            let watchFolder = NSMenuItem(title: "Watch Folder...", action: #selector(watchFolderFromPicker), keyEquivalent: "")
            watchFolder.target = self
            menu.addItem(watchFolder)

            menu.addItem(makeFavoriteWatchedFoldersMenuItem())

            menu.addItem(makeRecentWatchedFoldersMenuItem())

            let stopWatching = NSMenuItem(title: "Stop Watching Folder", action: #selector(stopWatchingFolder), keyEquivalent: "")
            stopWatching.target = self
            stopWatching.isEnabled = parent.hasActiveFolderWatch
            if !parent.hasActiveFolderWatch {
                stopWatching.action = nil
                stopWatching.target = nil
            }
            menu.addItem(stopWatching)

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: sender)
        }

        private func makeRecentFilesMenuItem() -> NSMenuItem {
            let item = NSMenuItem(title: "Recent Opened Files", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)
            let titlesByPath = ReaderRecentHistory.menuTitles(for: parent.recentManuallyOpenedFiles)

            if parent.recentManuallyOpenedFiles.isEmpty {
                let empty = NSMenuItem(title: "No recent manually opened files", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                for entry in parent.recentManuallyOpenedFiles {
                    let recentItem = NSMenuItem(
                        title: titlesByPath[entry.filePath] ?? entry.displayName,
                        action: #selector(openRecentFile(_:)),
                        keyEquivalent: ""
                    )
                    recentItem.target = self
                    recentItem.representedObject = entry.filePath
                    recentItem.toolTip = entry.pathText
                    submenu.addItem(recentItem)
                }

                submenu.addItem(.separator())
            }

            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearRecentFiles), keyEquivalent: "")
            clearItem.target = self
            clearItem.isEnabled = !parent.recentManuallyOpenedFiles.isEmpty
            submenu.addItem(clearItem)

            item.submenu = submenu
            return item
        }

        private func makeFavoriteWatchedFoldersMenuItem() -> NSMenuItem {
            let item = NSMenuItem(title: "Favorite Watched Folders", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)

            if parent.favoriteWatchedFolders.isEmpty {
                let empty = NSMenuItem(title: "No favorite watched folders", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                for entry in parent.favoriteWatchedFolders {
                    let favoriteItem = NSMenuItem(
                        title: entry.name,
                        action: #selector(startFavoriteWatch(_:)),
                        keyEquivalent: ""
                    )
                    favoriteItem.target = self
                    favoriteItem.representedObject = entry.id.uuidString
                    favoriteItem.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorite")
                    favoriteItem.image?.isTemplate = true
                    favoriteItem.toolTip = [
                        entry.pathText,
                        "When watch starts: \(entry.options.openMode.label)",
                        "Scope: \(entry.options.scope.label)"
                    ].joined(separator: "\n")
                    submenu.addItem(favoriteItem)
                }

                submenu.addItem(.separator())
            }

            let editItem = NSMenuItem(title: "Edit Favorites\u{2026}", action: #selector(editFavoriteWatchedFolders), keyEquivalent: "")
            editItem.target = self
            editItem.isEnabled = !parent.favoriteWatchedFolders.isEmpty
            submenu.addItem(editItem)

            let clearItem = NSMenuItem(title: "Clear Favorites", action: #selector(clearFavoriteWatchedFolders), keyEquivalent: "")
            clearItem.target = self
            clearItem.isEnabled = !parent.favoriteWatchedFolders.isEmpty
            submenu.addItem(clearItem)

            item.submenu = submenu
            return item
        }

        private func makeRecentWatchedFoldersMenuItem() -> NSMenuItem {
            let item = NSMenuItem(title: "Recent Watched Folders", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)
            let titlesByPath = ReaderRecentHistory.menuTitles(for: parent.recentWatchedFolders)

            if parent.recentWatchedFolders.isEmpty {
                let empty = NSMenuItem(title: "No recent watched folders", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                for entry in parent.recentWatchedFolders {
                    let recentItem = NSMenuItem(
                        title: titlesByPath[entry.folderPath] ?? entry.displayName,
                        action: #selector(startRecentFolderWatch(_:)),
                        keyEquivalent: ""
                    )
                    recentItem.target = self
                    recentItem.representedObject = entry.folderPath
                    recentItem.toolTip = [
                        entry.pathText,
                        "When watch starts: \(entry.options.openMode.label)",
                        "Scope: \(entry.options.scope.label)"
                    ].joined(separator: "\n")
                    submenu.addItem(recentItem)
                }

                submenu.addItem(.separator())
            }

            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearRecentWatchedFolders), keyEquivalent: "")
            clearItem.target = self
            clearItem.isEnabled = !parent.recentWatchedFolders.isEmpty
            submenu.addItem(clearItem)

            item.submenu = submenu
            return item
        }

        @objc private func openApp(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let app = appByID[id] else {
                return
            }
            parent.onOpenApp(app)
        }

        @objc private func openFileFromPicker() {
            guard let fileURL = MarkdownOpenPanel.pickFiles(allowsMultipleSelection: false)?.first else {
                return
            }

            parent.onOpenFile(fileURL)
        }

        @objc private func openRecentFile(_ sender: NSMenuItem) {
            guard let filePath = sender.representedObject as? String,
                  let entry = parent.recentManuallyOpenedFiles.first(where: { $0.filePath == filePath }) else {
                return
            }

            parent.onStartRecentManuallyOpenedFile(entry)
        }

        @objc private func revealInFinder() {
            parent.onRevealInFinder()
        }

        @objc private func watchFolderFromPicker() {
            guard let folderURL = pickFolder() else {
                return
            }
            parent.onRequestFolderWatch(folderURL)
        }

        @objc private func startRecentFolderWatch(_ sender: NSMenuItem) {
            guard let folderPath = sender.representedObject as? String,
                  let entry = parent.recentWatchedFolders.first(where: { $0.folderPath == folderPath }) else {
                return
            }

            parent.onStartRecentFolderWatch(entry)
        }

        @objc private func stopWatchingFolder() {
            parent.onStopFolderWatch()
        }

        @objc private func clearRecentFiles() {
            parent.onClearRecentManuallyOpenedFiles()
        }

        @objc private func startFavoriteWatch(_ sender: NSMenuItem) {
            guard let idString = sender.representedObject as? String,
                  let id = UUID(uuidString: idString),
                  let entry = parent.favoriteWatchedFolders.first(where: { $0.id == id }) else {
                return
            }

            parent.onStartFavoriteWatch(entry)
        }

        @objc private func editFavoriteWatchedFolders() {
            parent.onEditFavoriteWatchedFolders()
        }

        @objc private func clearFavoriteWatchedFolders() {
            parent.onClearFavoriteWatchedFolders()
        }

        @objc private func clearRecentWatchedFolders() {
            parent.onClearRecentWatchedFolders()
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
}