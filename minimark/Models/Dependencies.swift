import Foundation

struct RenderingDependencies {
    let renderer: MarkdownRendering
    let differ: ChangedRegionDiffering
}

struct FileDependencies {
    let watcher: FileChangeWatching
    let io: DocumentIO
    let actions: FileActionHandling
}

struct FolderWatchDependencies {
    let autoOpenPlanner: FolderWatchAutoOpenPlanning
    let settler: AutoOpenSettling
    let systemNotifier: SystemNotifying
}
