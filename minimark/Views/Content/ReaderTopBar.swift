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
    case openInApp(ExternalApplication)
    case revealInFinder
    case requestFolderWatch(URL)
    case stopFolderWatch
    case startFavoriteWatch(FavoriteWatchedFolder)
    case clearFavoriteWatchedFolders
    case renameFavoriteWatchedFolder(id: UUID, name: String)
    case removeFavoriteWatchedFolder(UUID)
    case reorderFavoriteWatchedFolders([UUID])
    case startRecentManuallyOpenedFile(RecentOpenedFile)
    case startRecentFolderWatch(RecentWatchedFolder)
    case clearRecentWatchedFolders
    case clearRecentManuallyOpenedFiles
    case saveSourceDraft
    case discardSourceDraft

    init?(_ menuAction: OpenInMenuAction) {
        switch menuAction {
        case .openFiles(let urls): self = .openFiles(urls)
        case .openInApp(let app): self = .openInApp(app)
        case .revealInFinder: self = .revealInFinder
        case .requestFolderWatch(let url): self = .requestFolderWatch(url)
        case .stopFolderWatch: self = .stopFolderWatch
        case .startFavoriteWatch(let fav): self = .startFavoriteWatch(fav)
        case .clearFavoriteWatchedFolders: self = .clearFavoriteWatchedFolders
        case .startRecentManuallyOpenedFile(let entry): self = .startRecentManuallyOpenedFile(entry)
        case .startRecentFolderWatch(let entry): self = .startRecentFolderWatch(entry)
        case .clearRecentWatchedFolders: self = .clearRecentWatchedFolders
        case .clearRecentManuallyOpenedFiles: self = .clearRecentManuallyOpenedFiles
        case .editFavoriteWatchedFolders: return nil
        }
    }
}

struct ReaderTopBar: View {
    let document: ReaderDocumentController
    let sourceEditing: ReaderSourceEditingController
    let statusBarTimestamp: ReaderStatusBarTimestamp?
    let canStopFolderWatch: Bool
    let apps: [ExternalApplication]
    let favoriteWatchedFolders: [FavoriteWatchedFolder]
    let recentWatchedFolders: [RecentWatchedFolder]
    let recentManuallyOpenedFiles: [RecentOpenedFile]
    let iconProvider: (ExternalApplication) -> NSImage?
    let onAction: (ReaderTopBarAction) -> Void

    private enum Metrics {
        static let barHorizontalPadding: CGFloat = 12
        static let mainBarHeight: CGFloat = ReaderTopBarMetrics.mainBarHeight
    }

    @State private var isEditingFavorites = false

    var body: some View {
        let projection = ReaderTopBarStoreProjection(
            document: document,
            sourceEditing: sourceEditing,
            statusBarTimestamp: statusBarTimestamp
        )

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                BreadcrumbDocumentContext(
                    projection: projection,
                    onRevealInFinder: { onAction(.revealInFinder) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                OpenInMenuButton(
                    hasFile: document.fileURL != nil,
                    hasActiveFolderWatch: canStopFolderWatch,
                    apps: apps,
                    favoriteWatchedFolders: favoriteWatchedFolders,
                    recentWatchedFolders: recentWatchedFolders,
                    recentManuallyOpenedFiles: recentManuallyOpenedFiles,
                    iconProvider: iconProvider,
                    onAction: { menuAction in
                        if let topBarAction = ReaderTopBarAction(menuAction) {
                            onAction(topBarAction)
                        } else {
                            isEditingFavorites = true
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
        .task(id: document.fileURL) {
            document.refreshOpenInApplications()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            document.refreshOpenInApplications()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            document.refreshOpenInApplications()
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
