import Foundation

struct ReaderPresentableError: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case fileRead
        case fileWrite
        case fileMissing
        case rendering
        case application
        case general
    }

    let kind: Kind
    let message: String

    init(from error: Error) {
        self.message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let readerError = error as? ReaderError {
            switch readerError {
            case .fileReadFailed:
                self.kind = .fileRead
            case .fileNotReachable:
                self.kind = .fileMissing
            case .fileWriteFailed:
                self.kind = .fileWrite
            case .renderingFailed, .markdownRuntimeUnavailable:
                self.kind = .rendering
            case .applicationNotRegisteredForFile, .noRegisteredApplications, .openInDefaultApplicationFailed:
                self.kind = .application
            case .invalidFileURL, .noOpenFileInReader, .unsavedDraftRequiresResolution:
                self.kind = .general
            }
        } else {
            self.kind = .general
        }
    }
}
