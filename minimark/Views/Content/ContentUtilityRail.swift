import AppKit
import SwiftUI

struct ContentUtilityRail: View {
    @ObservedObject var readerStore: ReaderStore
    let documentViewMode: ReaderDocumentViewMode
    let showSourceEditingControls: Bool
    let canNavigateChangedRegions: Bool
    let canStopFolderWatch: Bool
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let onNavigateChangedRegion: (ReaderChangedRegionNavigationDirection) -> Void
    let onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void
    let onOpenFiles: ([URL]) -> Void
    let onRequestFolderWatch: (URL) -> Void
    let onStopFolderWatch: () -> Void
    let onStartFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
    let onClearFavoriteWatchedFolders: () -> Void
    let onRenameFavoriteWatchedFolder: (UUID, String) -> Void
    let onRemoveFavoriteWatchedFolder: (UUID) -> Void
    let onReorderFavoriteWatchedFolders: ([UUID]) -> Void
    let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onClearRecentManuallyOpenedFiles: () -> Void
    let onStartSourceEditing: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isEditingFavorites = false
    @State private var isHovering = false

    private enum Metrics {
        static let railWidth: CGFloat = 44
        static let buttonSize: CGFloat = 32
        static let buttonCornerRadius: CGFloat = 8
        static let iconSize: CGFloat = 12
        static let groupSpacing: CGFloat = 8
        static let separatorHorizontalPadding: CGFloat = 8
        static let railCornerRadius: CGFloat = 12
        static let railInset: CGFloat = 8
        static let separatorWidth: CGFloat = 20
    }

    private var activePurple: Color {
        colorScheme == .dark
            ? Color(red: 0.59, green: 0.49, blue: 1.0)
            : Color(red: 0.34, green: 0.24, blue: 0.71)
    }

    private var hasFile: Bool {
        readerStore.fileURL != nil
    }

    private var showChangeNavigation: Bool {
        canNavigateChangedRegions
    }

    private var showEditButton: Bool {
        showSourceEditingControls && !readerStore.isSourceEditing
    }

    var body: some View {
        VStack(spacing: Metrics.groupSpacing) {
            viewModeGroup

            if showChangeNavigation {
                groupSeparator
                changeNavigationGroup
            }

            if showEditButton {
                groupSeparator
                editGroup
            }

            groupSeparator
            actionsGroup
        }
        .padding(.vertical, Metrics.groupSpacing)
        .frame(width: Metrics.railWidth)
        .background {
            RoundedRectangle(cornerRadius: Metrics.railCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isHovering ? 1.0 : 0.6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.railCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.14 : 0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.railCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(isHovering ? 0.20 : 0.10), radius: isHovering ? 12 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                isHovering = hovering
            }
        }
        .padding(Metrics.railInset)
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

    // MARK: - View Mode Group

    private var viewModeGroup: some View {
        VStack(spacing: 4) {
            ForEach(ReaderDocumentViewMode.allCases, id: \.self) { mode in
                viewModeButton(mode: mode)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document view mode")
    }

    private func viewModeButton(mode: ReaderDocumentViewMode) -> some View {
        let isSelected = documentViewMode == mode

        return Button {
            onSetDocumentViewMode(mode)
        } label: {
            Image(systemName: mode.systemImageName)
                .font(.system(size: Metrics.iconSize, weight: .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                        .fill(isSelected ? activePurple.opacity(0.18) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                        .strokeBorder(isSelected ? activePurple.opacity(0.28) : Color.clear, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!hasFile || isSelected)
        .foregroundStyle(isSelected ? AnyShapeStyle(activePurple) : (hasFile ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)))
        .help(mode.displayName)
        .accessibilityLabel(mode.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    // MARK: - Change Navigation Group

    private var changeNavigationGroup: some View {
        VStack(spacing: 4) {
            changeNavigationButton(
                symbolName: "arrow.up",
                label: "Previous change",
                direction: .previous
            )
            changeNavigationButton(
                symbolName: "arrow.down",
                label: "Next change",
                direction: .next
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func changeNavigationButton(
        symbolName: String,
        label: String,
        direction: ReaderChangedRegionNavigationDirection
    ) -> some View {
        Button {
            onNavigateChangedRegion(direction)
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: Metrics.iconSize, weight: .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint("Jumps to a changed region in the current preview")
    }

    // MARK: - Edit Group

    private var editGroup: some View {
        Button {
            onStartSourceEditing()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: Metrics.iconSize, weight: .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(readerStore.canStartSourceEditing ? 0.06 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(readerStore.canStartSourceEditing ? 0.10 : 0.05), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!readerStore.canStartSourceEditing)
        .foregroundStyle(readerStore.canStartSourceEditing ? .primary : .tertiary)
        .help("Edit Source")
        .accessibilityLabel("Edit source")
    }

    // MARK: - Actions Group

    private var actionsGroup: some View {
        OpenInMenuButton(
            hasFile: hasFile,
            hasActiveFolderWatch: canStopFolderWatch,
            apps: readerStore.openInApplications,
            favoriteWatchedFolders: favoriteWatchedFolders,
            recentWatchedFolders: recentWatchedFolders,
            recentManuallyOpenedFiles: recentManuallyOpenedFiles,
            iconProvider: appIconImage(for:),
            onOpenFiles: onOpenFiles,
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
        .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
        .help("Actions")
    }

    // MARK: - Separator

    private var groupSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: Metrics.separatorWidth, height: 1)
            .padding(.vertical, 2)
    }
}
