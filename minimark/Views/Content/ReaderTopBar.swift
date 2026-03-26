import AppKit
import SwiftUI

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
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let onNavigateChangedRegion: (ReaderChangedRegionNavigationDirection) -> Void
    let onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void
    let onOpenFile: (URL) -> Void
    let onRequestFolderWatch: (URL) -> Void
    let onStopFolderWatch: () -> Void
    let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onClearRecentManuallyOpenedFiles: () -> Void
    let onStartSourceEditing: () -> Void
    let onSaveSourceDraft: () -> Void
    let onDiscardSourceDraft: () -> Void

    private enum Metrics {
        static let barHorizontalPadding: CGFloat = 12
        static let barVerticalPadding: CGFloat = 8
        static let editingBannerVerticalPadding: CGFloat = 3
        static let editingBannerTextSpacing: CGFloat = 6
        static let editingBannerLabelSize: CGFloat = 10
        static let editingBannerIconSize: CGFloat = 8
        static let editingBannerButtonIconSize: CGFloat = 8
        static let editingBannerButtonHeight: CGFloat = 16
        static let sectionSpacing: CGFloat = 12
        static let controlGroupSpacing: CGFloat = 8
        static let chipHorizontalPadding: CGFloat = 10
        static let chipVerticalPadding: CGFloat = 5
        static let chipInnerSpacing: CGFloat = 8
        static let chipStopButtonSide: CGFloat = 18
        static let chipDetailIconSide: CGFloat = 12
        static let topBarMenuButtonSide: CGFloat = 24
        static let changeNavigationButtonSide: CGFloat = 24
        static let documentModeButtonWidth: CGFloat = 28
        static let splitDocumentModeButtonWidth: CGFloat = 32
        static let documentModeControlHeight: CGFloat = 28
        static let editingBannerCornerRadius: CGFloat = 8
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Metrics.sectionSpacing) {
                HStack(spacing: Metrics.controlGroupSpacing) {
                    FolderWatchToolbarButton(
                        activeFolderWatch: activeFolderWatch,
                        isInitialScanInProgress: isFolderWatchInitialScanInProgress,
                        didInitialScanFail: didFolderWatchInitialScanFail,
                        highlightColor: folderWatchHighlightColor,
                        onActivate: handleFolderWatchToolbarButton
                    )

                    if canNavigateChangedRegions {
                        ChangeNavigationControls(
                            canNavigate: canNavigateChangedRegions,
                            onNavigateChangedRegion: onNavigateChangedRegion
                        )
                    }
                }
                .layoutPriority(4)

                DocumentContext(readerStore: readerStore)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(0)

                TrailingActions(
                    readerStore: readerStore,
                    hasFile: readerStore.fileURL != nil,
                    hasActiveFolderWatch: canStopFolderWatch,
                    documentViewMode: documentViewMode,
                    showSourceEditingControls: showSourceEditingControls,
                    apps: readerStore.openInApplications,
                    recentWatchedFolders: recentWatchedFolders,
                    recentManuallyOpenedFiles: recentManuallyOpenedFiles,
                    iconProvider: appIconImage(for:),
                    onStartSourceEditing: onStartSourceEditing,
                    onSaveSourceDraft: onSaveSourceDraft,
                    onDiscardSourceDraft: onDiscardSourceDraft,
                    onSetDocumentViewMode: onSetDocumentViewMode,
                    onOpenFile: onOpenFile,
                    onOpenApp: { app in
                        readerStore.openCurrentFileInApplication(app)
                    },
                    onRevealInFinder: {
                        readerStore.revealCurrentFileInFinder()
                    },
                    onRequestFolderWatch: onRequestFolderWatch,
                    onStopFolderWatch: onStopFolderWatch,
                    onStartRecentManuallyOpenedFile: onStartRecentManuallyOpenedFile,
                    onStartRecentFolderWatch: onStartRecentFolderWatch,
                    onClearRecentWatchedFolders: onClearRecentWatchedFolders,
                    onClearRecentManuallyOpenedFiles: onClearRecentManuallyOpenedFiles
                )
                .layoutPriority(3)
            }
            .padding(.horizontal, Metrics.barHorizontalPadding)
            .padding(.vertical, Metrics.barVerticalPadding)

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
    }

    private func handleFolderWatchToolbarButton() {
        if canStopFolderWatch {
            onStopFolderWatch()
            return
        }

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
        let highlightColor: Color
        let onActivate: () -> Void

        private var isActive: Bool {
            activeFolderWatch != nil
        }

        private var statusText: String {
            if isInitialScanInProgress {
                return "Scanning folder tree..."
            }
            if didInitialScanFail {
                return "Initial scan failed"
            }
            return activeFolderWatch?.statusLabel ?? "Not watching"
        }

        private var helpText: String {
            activeFolderWatch?.tooltipText ?? "Watch Folder..."
        }

        private var buttonTitle: String {
            isActive ? "Stop Watching" : "Watch Folder..."
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    onActivate()
                } label: {
                    Label {
                        Text(buttonTitle)
                    } icon: {
                        Image(systemName: "binoculars.fill")
                            .foregroundStyle(isActive ? .yellow : .secondary)
                    }
                    .labelStyle(.titleAndIcon)
                }
                .controlSize(.small)
                .tint(isActive ? highlightColor : nil)
                .help(isActive ? "Stop Watching Folder" : "Watch Folder...")
                .accessibilityIdentifier("folder-watch-toolbar-button")
                .accessibilityLabel("Watch folder")
                .accessibilityValue(isActive ? "Active" : "Inactive")
                .accessibilityHint(isActive ? "Stops monitoring the current folder" : "Opens the folder picker for starting folder watch")

                Text(statusText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isActive ? highlightColor.opacity(0.9) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 280, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(helpText)
                    .accessibilityHidden(true)

                if isInitialScanInProgress {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 140)
                        .controlSize(.small)
                        .tint(highlightColor)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
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
                        width: Metrics.changeNavigationButtonSide,
                        height: Metrics.changeNavigationButtonSide
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

    private struct DocumentContext: View {
        @ObservedObject var readerStore: ReaderStore

        private var titleText: String {
            if readerStore.fileDisplayName.isEmpty {
                return "No document open"
            }

            return readerStore.fileDisplayName
        }

        var body: some View {
            VStack(spacing: 2) {
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(readerStore.fileURL?.path ?? titleText)
                    .accessibilityLabel("Current document")
                    .accessibilityValue(titleText)

                RefreshStatusText(
                    statusTimestamp: readerStore.statusBarTimestamp,
                    hasFile: readerStore.fileURL != nil,
                    isCurrentFileMissing: readerStore.isCurrentFileMissing
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private struct RefreshStatusText: View {
        let statusTimestamp: ReaderStatusBarTimestamp?
        let hasFile: Bool
        let isCurrentFileMissing: Bool

        var body: some View {
            TimelineView(.periodic(from: .now, by: 20)) { context in
                Text(refreshText(relativeTo: context.date))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(accessibilityValue(relativeTo: context.date))
            }
        }

        private func refreshText(relativeTo now: Date) -> String {
            if let availabilityMessage = availabilityMessage(noFileMessage: "Open a Markdown file to start reading") {
                return availabilityMessage
            }

            guard let statusTimestamp else {
                return "Ready"
            }

            return text(for: statusTimestamp, relativeTo: now)
        }

        private func accessibilityValue(relativeTo now: Date) -> String {
            if let availabilityMessage = availabilityMessage(noFileMessage: "No document open") {
                return availabilityMessage
            }

            guard let statusTimestamp else {
                return "Ready"
            }

            return relativeText(for: statusTimestamp, relativeTo: now)
        }

        private var accessibilityLabel: String {
            switch statusTimestamp {
            case .updated:
                return "Content refreshed"
            case .lastModified:
                return "Last modified"
            case nil:
                return "Content status"
            }
        }

        private func text(for timestamp: ReaderStatusBarTimestamp, relativeTo now: Date) -> String {
            switch timestamp {
            case .updated:
                return "Updated \(relativeText(for: timestamp, relativeTo: now))"
            case .lastModified:
                return "Last modified \(relativeText(for: timestamp, relativeTo: now))"
            }
        }

        private func relativeText(for timestamp: ReaderStatusBarTimestamp, relativeTo now: Date) -> String {
            switch timestamp {
            case let .updated(date), let .lastModified(date):
                return ReaderStatusFormatting.relativeText(for: date, relativeTo: now)
            }
        }

        private func availabilityMessage(noFileMessage: String) -> String? {
            if !hasFile {
                return noFileMessage
            }

            if isCurrentFileMissing {
                return "File deleted externally"
            }

            return nil
        }
    }

    fileprivate struct LastExternalChangeText: View {
        let changedAt: Date

        var body: some View {
            TimelineView(.periodic(from: .now, by: 20)) { context in
                Text("Last changed: \(ReaderStatusFormatting.relativeText(for: changedAt, relativeTo: context.date))")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityLabel("Last external change")
                    .accessibilityValue(ReaderStatusFormatting.relativeText(for: changedAt, relativeTo: context.date))
            }
        }
    }

    fileprivate struct FolderWatchStatusChip: View {
        let activeFolderWatch: ReaderFolderWatchSession
        let canStopFolderWatch: Bool
        let onStopFolderWatch: () -> Void

        @State private var isShowingDetails = false

        var body: some View {
            HStack(spacing: Metrics.chipInnerSpacing) {
                Button {
                    isShowingDetails = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(.system(size: 11, weight: .semibold))

                        Text(activeFolderWatch.chipLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)

                        Image(systemName: "info.circle")
                            .font(.system(size: Metrics.chipDetailIconSide, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
                    FolderWatchDetailsPopover(activeFolderWatch: activeFolderWatch)
                }
                .help(activeFolderWatch.tooltipText)
                .accessibilityLabel("Folder watch details")
                .accessibilityValue(activeFolderWatch.accessibilityValue)
                .accessibilityHint("Shows details about the watched folder")

                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 1, height: 14)

                Button {
                    onStopFolderWatch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: Metrics.chipStopButtonSide, height: Metrics.chipStopButtonSide)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canStopFolderWatch)
                .foregroundStyle(canStopFolderWatch ? .secondary : .tertiary)
                .accessibilityLabel("Stop watching folder")
                .accessibilityHint("Stops monitoring the current folder")
            }
            .padding(.leading, Metrics.chipHorizontalPadding)
            .padding(.trailing, Metrics.chipHorizontalPadding - 1)
            .padding(.vertical, Metrics.chipVerticalPadding)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.13), lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityElement(children: .contain)
        }
    }

    private struct TrailingActions: View {
        @ObservedObject var readerStore: ReaderStore
        let hasFile: Bool
        let hasActiveFolderWatch: Bool
        let documentViewMode: ReaderDocumentViewMode
        let showSourceEditingControls: Bool
        let apps: [ReaderExternalApplication]
        let recentWatchedFolders: [ReaderRecentWatchedFolder]
        let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
        let iconProvider: (ReaderExternalApplication) -> NSImage?
        let onStartSourceEditing: () -> Void
        let onSaveSourceDraft: () -> Void
        let onDiscardSourceDraft: () -> Void
        let onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void
        let onOpenFile: (URL) -> Void
        let onOpenApp: (ReaderExternalApplication) -> Void
        let onRevealInFinder: () -> Void
        let onRequestFolderWatch: (URL) -> Void
        let onStopFolderWatch: () -> Void
        let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
        let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
        let onClearRecentWatchedFolders: () -> Void
        let onClearRecentManuallyOpenedFiles: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                if showSourceEditingControls && !readerStore.isSourceEditing {
                    SourceEditingControls(
                        canStartEditing: readerStore.canStartSourceEditing,
                        onStartEditing: onStartSourceEditing
                    )
                }

                DocumentViewModeSwitch(
                    hasFile: hasFile,
                    documentViewMode: documentViewMode,
                    onSetDocumentViewMode: onSetDocumentViewMode
                )

                OpenInMenuButton(
                    hasFile: hasFile,
                    hasActiveFolderWatch: hasActiveFolderWatch,
                    apps: apps,
                    recentWatchedFolders: recentWatchedFolders,
                    recentManuallyOpenedFiles: recentManuallyOpenedFiles,
                    iconProvider: iconProvider,
                    onOpenFile: onOpenFile,
                    onOpenApp: onOpenApp,
                    onRevealInFinder: onRevealInFinder,
                    onRequestFolderWatch: onRequestFolderWatch,
                    onStopFolderWatch: onStopFolderWatch,
                    onStartRecentManuallyOpenedFile: onStartRecentManuallyOpenedFile,
                    onStartRecentFolderWatch: onStartRecentFolderWatch,
                    onClearRecentWatchedFolders: onClearRecentWatchedFolders,
                    onClearRecentManuallyOpenedFiles: onClearRecentManuallyOpenedFiles
                )
                .accessibilityLabel("Open in and watch actions")
                .accessibilityHint("Open a file, choose an app, reveal in Finder, or manage folder watch")
                .frame(width: Metrics.topBarMenuButtonSide, height: Metrics.topBarMenuButtonSide)
                .fixedSize()
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
                .frame(height: Metrics.documentModeControlHeight)
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
                modeButton(
                    mode: .preview,
                    symbolName: "doc.richtext"
                )

                modeButton(
                    mode: .split,
                    symbolName: "rectangle.split.2x1",
                    width: Metrics.splitDocumentModeButtonWidth
                )

                modeButton(
                    mode: .source,
                    symbolName: "text.alignleft"
                )
            }
            .padding(2)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Document view mode")
            .accessibilityHint("Switch between rendered preview, split view, and markdown source")
        }

        private func modeButton(
            mode: ReaderDocumentViewMode,
            symbolName: String,
            width: CGFloat = Metrics.documentModeButtonWidth
        ) -> some View {
            let isSelected = documentViewMode == mode

            return Button {
                onSetDocumentViewMode(mode)
            } label: {
                Image(systemName: symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(
                        width: width,
                        height: Metrics.documentModeControlHeight
                    )
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
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }
}

private struct OpenInMenuButton: NSViewRepresentable {
    let hasFile: Bool
    let hasActiveFolderWatch: Bool
    let apps: [ReaderExternalApplication]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let iconProvider: (ReaderExternalApplication) -> NSImage?
    let onOpenFile: (URL) -> Void
    let onOpenApp: (ReaderExternalApplication) -> Void
    let onRevealInFinder: () -> Void
    let onRequestFolderWatch: (URL) -> Void
    let onStopFolderWatch: () -> Void
    let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onClearRecentManuallyOpenedFiles: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Open in")
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