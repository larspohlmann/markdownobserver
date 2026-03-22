import Foundation

enum ReaderSettingsGuidance {
    static func layoutHelpText(selectedMode: ReaderMultiFileDisplayMode) -> String {
        switch selectedMode {
        case .sidebarLeft, .sidebarRight:
            return "Sidebar placement changes immediately."
        }
    }

    static func markdownAssociationErrorMessage(for error: MarkdownAssociationError) -> String {
        switch error {
        case let .launchServicesFailed(failures) where failures.contains(where: { $0.status == -54 }):
            return "macOS didn’t allow this change. In Finder, select a .md file, choose Get Info, set Open with to MarkdownObserver, then choose Change All."
        default:
            return error.errorDescription ?? "The default app could not be updated."
        }
    }
}