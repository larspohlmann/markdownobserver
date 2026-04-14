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

enum ReaderTopBarAction {
    case openFiles([URL])
    case openInApp(ReaderExternalApplication)
    case revealInFinder
    case requestFolderWatch(URL)
    case stopFolderWatch
    case startFavoriteWatch(ReaderFavoriteWatchedFolder)
    case clearFavoriteWatchedFolders
    case renameFavoriteWatchedFolder(id: UUID, name: String)
    case removeFavoriteWatchedFolder(UUID)
    case reorderFavoriteWatchedFolders([UUID])
    case startRecentManuallyOpenedFile(ReaderRecentOpenedFile)
    case startRecentFolderWatch(ReaderRecentWatchedFolder)
    case clearRecentWatchedFolders
    case clearRecentManuallyOpenedFiles
    case saveSourceDraft
    case discardSourceDraft
}

struct ReaderTopBar: View {
    var readerStore: ReaderStore
    let canStopFolderWatch: Bool
    let apps: [ReaderExternalApplication]
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let iconProvider: (ReaderExternalApplication) -> NSImage?
    let onAction: (ReaderTopBarAction) -> Void

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
                    onRevealInFinder: { onAction(.revealInFinder) }
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
                    onAction: { action in
                        switch action {
                        case .editFavoriteWatchedFolders:
                            isEditingFavorites = true
                        case .openFiles(let urls):
                            onAction(.openFiles(urls))
                        case .openInApp(let app):
                            onAction(.openInApp(app))
                        case .revealInFinder:
                            onAction(.revealInFinder)
                        case .requestFolderWatch(let url):
                            onAction(.requestFolderWatch(url))
                        case .stopFolderWatch:
                            onAction(.stopFolderWatch)
                        case .startFavoriteWatch(let fav):
                            onAction(.startFavoriteWatch(fav))
                        case .clearFavoriteWatchedFolders:
                            onAction(.clearFavoriteWatchedFolders)
                        case .startRecentManuallyOpenedFile(let entry):
                            onAction(.startRecentManuallyOpenedFile(entry))
                        case .startRecentFolderWatch(let entry):
                            onAction(.startRecentFolderWatch(entry))
                        case .clearRecentWatchedFolders:
                            onAction(.clearRecentWatchedFolders)
                        case .clearRecentManuallyOpenedFiles:
                            onAction(.clearRecentManuallyOpenedFiles)
                        }
                    }
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
                    onSave: { onAction(.saveSourceDraft) },
                    onDiscard: { onAction(.discardSourceDraft) }
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
                onAction: { action in
                    switch action {
                    case .rename(let id, let name):
                        onAction(.renameFavoriteWatchedFolder(id: id, name: name))
                    case .delete(let id):
                        onAction(.removeFavoriteWatchedFolder(id))
                    case .reorder(let ids):
                        onAction(.reorderFavoriteWatchedFolders(ids))
                    case .dismiss:
                        isEditingFavorites = false
                    }
                }
            )
        }
    }

}
