import AppKit
import SwiftUI

struct ContentUtilityRail: View {
    let hasFile: Bool
    let documentViewMode: ReaderDocumentViewMode
    let showEditButton: Bool
    let canStartSourceEditing: Bool
    let canStopFolderWatch: Bool
    let apps: [ReaderExternalApplication]
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let iconProvider: (ReaderExternalApplication) -> NSImage?
    let onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void
    let onOpenFiles: ([URL]) -> Void
    let onOpenApp: (ReaderExternalApplication) -> Void
    let onRevealInFinder: () -> Void
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

    @State private var isEditingFavorites = false
    @State private var isHovering = false

    private enum Metrics {
        static let railWidth: CGFloat = 44
        static let buttonSize: CGFloat = 32
        static let buttonCornerRadius: CGFloat = 8
        static let iconSize: CGFloat = 12
        static let groupSpacing: CGFloat = 8
        static let railCornerRadius: CGFloat = 12
        static let railInset: CGFloat = 8
        static let railTrailingInset: CGFloat = 18
        static let separatorWidth: CGFloat = 20
    }

    var body: some View {
        VStack(spacing: Metrics.groupSpacing) {
            if hasFile {
                viewModeGroup

                if showEditButton {
                    groupSeparator
                    editGroup
                }

                groupSeparator
            }

            actionsGroup
        }
        .padding(.vertical, Metrics.groupSpacing)
        .frame(width: Metrics.railWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Metrics.railCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.railCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.16 : 0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isHovering ? 0.25 : 0.12), radius: isHovering ? 16 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                isHovering = hovering
            }
        }
        .padding(.top, Metrics.railInset)
        .padding(.trailing, Metrics.railTrailingInset)
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
        .accessibilityHint("Switch between preview, split, and source views of the document.")
    }

    private func viewModeButton(mode: ReaderDocumentViewMode) -> some View {
        let isSelected = documentViewMode == mode

        return Button {
            onSetDocumentViewMode(mode)
        } label: {
            Image(systemName: mode.systemImageName)
                .font(.system(size: Metrics.iconSize, weight: isSelected ? .bold : .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .railButtonBackground(cornerRadius: Metrics.buttonCornerRadius,
                    fill: isSelected ? Color.primary.opacity(0.12) : Color.clear,
                    border: isSelected ? Color.primary.opacity(0.18) : Color.clear
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasFile || isSelected)
        .foregroundStyle(isSelected ? .primary : (hasFile ? .secondary : .tertiary))
        .help(mode.displayName)
        .accessibilityLabel(mode.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    // MARK: - Edit Group

    private var editGroup: some View {
        Button {
            onStartSourceEditing()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: Metrics.iconSize, weight: .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .railButtonBackground(cornerRadius: Metrics.buttonCornerRadius,
                    fill: Color.primary.opacity(canStartSourceEditing ? 0.06 : 0.03),
                    border: Color.primary.opacity(canStartSourceEditing ? 0.10 : 0.05)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canStartSourceEditing)
        .foregroundStyle(canStartSourceEditing ? .primary : .tertiary)
        .help("Edit Source")
        .accessibilityLabel("Edit source")
    }

    // MARK: - Actions Group

    private var actionsGroup: some View {
        OpenInMenuButton(
            hasFile: hasFile,
            hasActiveFolderWatch: canStopFolderWatch,
            apps: apps,
            favoriteWatchedFolders: favoriteWatchedFolders,
            recentWatchedFolders: recentWatchedFolders,
            recentManuallyOpenedFiles: recentManuallyOpenedFiles,
            iconProvider: iconProvider,
            onOpenFiles: onOpenFiles,
            onOpenApp: onOpenApp,
            onRevealInFinder: onRevealInFinder,
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

// MARK: - Rail Button Background

private struct RailButtonBackgroundModifier: ViewModifier {
    let fill: Color
    let border: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private extension View {
    func railButtonBackground(cornerRadius: CGFloat, fill: Color, border: Color) -> some View {
        modifier(RailButtonBackgroundModifier(fill: fill, border: border, cornerRadius: cornerRadius))
    }
}
