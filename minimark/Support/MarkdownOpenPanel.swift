import AppKit
import Foundation
import UniformTypeIdentifiers

enum MarkdownOpenPanel {
    private static let markdownExtensions = ["md", "markdown", "mdown"]

    static func pickFiles(
        allowsMultipleSelection: Bool,
        directoryURL: URL? = nil,
        title: String = "Open Markdown",
        message: String? = nil,
        prompt: String = "Open"
    ) -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedMarkdownContentTypes()
        panel.allowsOtherFileTypes = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = directoryURL
        panel.title = title
        panel.message = message ?? ""
        panel.prompt = prompt

        let response = panel.runModal()
        guard response == .OK else {
            return nil
        }

        let markdownURLs = panel.urls.filter { url in
            ReaderFileRouting.isSupportedMarkdownFileURL(url)
        }

        return markdownURLs.isEmpty ? nil : markdownURLs
    }

    private static func allowedMarkdownContentTypes() -> [UTType] {
        markdownExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func pickFolder(
        directoryURL: URL? = nil,
        title: String = "Choose Folder",
        message: String? = nil,
        prompt: String = "Choose Folder"
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = directoryURL
        panel.title = title
        panel.message = message ?? ""
        panel.prompt = prompt

        let response = panel.runModal()
        guard response == .OK else {
            return nil
        }

        return panel.urls.first
    }
}
