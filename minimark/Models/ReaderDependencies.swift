import Foundation

struct ReaderRenderingDependencies {
    let renderer: MarkdownRendering
    let differ: ChangedRegionDiffering
}

struct ReaderFileDependencies {
    let watcher: FileChangeWatching
    let io: ReaderDocumentIO
    let actions: ReaderFileActionHandling
}

struct ReaderFolderWatchDependencies {
    let autoOpenPlanner: ReaderFolderWatchAutoOpenPlanning
    let settler: ReaderAutoOpenSettling
    let systemNotifier: ReaderSystemNotifying
}
