import Foundation
import Combine

nonisolated struct ReaderRecentOpenedFile: Equatable, Hashable, Codable, Sendable, Identifiable {
    static let maximumCount = 15

    let filePath: String
    let bookmarkData: Data?

    nonisolated var id: String {
        filePath
    }

    nonisolated var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    nonisolated var resolvedFileURL: URL {
        guard let bookmarkData else {
            return fileURL
        }

        var bookmarkIsStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        ) else {
            return fileURL
        }

        return resolvedURL
    }

    nonisolated var displayName: String {
        let name = fileURL.lastPathComponent
        return name.isEmpty ? filePath : name
    }

    nonisolated var pathText: String {
        filePath
    }

    init(fileURL: URL) {
        let normalizedURL = ReaderFileRouting.normalizedFileURL(fileURL)
        filePath = normalizedURL.path
        bookmarkData = try? fileURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    init(filePath: String, bookmarkData: Data?) {
        self.filePath = filePath
        self.bookmarkData = bookmarkData
    }
}

nonisolated struct ReaderRecentWatchedFolder: Equatable, Hashable, Codable, Sendable, Identifiable {
    static let maximumCount = 15

    let folderPath: String
    let options: ReaderFolderWatchOptions
    let bookmarkData: Data?

    nonisolated var id: String {
        folderPath
    }

    nonisolated var folderURL: URL {
        URL(fileURLWithPath: folderPath)
    }

    nonisolated var displayName: String {
        let name = folderURL.lastPathComponent
        return name.isEmpty ? folderPath : name
    }

    nonisolated var pathText: String {
        folderPath
    }

    nonisolated var resolvedFolderURL: URL {
        guard let bookmarkData else {
            return folderURL
        }

        var bookmarkIsStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        ) else {
            return folderURL
        }

        return resolvedURL
    }

    init(folderURL: URL, options: ReaderFolderWatchOptions) {
        let normalizedURL = ReaderFileRouting.normalizedFileURL(folderURL)
        folderPath = normalizedURL.path
        self.options = options
        bookmarkData = try? folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    init(folderPath: String, options: ReaderFolderWatchOptions, bookmarkData: Data?) {
        self.folderPath = folderPath
        self.options = options
        self.bookmarkData = bookmarkData
    }
}

nonisolated enum ReaderRecentHistory {
    private struct MenuDisambiguationContext {
        let siblingPathsByDisplayName: [String: [String]]
        let parentComponentsByPath: [String: [String]]

        func title(displayName: String, pathText: String) -> String {
            let siblingPaths = siblingPathsByDisplayName[displayName] ?? []
            guard siblingPaths.count > 1,
                  let suffix = uniqueParentSuffix(
                    for: pathText,
                    among: siblingPaths,
                    parentComponentsByPath: parentComponentsByPath
                  ) else {
                return displayName
            }

            return "\(displayName) (\(suffix))"
        }
    }

    static func insertingUniqueFile(
        _ fileURL: URL,
        into existingEntries: [ReaderRecentOpenedFile]
    ) -> [ReaderRecentOpenedFile] {
        let newEntry = ReaderRecentOpenedFile(fileURL: fileURL)
        let deduplicated = existingEntries.filter { $0.filePath != newEntry.filePath }
        return Array(([newEntry] + deduplicated).prefix(ReaderRecentOpenedFile.maximumCount))
    }

    static func insertingUniqueWatchedFolder(
        _ folderURL: URL,
        options: ReaderFolderWatchOptions,
        into existingEntries: [ReaderRecentWatchedFolder]
    ) -> [ReaderRecentWatchedFolder] {
        let newEntry = ReaderRecentWatchedFolder(folderURL: folderURL, options: options)
        let deduplicated = existingEntries.filter { $0.folderPath != newEntry.folderPath }
        return Array(([newEntry] + deduplicated).prefix(ReaderRecentWatchedFolder.maximumCount))
    }

    static func menuTitle(
        for entry: ReaderRecentOpenedFile,
        among entries: [ReaderRecentOpenedFile]
    ) -> String {
        menuTitle(
            for: entry,
            among: entries,
            displayName: \ .displayName,
            pathText: \ .pathText
        )
    }

    static func menuTitles(for entries: [ReaderRecentOpenedFile]) -> [String: String] {
        menuTitles(for: entries, keyPath: \.filePath, displayName: \.displayName, pathText: \.pathText)
    }

    static func menuTitle(
        for entry: ReaderRecentWatchedFolder,
        among entries: [ReaderRecentWatchedFolder]
    ) -> String {
        let baseTitle = menuTitle(
            for: entry,
            among: entries,
            displayName: \ .displayName,
            pathText: \ .pathText
        )

        let excludedCount = entry.options.excludedSubdirectoryPaths.count
        guard entry.options.scope == .includeSubfolders, excludedCount > 0 else {
            return baseTitle
        }

        let noun = excludedCount == 1 ? "folder" : "folders"
        return "\(baseTitle) [\(excludedCount) filtered \(noun)]"
    }

    static func menuTitles(for entries: [ReaderRecentWatchedFolder]) -> [String: String] {
        let baseTitlesByPath = menuTitles(
            for: entries,
            keyPath: \.folderPath,
            displayName: \.displayName,
            pathText: \.pathText
        )

        return Dictionary(uniqueKeysWithValues: entries.map { entry in
            let excludedCount = entry.options.excludedSubdirectoryPaths.count
            guard entry.options.scope == .includeSubfolders, excludedCount > 0 else {
                return (entry.folderPath, baseTitlesByPath[entry.folderPath] ?? entry.displayName)
            }

            let noun = excludedCount == 1 ? "folder" : "folders"
            let baseTitle = baseTitlesByPath[entry.folderPath] ?? entry.displayName
            return (entry.folderPath, "\(baseTitle) [\(excludedCount) filtered \(noun)]")
        })
    }

    private static func menuTitle<Entry>(
        for entry: Entry,
        among entries: [Entry],
        displayName: KeyPath<Entry, String>,
        pathText: KeyPath<Entry, String>
    ) -> String {
        let context = buildMenuDisambiguationContext(
            for: entries,
            displayName: displayName,
            pathText: pathText
        )
        return context.title(
            displayName: entry[keyPath: displayName],
            pathText: entry[keyPath: pathText]
        )
    }

    private static func menuTitles<Entry>(
        for entries: [Entry],
        keyPath: KeyPath<Entry, String>,
        displayName: KeyPath<Entry, String>,
        pathText: KeyPath<Entry, String>
    ) -> [String: String] {
        let context = buildMenuDisambiguationContext(
            for: entries,
            displayName: displayName,
            pathText: pathText
        )

        return Dictionary(uniqueKeysWithValues: entries.map { entry in
            let key = entry[keyPath: keyPath]
            let resolvedDisplayName = entry[keyPath: displayName]
            return (
                key,
                context.title(
                    displayName: resolvedDisplayName,
                    pathText: entry[keyPath: pathText]
                )
            )
        })
    }

    private static func buildMenuDisambiguationContext<Entry>(
        for entries: [Entry],
        displayName: KeyPath<Entry, String>,
        pathText: KeyPath<Entry, String>
    ) -> MenuDisambiguationContext {
        let siblingPathsByDisplayName = Dictionary(grouping: entries, by: { $0[keyPath: displayName] })
            .mapValues { groupedEntries in
                groupedEntries.map { $0[keyPath: pathText] }
            }

        let allPaths = siblingPathsByDisplayName.values.flatMap { $0 }
        let parentComponentsByPath = Dictionary(uniqueKeysWithValues: allPaths.map { path in
            (path, parentComponents(for: path))
        })

        return MenuDisambiguationContext(
            siblingPathsByDisplayName: siblingPathsByDisplayName,
            parentComponentsByPath: parentComponentsByPath
        )
    }

    private static func uniqueParentSuffix(
        for path: String,
        among siblingPaths: [String],
        parentComponentsByPath: [String: [String]]
    ) -> String? {
        let siblingParentComponents = siblingPaths.map { parentComponentsByPath[$0] ?? parentComponents(for: $0) }
        let targetParentComponents = parentComponentsByPath[path] ?? parentComponents(for: path)
        guard !targetParentComponents.isEmpty else {
            return nil
        }

        let maximumDepth = siblingParentComponents.map(\.count).max() ?? 0
        for suffixLength in 1...maximumDepth {
            let targetSuffix = suffix(parentComponents: targetParentComponents, count: suffixLength)
            let siblingSuffixes = siblingParentComponents.map { suffix(parentComponents: $0, count: suffixLength) }

            if siblingSuffixes.filter({ $0 == targetSuffix }).count == 1 {
                return targetSuffix
            }
        }

        return targetParentComponents.joined(separator: "/")
    }

    private static func parentComponents(for path: String) -> [String] {
        URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
    }

    private static func suffix(parentComponents: [String], count: Int) -> String {
        let suffixCount = min(count, parentComponents.count)
        return parentComponents.suffix(suffixCount).joined(separator: "/")
    }
}

protocol ReaderSettingsKeyValueStoring: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: ReaderSettingsKeyValueStoring {}

nonisolated struct ReaderSettings: Equatable, Codable, Sendable {
    var appAppearance: AppAppearance
    var readerTheme: ReaderThemeKind
    var syntaxTheme: SyntaxThemeKind
    var baseFontSize: Double
    var autoRefreshOnExternalChange: Bool
    var notificationsEnabled: Bool
    var multiFileDisplayMode: ReaderMultiFileDisplayMode
    var sidebarSortMode: ReaderSidebarSortMode
    var recentWatchedFolders: [ReaderRecentWatchedFolder]
    var recentManuallyOpenedFiles: [ReaderRecentOpenedFile]

    init(
        appAppearance: AppAppearance,
        readerTheme: ReaderThemeKind,
        syntaxTheme: SyntaxThemeKind,
        baseFontSize: Double,
        autoRefreshOnExternalChange: Bool,
        notificationsEnabled: Bool,
        multiFileDisplayMode: ReaderMultiFileDisplayMode,
        sidebarSortMode: ReaderSidebarSortMode,
        recentWatchedFolders: [ReaderRecentWatchedFolder],
        recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    ) {
        self.appAppearance = appAppearance
        self.readerTheme = readerTheme
        self.syntaxTheme = syntaxTheme
        self.baseFontSize = baseFontSize
        self.autoRefreshOnExternalChange = autoRefreshOnExternalChange
        self.notificationsEnabled = notificationsEnabled
        self.multiFileDisplayMode = multiFileDisplayMode
        self.sidebarSortMode = sidebarSortMode
        self.recentWatchedFolders = recentWatchedFolders
        self.recentManuallyOpenedFiles = recentManuallyOpenedFiles
    }

    enum CodingKeys: String, CodingKey {
        case appAppearance
        case readerTheme
        case syntaxTheme
        case baseFontSize
        case autoRefreshOnExternalChange
        case notificationsEnabled
        case multiFileDisplayMode
        case sidebarSortMode
        case recentWatchedFolders
        case recentManuallyOpenedFiles
    }

    static let `default` = ReaderSettings(
        appAppearance: .system,
        readerTheme: .blackOnWhite,
        syntaxTheme: .monokai,
        baseFontSize: 15,
        autoRefreshOnExternalChange: true,
        notificationsEnabled: true,
        multiFileDisplayMode: .sidebarLeft,
        sidebarSortMode: .openOrder,
        recentWatchedFolders: [],
        recentManuallyOpenedFiles: []
    )

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appAppearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appAppearance) ?? .system
        readerTheme = try container.decode(ReaderThemeKind.self, forKey: .readerTheme)
        syntaxTheme = try container.decode(SyntaxThemeKind.self, forKey: .syntaxTheme)
        baseFontSize = try container.decode(Double.self, forKey: .baseFontSize)
        autoRefreshOnExternalChange = try container.decode(Bool.self, forKey: .autoRefreshOnExternalChange)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        multiFileDisplayMode = try container.decode(ReaderMultiFileDisplayMode.self, forKey: .multiFileDisplayMode)
        sidebarSortMode = try container.decodeIfPresent(ReaderSidebarSortMode.self, forKey: .sidebarSortMode) ?? .openOrder
        recentWatchedFolders = try container.decodeIfPresent([ReaderRecentWatchedFolder].self, forKey: .recentWatchedFolders) ?? []
        recentManuallyOpenedFiles = try container.decodeIfPresent([ReaderRecentOpenedFile].self, forKey: .recentManuallyOpenedFiles) ?? []
    }
}

@MainActor protocol ReaderSettingsStoring: AnyObject {
    var settingsPublisher: AnyPublisher<ReaderSettings, Never> { get }
    var currentSettings: ReaderSettings { get }

    func updateAppAppearance(_ appearance: AppAppearance)
    func updateTheme(_ kind: ReaderThemeKind)
    func updateSyntaxTheme(_ kind: SyntaxThemeKind)
    func updateBaseFontSize(_ value: Double)
    func updateNotificationsEnabled(_ isEnabled: Bool)
    func updateMultiFileDisplayMode(_ mode: ReaderMultiFileDisplayMode)
    func updateSidebarSortMode(_ mode: ReaderSidebarSortMode)
    func addRecentWatchedFolder(_ folderURL: URL, options: ReaderFolderWatchOptions)
    func resolvedRecentWatchedFolderURL(matching folderURL: URL) -> URL?
    func clearRecentWatchedFolders()
    func addRecentManuallyOpenedFile(_ fileURL: URL)
    func resolvedRecentManuallyOpenedFileURL(matching fileURL: URL) -> URL?
    func clearRecentManuallyOpenedFiles()
}

@MainActor final class ReaderSettingsStore: ObservableObject, ReaderSettingsStoring {
    typealias BookmarkResolution = (url: URL, isStale: Bool)
    typealias BookmarkResolver = (Data) throws -> BookmarkResolution
    typealias BookmarkCreator = (URL) throws -> Data

    let objectWillChange = ObservableObjectPublisher()

    var settingsPublisher: AnyPublisher<ReaderSettings, Never> {
        subject.eraseToAnyPublisher()
    }

    var currentSettings: ReaderSettings {
        subject.value
    }

    private let storage: ReaderSettingsKeyValueStoring
    private let storageKey: String
    private let subject: CurrentValueSubject<ReaderSettings, Never>
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let bookmarkResolver: BookmarkResolver
    private let bookmarkCreator: BookmarkCreator
    private let minimumPersistInterval: TimeInterval
    private var pendingPersistWorkItem: DispatchWorkItem?
    private var lastPersistAt: Date = .distantPast

    init(
        storage: ReaderSettingsKeyValueStoring = UserDefaults.standard,
        storageKey: String = "reader.settings.v1",
        bookmarkResolver: @escaping BookmarkResolver = { bookmarkData in
            var bookmarkIsStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkIsStale
            )
            return (resolvedURL, bookmarkIsStale)
        },
        bookmarkCreator: @escaping BookmarkCreator = { resolvedURL in
            try resolvedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        },
        minimumPersistInterval: TimeInterval = 0.2
    ) {
        self.storage = storage
        self.storageKey = storageKey
        self.bookmarkResolver = bookmarkResolver
        self.bookmarkCreator = bookmarkCreator
        self.minimumPersistInterval = max(0, minimumPersistInterval)
        let initialSettings: ReaderSettings

        if let data = storage.data(forKey: storageKey),
           let decoded = try? decoder.decode(ReaderSettings.self, from: data) {
            initialSettings = decoded
        } else {
            initialSettings = .default
        }

        self.subject = CurrentValueSubject(initialSettings)
    }

    func updateAppAppearance(_ appearance: AppAppearance) {
        updateSettings(coalescePersistence: true) { settings in
            settings.appAppearance = appearance
        }
    }

    func updateTheme(_ kind: ReaderThemeKind) {
        updateSettings(coalescePersistence: true) { settings in
            settings.readerTheme = kind
        }
    }

    func updateSyntaxTheme(_ kind: SyntaxThemeKind) {
        updateSettings(coalescePersistence: true) { settings in
            settings.syntaxTheme = kind
        }
    }

    func updateBaseFontSize(_ value: Double) {
        updateSettings(coalescePersistence: true) { settings in
            settings.baseFontSize = min(max(value, 10), 48)
        }
    }

    func updateNotificationsEnabled(_ isEnabled: Bool) {
        updateSettings(coalescePersistence: true) { settings in
            settings.notificationsEnabled = isEnabled
        }
    }

    func updateMultiFileDisplayMode(_ mode: ReaderMultiFileDisplayMode) {
        updateSettings(coalescePersistence: true) { settings in
            settings.multiFileDisplayMode = mode
        }
    }

    func updateSidebarSortMode(_ mode: ReaderSidebarSortMode) {
        updateSettings(coalescePersistence: true) { settings in
            settings.sidebarSortMode = mode
        }
    }

    func addRecentWatchedFolder(_ folderURL: URL, options: ReaderFolderWatchOptions) {
        updateSettings { settings in
            settings.recentWatchedFolders = ReaderRecentHistory.insertingUniqueWatchedFolder(
                folderURL,
                options: options,
                into: settings.recentWatchedFolders
            )
        }
    }

    func resolvedRecentWatchedFolderURL(matching folderURL: URL) -> URL? {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        guard let entry = currentSettings.recentWatchedFolders.first(where: { entry in
            ReaderFileRouting.normalizedFileURL(entry.folderURL) == normalizedFolderURL
        }) else {
            return nil
        }

        return resolveRecentWatchedFolderURL(for: entry)
    }

    func clearRecentWatchedFolders() {
        updateSettings { settings in
            settings.recentWatchedFolders = []
        }
    }

    func addRecentManuallyOpenedFile(_ fileURL: URL) {
        updateSettings { settings in
            settings.recentManuallyOpenedFiles = ReaderRecentHistory.insertingUniqueFile(
                fileURL,
                into: settings.recentManuallyOpenedFiles
            )
        }
    }

    func resolvedRecentManuallyOpenedFileURL(matching fileURL: URL) -> URL? {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        guard let entry = currentSettings.recentManuallyOpenedFiles.first(where: { entry in
            ReaderFileRouting.normalizedFileURL(entry.fileURL) == normalizedFileURL
        }) else {
            return nil
        }

        return resolveRecentOpenedFileURL(for: entry)
    }

    func clearRecentManuallyOpenedFiles() {
        updateSettings { settings in
            settings.recentManuallyOpenedFiles = []
        }
    }

    private func updateSettings(
        coalescePersistence: Bool = false,
        _ mutate: (inout ReaderSettings) -> Void
    ) {
        let current = subject.value
        var updated = current
        mutate(&updated)
        guard updated != current else {
            return
        }
        objectWillChange.send()
        subject.send(updated)
        if coalescePersistence {
            schedulePersist()
        } else {
            pendingPersistWorkItem?.cancel()
            pendingPersistWorkItem = nil
            persist()
        }
    }

    private func schedulePersist() {
        if minimumPersistInterval <= 0 {
            persist()
            return
        }

        let now = Date()
        let earliestPersistDate = lastPersistAt.addingTimeInterval(minimumPersistInterval)
        if now >= earliestPersistDate {
            pendingPersistWorkItem?.cancel()
            pendingPersistWorkItem = nil
            persist()
            return
        }

        guard pendingPersistWorkItem == nil else {
            return
        }

        let delay = earliestPersistDate.timeIntervalSince(now)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.pendingPersistWorkItem = nil
            self.persist()
        }
        pendingPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func persist() {
        guard let data = try? encoder.encode(subject.value) else {
            return
        }
        lastPersistAt = Date()
        storage.set(data, forKey: storageKey)
    }

    private func resolveRecentOpenedFileURL(for entry: ReaderRecentOpenedFile) -> URL {
        guard let bookmarkData = entry.bookmarkData else {
            return entry.fileURL
        }

        do {
            let resolution = try bookmarkResolver(bookmarkData)

            if resolution.isStale {
                refreshRecentOpenedFileBookmark(for: entry, resolvedURL: resolution.url)
            }

            return resolution.url
        } catch {
            updateRecentOpenedFileBookmarkData(forPath: entry.filePath, bookmarkData: nil)
            return entry.fileURL
        }
    }

    private func resolveRecentWatchedFolderURL(for entry: ReaderRecentWatchedFolder) -> URL {
        guard let bookmarkData = entry.bookmarkData else {
            return entry.folderURL
        }

        do {
            let resolution = try bookmarkResolver(bookmarkData)

            if resolution.isStale {
                refreshRecentWatchedFolderBookmark(for: entry, resolvedURL: resolution.url)
            }

            return resolution.url
        } catch {
            updateRecentWatchedFolderBookmarkData(forPath: entry.folderPath, bookmarkData: nil)
            return entry.folderURL
        }
    }

    private func refreshRecentOpenedFileBookmark(for entry: ReaderRecentOpenedFile, resolvedURL: URL) {
        let refreshedBookmarkData = try? bookmarkCreator(resolvedURL)
        updateRecentOpenedFileBookmarkData(forPath: entry.filePath, bookmarkData: refreshedBookmarkData)
    }

    private func refreshRecentWatchedFolderBookmark(for entry: ReaderRecentWatchedFolder, resolvedURL: URL) {
        let refreshedBookmarkData = try? bookmarkCreator(resolvedURL)
        updateRecentWatchedFolderBookmarkData(forPath: entry.folderPath, bookmarkData: refreshedBookmarkData)
    }

    private func updateRecentOpenedFileBookmarkData(forPath filePath: String, bookmarkData: Data?) {
        updateSettings { settings in
            guard let index = settings.recentManuallyOpenedFiles.firstIndex(where: { $0.filePath == filePath }) else {
                return
            }

            let existingEntry = settings.recentManuallyOpenedFiles[index]
            guard existingEntry.bookmarkData != bookmarkData else {
                return
            }

            settings.recentManuallyOpenedFiles[index] = ReaderRecentOpenedFile(
                filePath: existingEntry.filePath,
                bookmarkData: bookmarkData
            )
        }
    }

    private func updateRecentWatchedFolderBookmarkData(forPath folderPath: String, bookmarkData: Data?) {
        updateSettings { settings in
            guard let index = settings.recentWatchedFolders.firstIndex(where: { $0.folderPath == folderPath }) else {
                return
            }

            let existingEntry = settings.recentWatchedFolders[index]
            guard existingEntry.bookmarkData != bookmarkData else {
                return
            }

            settings.recentWatchedFolders[index] = ReaderRecentWatchedFolder(
                folderPath: existingEntry.folderPath,
                options: existingEntry.options,
                bookmarkData: bookmarkData
            )
        }
    }
}
