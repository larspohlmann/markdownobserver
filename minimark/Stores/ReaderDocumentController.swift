import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ReaderDocumentController {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ReaderDocumentController"
    )

    // MARK: - Identity state
    var fileURL: URL?
    var fileDisplayName: String = ""
    var documentLoadState: ReaderDocumentLoadState = .ready
    var isCurrentFileMissing: Bool = false
    var lastError: PresentableError?
    var openInApplications: [ExternalApplication] = []
    var currentOpenOrigin: OpenOrigin = .manual

    // MARK: - Content state
    var sourceMarkdown: String = ""
    var savedMarkdown: String = ""
    var fileLastModifiedAt: Date?
    var changedRegions: [ChangedRegion] = []

    // MARK: - Computed
    var hasOpenDocument: Bool { fileURL != nil }
    var isDeferredDocument: Bool { documentLoadState == .deferred }
    var windowTitle: String {
        fileDisplayName.isEmpty
            ? WindowTitleFormatter.appName
            : "\(fileDisplayName) - \(WindowTitleFormatter.appName)"
    }

    // MARK: - Dependencies
    let fileDependencies: FileDependencies
    let settingsStore: ReaderSettingsReading
    let settler: ReaderAutoOpenSettling

    @ObservationIgnored private var loadingOverlayHoldGeneration: UInt = 0

    init(
        fileDependencies: FileDependencies,
        settingsStore: ReaderSettingsReading,
        settler: ReaderAutoOpenSettling
    ) {
        self.fileDependencies = fileDependencies
        self.settingsStore = settingsStore
        self.settler = settler
    }

    // MARK: - Presentation

    func presentLoadedState(
        markdown: String,
        modificationDate: Date,
        at fileURL: URL,
        changedRegions: [ChangedRegion]
    ) {
        self.fileURL = fileURL
        self.fileDisplayName = fileURL.lastPathComponent
        self.savedMarkdown = markdown
        self.sourceMarkdown = markdown
        self.fileLastModifiedAt = modificationDate
        self.changedRegions = changedRegions
        self.isCurrentFileMissing = false
        self.lastError = nil
    }

    func presentMissingDocument(at fileURL: URL, error: Error) {
        self.fileURL = fileURL
        self.fileDisplayName = fileURL.lastPathComponent
        self.fileLastModifiedAt = nil
        self.openInApplications = []
        self.isCurrentFileMissing = true
        self.lastError = PresentableError(from: error)
        settler.clearSettling()
    }

    func clearOpenDocument() {
        fileDependencies.watcher.stopWatching()
        fileURL = nil
        fileDisplayName = ""
        documentLoadState = .ready
        isCurrentFileMissing = false
        lastError = nil
        openInApplications = []
        currentOpenOrigin = .manual
        sourceMarkdown = ""
        savedMarkdown = ""
        fileLastModifiedAt = nil
        changedRegions = []
        settler.clearSettling()
    }

    func deferFile(
        at url: URL,
        origin: OpenOrigin = .folderWatchInitialBatchAutoOpen
    ) {
        let normalizedURL = FileRouting.normalizedFileURL(url)
        fileURL = normalizedURL
        fileDisplayName = normalizedURL.lastPathComponent
        documentLoadState = .deferred
        currentOpenOrigin = origin
        lastError = nil
        isCurrentFileMissing = false
        let modificationDate = fileDependencies.io.modificationDate(for: normalizedURL)
        fileLastModifiedAt = modificationDate == .distantPast ? nil : modificationDate
    }

    // MARK: - Load state transitions

    func transitionToLoading() {
        guard documentLoadState == .deferred || documentLoadState == .ready else { return }
        documentLoadState = .loading
    }

    func clearLoadingState() {
        guard documentLoadState == .loading else { return }
        documentLoadState = .ready
    }

    func holdLoadingOverlayBriefly() {
        guard documentLoadState == .ready else { return }
        transitionToLoading()
        loadingOverlayHoldGeneration &+= 1
        let generation = loadingOverlayHoldGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.loadingOverlayHoldGeneration == generation else { return }
            self.clearLoadingState()
        }
    }

    // MARK: - File actions

    func refreshOpenInApplications() {
        guard let fileURL else {
            openInApplications = []
            return
        }
        do {
            openInApplications = try fileDependencies.actions.registeredApplications(for: fileURL)
        } catch {
            openInApplications = []
            handle(error)
        }
    }

    func openInApplication(_ application: ExternalApplication?) {
        guard let fileURL else {
            handle(AppError.noOpenFileInReader)
            return
        }
        do {
            try fileDependencies.actions.open(fileURL: fileURL, in: application)
            lastError = nil
        } catch {
            handle(error)
        }
    }

    func revealInFinder() {
        guard let fileURL else {
            handle(AppError.noOpenFileInReader)
            return
        }
        do {
            try fileDependencies.actions.revealInFinder(fileURL: fileURL)
            lastError = nil
        } catch {
            handle(error)
        }
    }

    func stopWatching() {
        fileDependencies.watcher.stopWatching()
    }

    // MARK: - Error handling

    func handle(_ error: Error) {
        lastError = PresentableError(from: error)
    }

    func clearLastError() {
        lastError = nil
    }

    // MARK: - Test Helpers

    #if DEBUG
    func testSetFileURL(_ url: URL?) { fileURL = url }
    func testSetFileDisplayName(_ name: String) { fileDisplayName = name }
    func testSetFileLastModifiedAt(_ date: Date?) { fileLastModifiedAt = date }
    func testSetIsCurrentFileMissing(_ value: Bool) { isCurrentFileMissing = value }
    #endif
}
