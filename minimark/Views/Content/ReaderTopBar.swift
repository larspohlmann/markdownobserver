import AppKit
import SwiftUI

struct PointingHandCursor: ViewModifier {
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
    static let sourceEditingBarHeight: CGFloat = 22
}

struct ReaderTopBar: View {
    var readerStore: ReaderStore
    let canStopFolderWatch: Bool
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
    let onRenameFavoriteWatchedFolder: (UUID, String) -> Void
    let onRemoveFavoriteWatchedFolder: (UUID) -> Void
    let onReorderFavoriteWatchedFolders: ([UUID]) -> Void
    let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onClearRecentManuallyOpenedFiles: () -> Void
    let onSaveSourceDraft: () -> Void
    let onDiscardSourceDraft: () -> Void

    private enum Metrics {
        static let barHorizontalPadding: CGFloat = 12
        static let mainBarHeight: CGFloat = ReaderTopBarMetrics.mainBarHeight
    }

    @State private var isEditingFavorites = false

    var body: some View {
        let projection = ReaderTopBarStoreProjection(store: readerStore)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                BreadcrumbDocumentContext(
                    projection: projection,
                    onRevealInFinder: onRevealInFinder
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                OpenInMenuButton(
                    hasFile: readerStore.fileURL != nil,
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
                .frame(width: 28, height: 28)
            }
            .padding(.horizontal, Metrics.barHorizontalPadding)
            .frame(height: Metrics.mainBarHeight)

            if projection.isSourceEditing {
                SourceEditingStatusBar(
                    hasUnsavedChanges: projection.hasUnsavedDraftChanges,
                    canSave: projection.canSaveSourceDraft,
                    canDiscard: projection.canDiscardSourceDraft,
                    onSave: onSaveSourceDraft,
                    onDiscard: onDiscardSourceDraft
                )
            }
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
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

}
