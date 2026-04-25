import AppKit
import Foundation

/// Presents an NSOpenPanel asking the user to authorize MarkdownObserver to
/// read files in a folder so that markdown link clicks can follow into
/// sibling and descendant files. The chosen folder is persisted as a
/// security-scoped bookmark via `LinkAccessGrantWriting` so subsequent link
/// clicks under the same folder don't re-prompt.
@MainActor
final class LinkFollowAccessRequester {
    private let grantStore: LinkAccessGrantWriting
    private let pickFolder: @MainActor (URL?, String, String, String) -> URL?

    init(
        grantStore: LinkAccessGrantWriting,
        pickFolder: @escaping @MainActor (URL?, String, String, String) -> URL? = { directoryURL, title, message, prompt in
            MarkdownOpenPanel.pickFolder(
                directoryURL: directoryURL,
                title: title,
                message: message,
                prompt: prompt
            )
        }
    ) {
        self.grantStore = grantStore
        self.pickFolder = pickFolder
    }

    /// Presents an NSOpenPanel pre-pointed at `targetFileURL.deletingLastPathComponent()`
    /// and, if the user picks a folder that contains the target file, persists the
    /// selection as a link-access grant.
    ///
    /// Returns `true` if a grant covering the target file was successfully recorded.
    @discardableResult
    func requestAccess(forContaining targetFileURL: URL) -> Bool {
        let parentFolderURL = targetFileURL.deletingLastPathComponent()
        let fileName = targetFileURL.lastPathComponent

        guard let chosenFolderURL = pickFolder(
            parentFolderURL,
            "Allow Link Following",
            "MarkdownObserver needs access to this folder to open “\(fileName)” and related markdown files reached via links.",
            "Grant Access"
        ) else {
            return false
        }

        guard folderContains(chosenFolderURL, file: targetFileURL) else {
            return false
        }

        grantStore.addLinkAccessGrant(chosenFolderURL)
        return true
    }

    private func folderContains(_ folderURL: URL, file fileURL: URL) -> Bool {
        let folderPath = FileRouting.normalizedFileURL(folderURL).path
        let filePath = FileRouting.normalizedFileURL(fileURL).path
        let folderPathWithSeparator = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return filePath.hasPrefix(folderPathWithSeparator)
    }
}
