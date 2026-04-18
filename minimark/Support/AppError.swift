import Foundation

enum AppError: LocalizedError {
    case invalidFileURL
    case noOpenFileInReader
    case fileNotReachable(URL)
    case fileReadFailed(URL, underlying: Error)
    case fileWriteFailed(URL, underlying: Error)
    case renderingFailed(underlying: Error)
    case markdownRuntimeUnavailable(String)
    case unsavedDraftRequiresResolution
    case applicationNotRegisteredForFile(fileURL: URL, applicationURL: URL)
    case noRegisteredApplications(URL)
    case openInDefaultApplicationFailed(URL)

    var errorDescription: String? {
        switch self {
        case .invalidFileURL:
            return "The selected file URL is invalid."
        case .noOpenFileInReader:
            return "No file is currently open."
        case let .fileNotReachable(url):
            return "The file is not reachable: \(url.path)"
        case let .fileReadFailed(url, underlying):
            return "Failed to read file at \(url.path): \(underlying.localizedDescription)"
        case let .fileWriteFailed(url, underlying):
            return "Failed to write file at \(url.path): \(underlying.localizedDescription)"
        case let .renderingFailed(underlying):
            return "Failed to render markdown: \(underlying.localizedDescription)"
        case let .markdownRuntimeUnavailable(path):
            return "The markdown rendering runtime is unavailable at \(path)."
        case .unsavedDraftRequiresResolution:
            return "Save or discard the current source draft before replacing the open document."
        case let .applicationNotRegisteredForFile(fileURL, applicationURL):
            return "The app at \(applicationURL.path) cannot open \(fileURL.lastPathComponent)."
        case let .noRegisteredApplications(url):
            return "No compatible apps were found to open \(url.lastPathComponent)."
        case let .openInDefaultApplicationFailed(url):
            return "Failed to open \(url.lastPathComponent) in the default app."
        }
    }
}
