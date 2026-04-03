import AppKit
import SwiftUI

private struct PointingHandCursor: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, !isHovering {
                    NSCursor.pointingHand.push()
                    isHovering = true
                } else if !hovering, isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

enum ReaderTopBarMetrics {
    static let mainBarHeight: CGFloat = 44
}

struct ReaderTopBar: View {
    @ObservedObject var readerStore: ReaderStore
    let activeFolderWatch: ReaderFolderWatchSession?
    let isFolderWatchInitialScanInProgress: Bool
    let didFolderWatchInitialScanFail: Bool
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let onRequestFolderWatch: (URL) -> Void
    let onStartFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
    let onRenameFavoriteWatchedFolder: (UUID, String) -> Void
    let onRemoveFavoriteWatchedFolder: (UUID) -> Void
    let onReorderFavoriteWatchedFolders: ([UUID]) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onSaveSourceDraft: () -> Void
    let onDiscardSourceDraft: () -> Void

    private enum Metrics {
        static let barHorizontalPadding: CGFloat = 12
        static let mainBarHeight: CGFloat = ReaderTopBarMetrics.mainBarHeight
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
    }

    @State private var isEditingFavorites = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                FolderWatchToolbarButton(
                    activeFolderWatch: activeFolderWatch,
                    isInitialScanInProgress: isFolderWatchInitialScanInProgress,
                    didInitialScanFail: didFolderWatchInitialScanFail,
                    favoriteWatchedFolders: favoriteWatchedFolders,
                    recentWatchedFolders: recentWatchedFolders,
                    onActivate: handleFolderWatchToolbarButton,
                    onStartFavoriteWatch: onStartFavoriteWatch,
                    onStartRecentFolderWatch: onStartRecentFolderWatch,
                    onEditFavoriteWatchedFolders: { isEditingFavorites = true },
                    onClearRecentWatchedFolders: onClearRecentWatchedFolders
                )

                Spacer().frame(width: Metrics.watchButtonToDocSpacing)

                BreadcrumbDocumentContext(
                    readerStore: readerStore,
                    onRevealInFinder: { readerStore.revealCurrentFileInFinder() }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Metrics.barHorizontalPadding)
            .frame(height: Metrics.mainBarHeight)

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
                onReorder: onReorderFavoriteWatchedFolders,
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
        let isInitialScanInProgress: Bool
        let didInitialScanFail: Bool
        let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
        let recentWatchedFolders: [ReaderRecentWatchedFolder]
        let onActivate: () -> Void
        let onStartFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
        let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
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
            .overlay(alignment: .topTrailing) {
                Group {
                    if isInitialScanInProgress {
                        ProgressView()
                            .scaleEffect(0.6)
                            .controlSize(.small)
                    } else if didInitialScanFail {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
                .offset(x: -4, y: 4)
                .allowsHitTesting(false)
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
                    .accessibilityIdentifier("edit-favorites-button")
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
            .foregroundStyle(Color(nsColor: .labelColor))
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
            let abbreviated = abbreviatePathWithTilde(url.deletingLastPathComponent().path)
            let components = abbreviated
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            let joined = components.joined(separator: " \u{203A} ")
            if abbreviated.hasPrefix("/") {
                return joined.isEmpty ? "/" : "/ \u{203A} " + joined
            }
            return joined
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
                            isCurrentFileMissing: readerStore.isCurrentFileMissing
                        )
                    }
                }
                .buttonStyle(.plain)
                .modifier(PointingHandCursor())
                .help("Reveal in Finder")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Current document")
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

}

@MainActor
func appIconImage(for app: ReaderExternalApplication) -> NSImage? {
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

    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Save as Favorite")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)

                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                        .offset(x: 3, y: 2)
                }
                .frame(width: 28, height: 24)

                TextField("Favorite name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($isNameFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor.opacity(isNameFocused ? 0.4 : 0), lineWidth: 1)
                    )
                    .onSubmit {
                        guard !trimmedName.isEmpty else { return }
                        onSave(trimmedName)
                    }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(trimmedName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 340)
        .onAppear { isNameFocused = true }
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

struct OpenInMenuButton: NSViewRepresentable {
    let hasFile: Bool
    let hasActiveFolderWatch: Bool
    let apps: [ReaderExternalApplication]
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let iconProvider: (ReaderExternalApplication) -> NSImage?
    let onOpenFiles: ([URL]) -> Void
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

            let openFile = NSMenuItem(title: "Open File(s)...", action: #selector(openFileFromPicker), keyEquivalent: "")
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
            guard let fileURLs = MarkdownOpenPanel.pickFiles(allowsMultipleSelection: true) else {
                return
            }

            parent.onOpenFiles(fileURLs)
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