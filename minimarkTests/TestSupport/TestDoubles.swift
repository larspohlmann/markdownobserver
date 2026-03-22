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
        readerTheme: ReaderTheme,
        syntaxTheme: SyntaxThemeKind,
        baseFontSize: Double
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

    init(changedRegionsForModifiedContent: [ChangedRegion] = []) {
        self.changedRegionsForModifiedContent = changedRegionsForModifiedContent
    }

    func computeChangedRegions(oldMarkdown: String, newMarkdown: String) -> [ChangedRegion] {
        oldMarkdown == newMarkdown ? [] : changedRegionsForModifiedContent
    }

    func blocks(for markdown: String) -> [MarkdownBlock] {
        []
    }
}

final class TestFileWatcher: FileChangeWatching {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastStartedFileURL: URL?
    private var onChange: (@Sendable () -> Void)?

    func startWatching(fileURL: URL, onChange: @escaping @Sendable () -> Void) throws {
        startCallCount += 1
        lastStartedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        self.onChange = onChange
    }

    func stopWatching() {
        stopCallCount += 1
        onChange = nil
    }

    func emitChange() {
        onChange?()
    }
}

@MainActor
final class TestReaderSettingsStore: ReaderSettingsStoring {
    var settingsPublisher: AnyPublisher<ReaderSettings, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentSettings: ReaderSettings {
        subject.value
    }

    private(set) var recordedRecentWatchedFolders: [ReaderRecentWatchedFolder] = []
    private(set) var recordedRecentManuallyOpenedFiles: [ReaderRecentOpenedFile] = []

    private let subject: CurrentValueSubject<ReaderSettings, Never>

    init(autoRefreshOnExternalChange: Bool, notificationsEnabled: Bool = true) {
        subject = CurrentValueSubject(
            ReaderSettings(
                appAppearance: .system,
                readerTheme: .blackOnWhite,
                syntaxTheme: .monokai,
                baseFontSize: 15,
                autoRefreshOnExternalChange: autoRefreshOnExternalChange,
                notificationsEnabled: notificationsEnabled,
                multiFileDisplayMode: .sidebarLeft,
                sidebarSortMode: .openOrder,
                recentWatchedFolders: [],
                recentManuallyOpenedFiles: []
            )
        )
    }

    func updateAppAppearance(_ appearance: AppAppearance) {
        var next = subject.value
        next.appAppearance = appearance
        subject.send(next)
    }

    func updateTheme(_ kind: ReaderThemeKind) {
        var next = subject.value
        next.readerTheme = kind
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

    func updateNotificationsEnabled(_ isEnabled: Bool) {
        var next = subject.value
        next.notificationsEnabled = isEnabled
        subject.send(next)
    }

    func updateMultiFileDisplayMode(_ mode: ReaderMultiFileDisplayMode) {
        var next = subject.value
        next.multiFileDisplayMode = mode
        subject.send(next)
    }

    func updateSidebarSortMode(_ mode: ReaderSidebarSortMode) {
        var next = subject.value
        next.sidebarSortMode = mode
        subject.send(next)
    }

    func addRecentWatchedFolder(_ folderURL: URL, options: ReaderFolderWatchOptions) {
        var next = subject.value
        next.recentWatchedFolders = ReaderRecentHistory.insertingUniqueWatchedFolder(
            folderURL,
            options: options,
            into: next.recentWatchedFolders
        )
        recordedRecentWatchedFolders = next.recentWatchedFolders
        subject.send(next)
    }

    func resolvedRecentWatchedFolderURL(matching folderURL: URL) -> URL? {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        return subject.value.recentWatchedFolders.first(where: { entry in
            ReaderFileRouting.normalizedFileURL(entry.folderURL) == normalizedFolderURL
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
        next.recentManuallyOpenedFiles = ReaderRecentHistory.insertingUniqueFile(
            fileURL,
            into: next.recentManuallyOpenedFiles
        )
        recordedRecentManuallyOpenedFiles = next.recentManuallyOpenedFiles
        subject.send(next)
    }

    func clearRecentManuallyOpenedFiles() {
        var next = subject.value
        next.recentManuallyOpenedFiles = []
        recordedRecentManuallyOpenedFiles = []
        subject.send(next)
    }
}

final class TestSettingsKeyValueStorage: ReaderSettingsKeyValueStoring {
    private var storedValues: [String: Data] = [:]

    func data(forKey defaultName: String) -> Data? {
        storedValues[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storedValues[defaultName] = value as? Data
    }
}

final class TestFolderWatcher: FolderChangeWatching {
    private var onMarkdownFilesAddedOrChanged: (([ReaderFolderWatchChangeEvent]) -> Void)?

    var startCallCount = 0
    var stopCallCount = 0
    var lastIncludeSubfolders = false
    var markdownFilesToReturn: [URL] = []

    func startWatching(
        folderURL: URL,
        includeSubfolders: Bool,
        onMarkdownFilesAddedOrChanged: @escaping @Sendable ([ReaderFolderWatchChangeEvent]) -> Void
    ) throws {
        startCallCount += 1
        lastIncludeSubfolders = includeSubfolders
        self.onMarkdownFilesAddedOrChanged = onMarkdownFilesAddedOrChanged
    }

    func stopWatching() {
        stopCallCount += 1
        onMarkdownFilesAddedOrChanged = nil
    }

    func markdownFiles(in folderURL: URL, includeSubfolders: Bool) throws -> [URL] {
        markdownFilesToReturn
    }

    func emitChangedMarkdownEvents(_ events: [ReaderFolderWatchChangeEvent]) {
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

final class TestReaderFileActions: ReaderFileActionHandling {
    func registeredApplications(for fileURL: URL) throws -> [ReaderExternalApplication] {
        []
    }

    func open(fileURL: URL, in application: ReaderExternalApplication?) throws {}
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

final class TestReaderSystemNotifier: ReaderSystemNotifying {
    struct AutoLoadedNotification: Equatable {
        let fileURL: URL
        let changeKind: ReaderFolderWatchChangeKind
        let watchedFolderURL: URL?
    }

    struct ExternalChangeNotification: Equatable {
        let fileURL: URL
        let autoRefreshed: Bool
        let watchedFolderURL: URL?
    }

    private(set) var autoLoadedNotifications: [AutoLoadedNotification] = []
    private(set) var externalChangeNotifications: [ExternalChangeNotification] = []

    func notifyFileAutoLoaded(
        _ fileURL: URL,
        changeKind: ReaderFolderWatchChangeKind,
        watchedFolderURL: URL?
    ) {
        autoLoadedNotifications.append(
            AutoLoadedNotification(
                fileURL: ReaderFileRouting.normalizedFileURL(fileURL),
                changeKind: changeKind,
                watchedFolderURL: watchedFolderURL.map(ReaderFileRouting.normalizedFileURL)
            )
        )
    }

    func notifyExternalChange(for fileURL: URL, autoRefreshed: Bool, watchedFolderURL: URL?) {
        externalChangeNotifications.append(
            ExternalChangeNotification(
                fileURL: ReaderFileRouting.normalizedFileURL(fileURL),
                autoRefreshed: autoRefreshed,
                watchedFolderURL: watchedFolderURL.map(ReaderFileRouting.normalizedFileURL)
            )
        )
    }
}

final class TestNotificationTargetFocuser: ReaderNotificationTargetFocusing {
    private(set) var focusedTargets: [(fileURL: URL?, watchedFolderURL: URL?)] = []
    var focusResult = true

    func focusNotificationTarget(fileURL: URL?, watchedFolderURL: URL?) -> Bool {
        focusedTargets.append((
            fileURL.map(ReaderFileRouting.normalizedFileURL),
            watchedFolderURL.map(ReaderFileRouting.normalizedFileURL)
        ))
        return focusResult
    }
}

final class TestUserNotificationCenter: ReaderUserNotificationCentering {
    weak var delegate: UNUserNotificationCenterDelegate?

    private(set) var requestAuthorizationCallCount = 0
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var recordedEvents: [String] = []
    var authorizationRequestResult = true
    var currentNotificationSettings = ReaderUserNotificationSettings(
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
            currentNotificationSettings = ReaderUserNotificationSettings(
                authorizationStatus: .authorized,
                alertSetting: .enabled,
                soundSetting: .disabled,
                notificationCenterSetting: .enabled
            )
        }
        completionHandler(authorizationRequestResult, nil)
    }

    func notificationSettings(
        completionHandler: @escaping (ReaderUserNotificationSettings) -> Void
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

struct SidebarSortTestItem {
    let id: String
    let displayName: String?
    let lastChangedAt: Date?
}

@MainActor
struct ReaderStoreTestFixture {
    let temporaryDirectoryURL: URL
    let primaryFileURL: URL
    let secondaryFileURL: URL
    let store: ReaderStore
    let notifier = TestReaderSystemNotifier()

    private let renderer = TestMarkdownRenderer()
    private let differ: TestChangedRegionDiffer
    let watcher = TestFileWatcher()
    let folderWatcher = TestFolderWatcher()
    let settings: TestReaderSettingsStore
    let securityScope = TestSecurityScopeAccess()
    private let fileActions = TestReaderFileActions()

    init(
        autoRefreshOnExternalChange: Bool,
        notificationsEnabled: Bool = true,
        changedRegionsForModifiedContent: [ChangedRegion] = [],
        autoOpenSettlingInterval: TimeInterval = 1.0
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
        settings = TestReaderSettingsStore(
            autoRefreshOnExternalChange: autoRefreshOnExternalChange,
            notificationsEnabled: notificationsEnabled
        )
        store = ReaderStore(
            renderer: renderer,
            differ: differ,
            fileWatcher: watcher,
            folderWatcher: folderWatcher,
            settingsStore: settings,
            securityScope: securityScope,
            fileActions: fileActions,
            systemNotifier: notifier,
            autoOpenSettlingInterval: autoOpenSettlingInterval
        )
    }

    func write(content: String, to url: URL) {
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}

@MainActor
struct ReaderSidebarControllerTestHarness {
    let temporaryDirectoryURL: URL
    let primaryFileURL: URL
    let secondaryFileURL: URL
    let controller: ReaderSidebarDocumentController
    let folderWatchControllerWatcher: TestFolderWatcher
    let fileWatchers: [TestFileWatcher]
    let folderWatchers: [TestFolderWatcher]
    let settingsStore: ReaderSettingsStore

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-sidebar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        temporaryDirectoryURL = directory
        primaryFileURL = directory.appendingPathComponent("alpha.md")
        secondaryFileURL = directory.appendingPathComponent("zeta.md")

        try "# Alpha".write(to: primaryFileURL, atomically: true, encoding: .utf8)
        try "# Zeta".write(to: secondaryFileURL, atomically: true, encoding: .utf8)

        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.sidebar.tests.\(UUID().uuidString)"
        )
        self.settingsStore = settingsStore
        let controllerWatcher = TestFolderWatcher()
        folderWatchControllerWatcher = controllerWatcher
        var createdFileWatchers: [TestFileWatcher] = []
        var createdWatchers: [TestFolderWatcher] = []
        controller = ReaderSidebarDocumentController(
            settingsStore: settingsStore,
            makeReaderStore: {
                let fileWatcher = TestFileWatcher()
                createdFileWatchers.append(fileWatcher)
                let watcher = TestFolderWatcher()
                createdWatchers.append(watcher)
                return ReaderStore(
                    renderer: TestMarkdownRenderer(),
                    differ: TestChangedRegionDiffer(),
                    fileWatcher: fileWatcher,
                    folderWatcher: watcher,
                    settingsStore: settingsStore,
                    securityScope: TestSecurityScopeAccess(),
                    fileActions: TestReaderFileActions()
                )
            },
            makeFolderWatchController: {
                ReaderFolderWatchController(
                    folderWatcher: controllerWatcher,
                    settingsStore: settingsStore,
                    securityScope: TestSecurityScopeAccess(),
                    systemNotifier: TestReaderSystemNotifier(),
                    folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
                )
            }
        )
        fileWatchers = createdFileWatchers
        folderWatchers = createdWatchers
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}