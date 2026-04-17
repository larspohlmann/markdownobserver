import Foundation
import OSLog

struct FolderChangeWatcherFailure: Equatable, Sendable {
    enum Stage: String, Equatable, Sendable {
        case startupSnapshot
        case verificationSnapshot
        case watchedDirectoryEnumeration
    }

    let stage: Stage
    let folderIdentifier: String
    let errorDescription: String
}

struct FolderChangeFailureReporter: Sendable {
    typealias FailureHandler = @Sendable (FolderChangeWatcherFailure) -> Void

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "FolderChangeWatcher"
    )

    let onFailure: FailureHandler?
    private var lastReportedFailureByStage: [FolderChangeWatcherFailure.Stage: String] = [:]

    init(onFailure: FailureHandler? = nil) {
        self.onFailure = onFailure
    }

    mutating func report(
        stage: FolderChangeWatcherFailure.Stage,
        folderURL: URL,
        error: any Error
    ) {
        let errorDescription = Self.sanitizedErrorDescription(for: error)
        let failure = FolderChangeWatcherFailure(
            stage: stage,
            folderIdentifier: Self.sanitizedFolderIdentifier(for: folderURL),
            errorDescription: errorDescription
        )

        let signature = Self.stableErrorKey(for: error)
        guard lastReportedFailureByStage[stage] != signature else {
            return
        }
        lastReportedFailureByStage[stage] = signature

        Self.logger.error(
            "folder watch failure stage=\(stage.rawValue, privacy: .public) folder=\(folderURL.path, privacy: .private(mask: .hash)) error=\(errorDescription, privacy: .private(mask: .hash))"
        )

        let onFailure = self.onFailure
        DispatchQueue.main.async {
            onFailure?(failure)
        }
    }

    mutating func clearReportedFailure(for stage: FolderChangeWatcherFailure.Stage) {
        lastReportedFailureByStage.removeValue(forKey: stage)
    }

    mutating func resetAllReportedFailures() {
        lastReportedFailureByStage.removeAll()
    }

    private static func sanitizedFolderIdentifier(for folderURL: URL) -> String {
        let normalizedPath = FileRouting.normalizedFileURL(folderURL).path
        return String(normalizedPath.hashValue, radix: 16)
    }

    private static func sanitizedErrorDescription(for error: any Error) -> String {
        let nsError = error as NSError
        return "domain: \(nsError.domain), code: \(nsError.code)"
    }

    private static func stableErrorKey(for error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }
}
