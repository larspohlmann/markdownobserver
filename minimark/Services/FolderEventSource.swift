import Foundation

protocol FolderEventSource: AnyObject, Sendable {
    func start(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher,
        queue: DispatchQueue,
        onEvent: @escaping @Sendable (_ changedDirectoryURLs: Set<URL>?) -> Void
    )

    func stop()
}

enum FolderEventSourceFactory {
    static func makeEventSource(includeSubfolders: Bool) -> any FolderEventSource {
        if includeSubfolders {
            return FSEventStreamFolderEventSource()
        } else {
            return DispatchSourceFolderEventSource()
        }
    }
}
