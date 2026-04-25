//
//  TestDoubles.swift
//  minimarkTests
//

import AppKit
import Combine
import Foundation
import UserNotifications
@testable import minimark

final class TestMarkdownRenderer: MarkdownRendering {
    func render(
        markdown: String,
        changedRegions: [ChangedRegion],
        unsavedChangedRegions: [ChangedRegion],
        theme: ThemeDefinition,
        syntaxTheme: SyntaxThemeKind,
        baseFontSize: Double,
        readerThemeOverride: ThemeOverride?
    ) throws -> RenderedMarkdown {
        RenderedMarkdown(
            htmlDocument: "<html><body>\(markdown)</body></html>",
            changedRegions: changedRegions,
            renderedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(20),
    condition: @escaping () -> Bool
) async -> Bool {
    let timeoutNanoseconds = max(UInt64(timeout.components.seconds) * 1_000_000_000 + UInt64(timeout.components.attoseconds / 1_000_000_000), 1)
    let pollNanoseconds = max(UInt64(pollInterval.components.seconds) * 1_000_000_000 + UInt64(pollInterval.components.attoseconds / 1_000_000_000), 1)
    let deadline = ContinuousClock.now + timeout

    while ContinuousClock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: min(pollNanoseconds, timeoutNanoseconds))
    }

    return condition()
}

final class TestChangedRegionDiffer: ChangedRegionDiffering {
    private let changedRegionsForModifiedContent: [ChangedRegion]
    var computeChangedRegionsCalls: [(oldMarkdown: String, newMarkdown: String)] = []

    init(changedRegionsForModifiedContent: [ChangedRegion] = []) {
        self.changedRegionsForModifiedContent = changedRegionsForModifiedContent
    }

    func computeChangedRegions(oldMarkdown: String, newMarkdown: String) -> [ChangedRegion] {
        computeChangedRegionsCalls.append((oldMarkdown: oldMarkdown, newMarkdown: newMarkdown))
        return oldMarkdown == newMarkdown ? [] : changedRegionsForModifiedContent
    }

    func blocks(for markdown: String) -> [MarkdownBlock] {
        []
    }
}

final class TestFileWatcher: FileChangeWatching {
    enum Operation: Equatable {
        case start(URL)
        case stop
    }

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastStartedFileURL: URL?
    private(set) var operations: [Operation] = []
    private var onChange: (@Sendable () -> Void)?

    func startWatching(fileURL: URL, onChange: @escaping @Sendable () -> Void) throws {
        startCallCount += 1
        lastStartedFileURL = FileRouting.normalizedFileURL(fileURL)
        operations.append(.start(FileRouting.normalizedFileURL(fileURL)))
        self.onChange = onChange
    }

    func stopWatching() {
        stopCallCount += 1
        operations.append(.stop)
        onChange = nil
    }

    func emitChange() {
        onChange?()
    }
}

@MainActor
final class TestSettingsStore: SettingsStoring {
    var settingsPublisher: AnyPublisher<Settings, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentSettings: Settings {
        subject.value
    }

    private(set) var recordedFavoriteWatchedFolders: [FavoriteWatchedFolder] = []
    private(set) var recordedRecentWatchedFolders: [RecentWatchedFolder] = []
    private(set) var recordedRecentManuallyOpenedFiles: [RecentOpenedFile] = []

    private let subject: CurrentValueSubject<Settings, Never>

    init(
        autoRefreshOnExternalChange: Bool,
        notificationsEnabled: Bool = true,
        diffBaselineLookback: DiffBaselineLookback = .twoMinutes
    ) {
        subject = CurrentValueSubject(
            Settings(
                appAppearance: .system,
                readerTheme: .blackOnWhite,
                syntaxTheme: .monokai,
                baseFontSize: 15,
                autoRefreshOnExternalChange: autoRefreshOnExternalChange,
                notificationsEnabled: notificationsEnabled,
                multiFileDisplayMode: .sidebarLeft,
                sidebarSortMode: .openOrder,
                sidebarGroupSortMode: .lastChangedNewestFirst,
                recentWatchedFolders: [],
                recentManuallyOpenedFiles: [],
                diffBaselineLookback: diffBaselineLookback
            )
        )
    }

    func updateAppAppearance(_ appearance: AppAppearance) {
        var next = subject.value
        next.appAppearance = appearance
        subject.send(next)
    }

    func updateTheme(_ kind: ThemeKind) {
        var next = subject.value
        next.readerTheme = kind
        subject.send(next)
    }

    func updateReaderThemeOverride(_ override: ThemeOverride?) {
        var next = subject.value
        next.readerThemeOverride = override
        subject.send(next)
    }

    func updateSyntaxTheme(_ kind: SyntaxThemeKind) {
        var next = subject.value
        next.syntaxTheme = kind
        subject.send(next)
    }

    func updateBaseFontSize(_ value: Double) {
        var next = subject.value
        next.baseFontSize = value
        subject.send(next)
    }

    func increaseFontSize(step: Double) {
        updateBaseFontSize(subject.value.baseFontSize + step)
    }

    func decreaseFontSize(step: Double) {
        updateBaseFontSize(subject.value.baseFontSize - step)
    }

    func resetFontSize() {
        updateBaseFontSize(Settings.default.baseFontSize)
    }

    func updateNotificationsEnabled(_ isEnabled: Bool) {
        var next = subject.value
        next.notificationsEnabled = isEnabled
        subject.send(next)
    }

    func updateMultiFileDisplayMode(_ mode: MultiFileDisplayMode) {
        var next = subject.value
        next.multiFileDisplayMode = mode
        subject.send(next)
    }

    func updateSidebarSortMode(_ mode: SidebarSortMode) {
        var next = subject.value
        next.sidebarSortMode = mode
        subject.send(next)
    }

    func updateSidebarGroupSortMode(_ mode: SidebarSortMode) {
        var next = subject.value
        next.sidebarGroupSortMode = mode
        subject.send(next)
    }

    func addFavoriteWatchedFolder(
        name: String,
        folderURL: URL,
        options: FolderWatchOptions,
        openDocumentFileURLs: [URL] = [],
        workspaceState: FavoriteWorkspaceState = .from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: FavoriteWorkspaceState.defaultSidebarWidth
        )
    ) {
        var next = subject.value
        next.favoriteWatchedFolders = FavoriteHistory.insertingUniqueFavorite(
            name: name,
            folderURL: folderURL,
            options: options,
            openDocumentFileURLs: openDocumentFileURLs,
            workspaceState: workspaceState,
            into: next.favoriteWatchedFolders
        )
        recordedFavoriteWatchedFolders = next.favoriteWatchedFolders
        subject.send(next)
    }

    func removeFavoriteWatchedFolder(id: UUID) {
        var next = subject.value
        next.favoriteWatchedFolders = FavoriteHistory.removingFavorite(
            id: id,
            from: next.favoriteWatchedFolders
        )
        recordedFavoriteWatchedFolders = next.favoriteWatchedFolders
        subject.send(next)
    }

    func renameFavoriteWatchedFolder(id: UUID, newName: String) {
        var next = subject.value
        next.favoriteWatchedFolders = FavoriteHistory.renamingFavorite(
            id: id,
            newName: newName,
            in: next.favoriteWatchedFolders
        )
        recordedFavoriteWatchedFolders = next.favoriteWatchedFolders
        subject.send(next)
    }

    func updateFavoriteWatchedFolderOpenDocuments(
        id: UUID,
        folderURL: URL,
        openDocumentFileURLs: [URL]
    ) {
        var next = subject.value
        guard let index = next.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = next.favoriteWatchedFolders[index]
        let scopedRelativePaths = FavoriteWatchedFolder.scopedOpenDocumentRelativePaths(
            from: openDocumentFileURLs,
            relativeTo: folderURL,
            options: existing.options
        )
        let updatedKnownPaths = Array(
            Set(existing.allKnownRelativePaths).union(scopedRelativePaths)
        ).sorted()
        next.favoriteWatchedFolders[index] = FavoriteWatchedFolder(
            id: existing.id,
            name: existing.name,
            folderPath: existing.folderPath,
            options: existing.options,
            bookmarkData: existing.bookmarkData,
            openDocumentRelativePaths: scopedRelativePaths,
            allKnownRelativePaths: updatedKnownPaths,
            workspaceState: existing.workspaceState,
            createdAt: existing.createdAt
        )

        recordedFavoriteWatchedFolders = next.favoriteWatchedFolders
        subject.send(next)
    }

    func updateFavoriteWatchedFolderKnownDocuments(
        id: UUID,
        folderURL: URL,
        knownDocumentFileURLs: [URL]
    ) {
        var next = subject.value
        guard let index = next.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = next.favoriteWatchedFolders[index]
        let scopedRelativePaths = FavoriteWatchedFolder.scopedOpenDocumentRelativePaths(
            from: knownDocumentFileURLs,
            relativeTo: folderURL,
            options: existing.options
        )
        let updatedKnownPaths = Array(
            Set(existing.allKnownRelativePaths).union(scopedRelativePaths)
        ).sorted()
        next.favoriteWatchedFolders[index] = FavoriteWatchedFolder(
            id: existing.id,
            name: existing.name,
            folderPath: existing.folderPath,
            options: existing.options,
            bookmarkData: existing.bookmarkData,
            openDocumentRelativePaths: existing.openDocumentRelativePaths,
            allKnownRelativePaths: updatedKnownPaths,
            workspaceState: existing.workspaceState,
            createdAt: existing.createdAt
        )

        recordedFavoriteWatchedFolders = next.favoriteWatchedFolders
        subject.send(next)
    }

    func resolvedFavoriteWatchedFolderURL(for entry: FavoriteWatchedFolder) -> URL {
        entry.folderURL
    }

    func updateFavoriteWorkspaceState(id: UUID, workspaceState: FavoriteWorkspaceState) {
        var next = subject.value
        guard let index = next.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
            return
        }
        let existing = next.favoriteWatchedFolders[index]
        next.favoriteWatchedFolders[index] = FavoriteWatchedFolder(
            id: existing.id,
            name: existing.name,
            folderPath: existing.folderPath,
            options: existing.options,
            bookmarkData: existing.bookmarkData,
            openDocumentRelativePaths: existing.openDocumentRelativePaths,
            allKnownRelativePaths: existing.allKnownRelativePaths,
            workspaceState: workspaceState,
            createdAt: existing.createdAt
        )
        recordedFavoriteWatchedFolders = next.favoriteWatchedFolders
        subject.send(next)
    }

    func clearFavoriteWatchedFolders() {
        var next = subject.value
        next.favoriteWatchedFolders = []
        recordedFavoriteWatchedFolders = []
        subject.send(next)
    }

    func addRecentWatchedFolder(_ folderURL: URL, options: FolderWatchOptions) {
        var next = subject.value
        next.recentWatchedFolders = RecentHistory.insertingUniqueWatchedFolder(
            folderURL,
            options: options,
            into: next.recentWatchedFolders
        )
        recordedRecentWatchedFolders = next.recentWatchedFolders
        subject.send(next)
    }

    func resolvedRecentWatchedFolderURL(matching folderURL: URL) -> URL? {
        let normalizedFolderURL = FileRouting.normalizedFileURL(folderURL)
        return subject.value.recentWatchedFolders.first(where: { entry in
            FileRouting.normalizedFileURL(entry.folderURL) == normalizedFolderURL
        })?.resolvedFolderURL
    }

    func clearRecentWatchedFolders() {
        var next = subject.value
        next.recentWatchedFolders = []
        recordedRecentWatchedFolders = []
        subject.send(next)
    }

    func addRecentManuallyOpenedFile(_ fileURL: URL) {
        var next = subject.value
        next.recentManuallyOpenedFiles = RecentHistory.insertingUniqueFile(
            fileURL,
            into: next.recentManuallyOpenedFiles
        )
        recordedRecentManuallyOpenedFiles = next.recentManuallyOpenedFiles
        subject.send(next)
    }

    func resolvedRecentManuallyOpenedFileURL(matching fileURL: URL) -> URL? {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)
        return subject.value.recentManuallyOpenedFiles.first(where: { entry in
            FileRouting.normalizedFileURL(entry.fileURL) == normalizedFileURL
        })?.resolvedFileURL
    }

    func clearRecentManuallyOpenedFiles() {
        var next = subject.value
        next.recentManuallyOpenedFiles = []
        recordedRecentManuallyOpenedFiles = []
        subject.send(next)
    }

    private(set) var recordedTrustedImageFolders: [TrustedImageFolder] = []

    func addTrustedImageFolder(_ folderURL: URL) {
        var next = subject.value
        next.trustedImageFolders = TrustedImageFolderHistory.insertingUnique(
            folderURL,
            into: next.trustedImageFolders
        )
        recordedTrustedImageFolders = next.trustedImageFolders
        subject.send(next)
    }

    func updateDiffBaselineLookback(_ lookback: DiffBaselineLookback) {
        var next = subject.value
        next.diffBaselineLookback = lookback
        subject.send(next)
    }

    func isHintDismissed(_ hint: FirstUseHint) -> Bool {
        subject.value.dismissedHints.contains(hint)
    }

    func dismissHint(_ hint: FirstUseHint) {
        var next = subject.value
        next.dismissedHints.insert(hint)
        subject.send(next)
    }

    func resolvedTrustedImageFolderURL(containing fileURL: URL) -> URL? {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)
        let filePath = normalizedFileURL.path

        for entry in subject.value.trustedImageFolders {
            let folderPath = entry.folderPath.hasSuffix("/") ? entry.folderPath : entry.folderPath + "/"
            if filePath.hasPrefix(folderPath) {
                return entry.folderURL
            }
        }

        return nil
    }

    private(set) var recordedLinkAccessGrants: [LinkAccessGrant] = []

    func addLinkAccessGrant(_ folderURL: URL) {
        var next = subject.value
        next.linkAccessGrants = LinkAccessGrantHistory.insertingUnique(
            folderURL,
            bookmarkData: Data(),
            into: next.linkAccessGrants
        )
        recordedLinkAccessGrants = next.linkAccessGrants
        subject.send(next)
    }

    func resolvedLinkAccessFolderURL(containing fileURL: URL) -> URL? {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)
        let filePath = normalizedFileURL.path

        let coveringEntries = subject.value.linkAccessGrants
            .filter { entry in
                let folderPath = entry.folderPath.hasSuffix("/") ? entry.folderPath : entry.folderPath + "/"
                return filePath.hasPrefix(folderPath) || filePath == entry.folderPath
            }
            .sorted { $0.folderPath.count > $1.folderPath.count }

        return coveringEntries.first?.folderURL
    }

    func reorderFavoriteWatchedFolders(orderedIDs: [UUID]) {
        var next = subject.value
        let existing = next.favoriteWatchedFolders
        let ordered = orderedIDs.compactMap { id in
            existing.first(where: { $0.id == id })
        }
        let orderedIDSet = Set(ordered.map(\.id))
        let remaining = existing.filter { !orderedIDSet.contains($0.id) }
        let reordered = ordered + remaining
        next.favoriteWatchedFolders = reordered
        recordedFavoriteWatchedFolders = reordered
        subject.send(next)
    }

    func updateFavoriteWatchedFolderExclusions(id: UUID, excludedSubdirectoryPaths: [String]) {
        var next = subject.value
        guard let index = next.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
            return
        }
        let existing = next.favoriteWatchedFolders[index]
        let folderURL = URL(fileURLWithPath: existing.folderPath, isDirectory: true)
        let normalizedOptions = FolderWatchOptions(
            openMode: existing.options.openMode,
            scope: existing.options.scope,
            excludedSubdirectoryPaths: excludedSubdirectoryPaths
        ).encodedForFolder(folderURL)
        guard existing.options != normalizedOptions else {
            return
        }
        next.favoriteWatchedFolders[index] = FavoriteWatchedFolder(
            id: existing.id,
            name: existing.name,
            folderPath: existing.folderPath,
            options: normalizedOptions,
            bookmarkData: existing.bookmarkData,
            openDocumentRelativePaths: existing.openDocumentRelativePaths,
            allKnownRelativePaths: existing.allKnownRelativePaths,
            workspaceState: existing.workspaceState,
            createdAt: existing.createdAt
        )
        recordedFavoriteWatchedFolders = next.favoriteWatchedFolders
        subject.send(next)
    }
}

final class TestSettingsKeyValueStorage: SettingsKeyValueStoring {
    private var storedValues: [String: Data] = [:]
    private(set) var setCallCount = 0

    func data(forKey defaultName: String) -> Data? {
        storedValues[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        setCallCount += 1
        storedValues[defaultName] = value as? Data
    }
}

final class TestFolderWatcher: FolderChangeWatching, @unchecked Sendable {
    private var onMarkdownFilesAddedOrChanged: (([FolderWatchChangeEvent]) -> Void)?

    var startCallCount = 0
    var stopCallCount = 0
    var lastIncludeSubfolders = false
    var lastExcludedSubdirectoryURLs: [URL] = []
    var markdownFilesToReturn: [URL] = []
    var markdownFilesError: Error?
    var markdownFilesDelay: TimeInterval = 0
    var cachedMarkdownFileURLsToReturn: [URL]?

    var scanProgressStreamToReturn: AsyncStream<FolderChangeWatcher.ScanProgress> = AsyncStream { $0.finish() }
    var scanProgressStream: AsyncStream<FolderChangeWatcher.ScanProgress> {
        scanProgressStreamToReturn
    }

    func startWatching(
        folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL],
        onMarkdownFilesAddedOrChanged: @escaping @Sendable ([FolderWatchChangeEvent]) -> Void
    ) throws {
        startCallCount += 1
        lastIncludeSubfolders = includeSubfolders
        lastExcludedSubdirectoryURLs = excludedSubdirectoryURLs
        self.onMarkdownFilesAddedOrChanged = onMarkdownFilesAddedOrChanged
    }

    func stopWatching() {
        stopCallCount += 1
        onMarkdownFilesAddedOrChanged = nil
    }

    func markdownFiles(
        in folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL]
    ) throws -> [URL] {
        if let markdownFilesError {
            throw markdownFilesError
        }
        if markdownFilesDelay > 0 {
            Thread.sleep(forTimeInterval: markdownFilesDelay)
        }
        lastExcludedSubdirectoryURLs = excludedSubdirectoryURLs
        return markdownFilesToReturn
    }

    func cachedMarkdownFileURLs() -> [URL]? {
        cachedMarkdownFileURLsToReturn
    }

    func emitChangedMarkdownEvents(_ events: [FolderWatchChangeEvent]) {
        onMarkdownFilesAddedOrChanged?(events)
    }
}

final class TestSecurityScopeAccess: SecurityScopedResourceAccessing {
    private(set) var accessedURLs: [URL] = []
    var didStartAccessByPath: [String: Bool] = [:]
    var didStartAccessResponsesByPath: [String: [Bool]] = [:]

    func beginAccess(to url: URL) -> SecurityScopedAccessToken {
        accessedURLs.append(url)
        let didStartAccess: Bool
        if var queuedResponses = didStartAccessResponsesByPath[url.path],
           let response = queuedResponses.first {
            queuedResponses.removeFirst()
            didStartAccessResponsesByPath[url.path] = queuedResponses
            didStartAccess = response
        } else {
            didStartAccess = didStartAccessByPath[url.path] ?? true
        }
        return TestSecurityToken(
            url: url,
            didStartAccess: didStartAccess
        )
    }
}

final class TestSecurityToken: SecurityScopedAccessToken {
    let url: URL
    let didStartAccess: Bool

    init(url: URL = URL(fileURLWithPath: "/test-scope"), didStartAccess: Bool = true) {
        self.url = url
        self.didStartAccess = didStartAccess
    }

    func endAccess() {}
}

@MainActor
final class TestAutoOpenSettler: AutoOpenSettling {
    var pendingContext: PendingAutoOpenSettlingContext?

    private(set) var beginSettlingCalls: [PendingAutoOpenSettlingContext?] = []
    private(set) var clearSettlingCallCount = 0
    private(set) var handleChangeIfNeededCalls: [URL] = []

    var makePendingContextResult: PendingAutoOpenSettlingContext?
    var handleChangeIfNeededResult = false

    func makePendingContext(
        origin: OpenOrigin,
        initialDiffBaselineMarkdown: String?,
        loadedMarkdown: String,
        now: Date
    ) -> PendingAutoOpenSettlingContext? {
        makePendingContextResult
    }

    func beginSettling(_ context: PendingAutoOpenSettlingContext?) {
        pendingContext = context
        beginSettlingCalls.append(context)
    }

    func clearSettling() {
        pendingContext = nil
        clearSettlingCallCount += 1
    }

    func handleChangeIfNeeded(
        fileURL: URL,
        loader: (URL) throws -> (markdown: String, modificationDate: Date)
    ) -> Bool {
        handleChangeIfNeededCalls.append(fileURL)
        return handleChangeIfNeededResult
    }
}

final class TestDocumentIO: DocumentIO {
    private let realIO = DocumentIOService()

    func load(at accessibleURL: URL) throws -> (markdown: String, modificationDate: Date) {
        try realIO.load(at: accessibleURL)
    }

    func write(_ markdown: String, to accessibleURL: URL) throws {
        try realIO.write(markdown, to: accessibleURL)
    }

    func modificationDate(for url: URL) -> Date {
        realIO.modificationDate(for: url)
    }
}

final class TestFileActions: FileActionHandling {
    func registeredApplications(for fileURL: URL) throws -> [ExternalApplication] {
        []
    }

    func open(fileURL: URL, in application: ExternalApplication?) throws {}
    func revealInFinder(fileURL: URL) throws {}
}

final class TestWorkspace: WorkspaceControlling {
    let applicationURLsToReturn: [URL]

    init(applicationURLsToReturn: [URL]) {
        self.applicationURLsToReturn = applicationURLsToReturn
    }

    func urlsForApplications(toOpen url: URL) -> [URL] {
        applicationURLsToReturn
    }

    func open(_ url: URL) -> Bool {
        true
    }

    func open(_ urls: [URL], withApplicationAt applicationURL: URL, configuration: NSWorkspace.OpenConfiguration) {}

    func activateFileViewerSelecting(_ fileURLs: [URL]) {}
}

final class TestSystemNotifier: SystemNotifying {
    struct FileChangeNotification: Equatable {
        let fileURL: URL
        let changeKind: FolderWatchChangeKind
        let watchedFolderURL: URL?
    }

    private(set) var fileChangeNotifications: [FileChangeNotification] = []

    func notifyFileChanged(
        _ fileURL: URL,
        changeKind: FolderWatchChangeKind,
        watchedFolderURL: URL?
    ) {
        fileChangeNotifications.append(
            FileChangeNotification(
                fileURL: FileRouting.normalizedFileURL(fileURL),
                changeKind: changeKind,
                watchedFolderURL: watchedFolderURL.map(FileRouting.normalizedFileURL)
            )
        )
    }
}

final class TestNotificationTargetFocuser: NotificationTargetFocusing {
    private(set) var focusedTargets: [(fileURL: URL?, watchedFolderURL: URL?)] = []
    var focusResult = true

    func focusNotificationTarget(fileURL: URL?, watchedFolderURL: URL?) -> Bool {
        focusedTargets.append((
            fileURL.map(FileRouting.normalizedFileURL),
            watchedFolderURL.map(FileRouting.normalizedFileURL)
        ))
        return focusResult
    }
}

final class TestUserNotificationCenter: UserNotificationCentering {
    weak var delegate: UNUserNotificationCenterDelegate?

    private(set) var requestAuthorizationCallCount = 0
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var recordedEvents: [String] = []
    var authorizationRequestResult = true
    var currentNotificationSettings = UserNotificationSettings(
        authorizationStatus: .notDetermined,
        alertSetting: .disabled,
        soundSetting: .disabled,
        notificationCenterSetting: .enabled
    )

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        recordedEvents.append("requestAuthorization")
        requestAuthorizationCallCount += 1
        if authorizationRequestResult {
            currentNotificationSettings = UserNotificationSettings(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                soundSetting: .disabled,
                notificationCenterSetting: .enabled
            )
        }
        completionHandler(authorizationRequestResult, nil)
    }

    func notificationSettings(
        completionHandler: @escaping (UserNotificationSettings) -> Void
    ) {
        recordedEvents.append("notificationSettings")
        completionHandler(currentNotificationSettings)
    }

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: ((Error?) -> Void)?
    ) {
        recordedEvents.append("add")
        addedRequests.append(request)
        completionHandler?(nil)
    }
}

func makeTestApplicationBundle(
    at bundleURL: URL,
    bundleIdentifier: String,
    displayName: String
) throws -> URL {
    let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
    let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
    let executableName = displayName.replacingOccurrences(of: " ", with: "")
    let executableURL = macOSURL.appendingPathComponent(executableName)
    let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")

    try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

    let infoDictionary: [String: Any] = [
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundleDisplayName": displayName,
        "CFBundleExecutable": executableName,
        "CFBundleName": displayName,
        "CFBundlePackageType": "APPL"
    ]

    let infoData = try PropertyListSerialization.data(
        fromPropertyList: infoDictionary,
        format: .xml,
        options: 0
    )
    try infoData.write(to: infoPlistURL)
    try Data().write(to: executableURL)

    return bundleURL
}

@MainActor
final class TestFolderWatchControllerDelegate: FolderWatchControllerDelegate {
    var currentDocumentFileURL: URL?
    var openDocumentFileURLs: [URL] = []
    private(set) var handledEvents: [FolderWatchChangeEvent] = []
    private(set) var selectNewestDocumentCallCount = 0
    private(set) var stateDidChangeCallCount = 0

    func folderWatchControllerCurrentDocumentFileURL(_ controller: FolderWatchController) -> URL? {
        currentDocumentFileURL
    }

    func folderWatchControllerOpenDocumentFileURLs(_ controller: FolderWatchController) -> [URL] {
        openDocumentFileURLs
    }

    func folderWatchController(
        _ controller: FolderWatchController,
        handleEvents events: [FolderWatchChangeEvent],
        in session: FolderWatchSession,
        origin: OpenOrigin
    ) {
        handledEvents.append(contentsOf: events)
    }

    private(set) var liveAutoOpenedURLs: [URL] = []

    func folderWatchController(_ controller: FolderWatchController, didLiveAutoOpenFileURLs urls: [URL]) {
        liveAutoOpenedURLs.append(contentsOf: urls)
    }

    func folderWatchControllerShouldSelectNewestDocument(_ controller: FolderWatchController) {
        selectNewestDocumentCallCount += 1
    }

    func folderWatchControllerStateDidChange(_ controller: FolderWatchController) {
        stateDidChangeCallCount += 1
    }
}

struct SidebarSortTestItem {
    let id: String
    let displayName: String?
    let lastChangedAt: Date?
}

@MainActor
struct DocumentStoreTestFixture {
    let temporaryDirectoryURL: URL
    let primaryFileURL: URL
    let secondaryFileURL: URL
    let store: DocumentStore
    let notifier = TestSystemNotifier()

    private let renderer = TestMarkdownRenderer()
    let differ: TestChangedRegionDiffer
    let watcher = TestFileWatcher()
    let settings: TestSettingsStore
    let securityScope = TestSecurityScopeAccess()
    private let fileActions = TestFileActions()

    init(
        autoRefreshOnExternalChange: Bool,
        notificationsEnabled: Bool = true,
        changedRegionsForModifiedContent: [ChangedRegion] = [],
        autoOpenSettlingInterval: TimeInterval = 1.0,
        diffBaselineLookback: DiffBaselineLookback = .twoMinutes,
        requestWatchedFolderReauthorization: @escaping (URL) -> URL? = { _ in nil }
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        temporaryDirectoryURL = directory
        primaryFileURL = directory.appendingPathComponent("first.md")
        secondaryFileURL = directory.appendingPathComponent("second.md")

        try "# Initial".write(to: primaryFileURL, atomically: true, encoding: .utf8)
        try "# Second".write(to: secondaryFileURL, atomically: true, encoding: .utf8)

        differ = TestChangedRegionDiffer(changedRegionsForModifiedContent: changedRegionsForModifiedContent)
        settings = TestSettingsStore(
            autoRefreshOnExternalChange: autoRefreshOnExternalChange,
            notificationsEnabled: notificationsEnabled,
            diffBaselineLookback: diffBaselineLookback
        )
        let securityScopeResolver = SecurityScopeResolver(
            securityScope: securityScope,
            settingsStore: settings,
            requestWatchedFolderReauthorization: requestWatchedFolderReauthorization
        )
        let settler = AutoOpenSettler(settlingInterval: autoOpenSettlingInterval)
        store = DocumentStore(
            rendering: RenderingDependencies(renderer: renderer, differ: differ),
            file: FileDependencies(watcher: watcher, io: DocumentIOService(), actions: fileActions),
            folderWatch: FolderWatchDependencies(
                autoOpenPlanner: FolderWatchAutoOpenPlanner(),
                settler: settler,
                systemNotifier: notifier
            ),
            settingsStore: settings,
            securityScopeResolver: securityScopeResolver
        )
    }

    func write(content: String, to url: URL) {
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    var document: DocumentController { store.document }
    var rendering: RenderingController { store.renderingController }
    var sourceEditing: SourceEditingController { store.sourceEditingController }
    var externalChange: ExternalChangeController { store.externalChange }
    var tocController: TOCController { store.toc }
    var folderWatchDispatcherController: FolderWatchDispatcher { store.folderWatchDispatcher }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}

@MainActor
struct SidebarControllerTestHarness {
    let temporaryDirectoryURL: URL
    let primaryFileURL: URL
    let secondaryFileURL: URL
    let controller: SidebarDocumentController
    let folderWatchControllerWatcher: TestFolderWatcher
    let fileWatchers: [TestFileWatcher]
    let settingsStore: SettingsStore

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-sidebar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        temporaryDirectoryURL = directory
        primaryFileURL = directory.appendingPathComponent("alpha.md")
        secondaryFileURL = directory.appendingPathComponent("zeta.md")

        try "# Alpha".write(to: primaryFileURL, atomically: true, encoding: .utf8)
        try "# Zeta".write(to: secondaryFileURL, atomically: true, encoding: .utf8)

        let settingsStore = SettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.sidebar.tests.\(UUID().uuidString)"
        )
        self.settingsStore = settingsStore
        let controllerWatcher = TestFolderWatcher()
        folderWatchControllerWatcher = controllerWatcher
        var createdFileWatchers: [TestFileWatcher] = []
        controller = SidebarDocumentController(
            settingsStore: settingsStore,
            makeDocumentStore: {
                let fileWatcher = TestFileWatcher()
                createdFileWatchers.append(fileWatcher)
                let settler = AutoOpenSettler(settlingInterval: 1.0)
                let securityScopeResolver = SecurityScopeResolver(
                    securityScope: TestSecurityScopeAccess(),
                    settingsStore: settingsStore,
                    requestWatchedFolderReauthorization: { _ in nil }
                )
                let store = DocumentStore(
                    rendering: RenderingDependencies(
                        renderer: TestMarkdownRenderer(), differ: TestChangedRegionDiffer()
                    ),
                    file: FileDependencies(
                        watcher: fileWatcher, io: DocumentIOService(), actions: TestFileActions()
                    ),
                    folderWatch: FolderWatchDependencies(
                        autoOpenPlanner: FolderWatchAutoOpenPlanner(),
                        settler: settler,
                        systemNotifier: TestSystemNotifier()
                    ),
                    settingsStore: settingsStore,
                    securityScopeResolver: securityScopeResolver
                )
                return store
            },
            makeFolderWatchController: {
                FolderWatchController(
                    folderWatcher: controllerWatcher,
                    settingsStore: settingsStore,
                    securityScope: TestSecurityScopeAccess(),
                    systemNotifier: TestSystemNotifier(),
                    folderWatchAutoOpenPlanner: FolderWatchAutoOpenPlanner()
                )
            }
        )
        fileWatchers = createdFileWatchers
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}