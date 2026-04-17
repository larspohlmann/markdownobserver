import AppKit
import Foundation

protocol ReaderFileActionHandling {
    func registeredApplications(for fileURL: URL) throws -> [ExternalApplication]
    func open(fileURL: URL, in application: ExternalApplication?) throws
    func revealInFinder(fileURL: URL) throws
}

final class ReaderFileActionService: ReaderFileActionHandling {
    private let workspace: WorkspaceControlling

    init(workspace: WorkspaceControlling = NSWorkspace.shared) {
        self.workspace = workspace
    }

    func registeredApplications(for fileURL: URL) throws -> [ExternalApplication] {
        try validateReachableFileURL(fileURL)

        return uniquedApplications(
            from: workspace.urlsForApplications(toOpen: fileURL)
                .compactMap(mapApplication(bundleURL:))
        )
            .sorted { lhs, rhs in
                let displayNameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if displayNameOrder != .orderedSame {
                    return displayNameOrder == .orderedAscending
                }

                return lhs.bundleURL.path.localizedCaseInsensitiveCompare(rhs.bundleURL.path) == .orderedAscending
            }
    }

    private func uniquedApplications(from applications: [ExternalApplication]) -> [ExternalApplication] {
        var seenIdentifiers = Set<String>()

        return applications.filter { application in
            seenIdentifiers.insert(application.bundleIdentifier ?? application.bundleURL.path).inserted
        }
    }

    func open(fileURL: URL, in application: ExternalApplication?) throws {
        try validateReachableFileURL(fileURL)

        if let application {
            guard workspace.urlsForApplications(toOpen: fileURL).contains(application.bundleURL) else {
                throw ReaderError.applicationNotRegisteredForFile(fileURL: fileURL, applicationURL: application.bundleURL)
            }

            workspace.open([fileURL], withApplicationAt: application.bundleURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        let didOpen = workspace.open(fileURL)
        if !didOpen {
            throw ReaderError.openInDefaultApplicationFailed(fileURL)
        }
    }

    func revealInFinder(fileURL: URL) throws {
        try validateReachableFileURL(fileURL)
        workspace.activateFileViewerSelecting([fileURL])
    }

    private func validateReachableFileURL(_ fileURL: URL) throws {
        guard fileURL.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            throw ReaderError.fileNotReachable(fileURL)
        }
    }

    private func mapApplication(bundleURL: URL) -> ExternalApplication? {
        guard let bundle = Bundle(url: bundleURL) else {
            return nil
        }

        let bundleIdentifier = bundle.bundleIdentifier
        let displayName =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            bundleURL.deletingPathExtension().lastPathComponent

        let identifier = bundleIdentifier ?? bundleURL.path

        return ExternalApplication(
            id: identifier,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL
        )
    }
}

protocol WorkspaceControlling {
    func urlsForApplications(toOpen url: URL) -> [URL]
    func open(_ url: URL) -> Bool
    func open(_ urls: [URL], withApplicationAt applicationURL: URL, configuration: NSWorkspace.OpenConfiguration)
    func activateFileViewerSelecting(_ fileURLs: [URL])
}

extension NSWorkspace: WorkspaceControlling {
    func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) {
        open(urls, withApplicationAt: applicationURL, configuration: configuration, completionHandler: nil)
    }
}
