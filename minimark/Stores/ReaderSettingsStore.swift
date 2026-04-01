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

nonisolated struct ReaderTrustedImageFolder: Equatable, Hashable, Codable, Sendable, Identifiable {
    static let maximumCount = 30

    let folderPath: String
    let bookmarkData: Data?

    nonisolated var id: String {
        folderPath
    }

    nonisolated var folderURL: URL {
        URL(fileURLWithPath: folderPath)
    }

    init(folderURL: URL) {
        let normalizedURL = ReaderFileRouting.normalizedFileURL(folderURL)
        folderPath = normalizedURL.path
        bookmarkData = try? folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    init(folderPath: String, bookmarkData: Data?) {
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
    }
}

nonisolated enum ReaderTrustedImageFolderHistory {
    static func insertingUnique(
        _ folderURL: URL,
        into existingEntries: [ReaderTrustedImageFolder]
    ) -> [ReaderTrustedImageFolder] {
        let newEntry = ReaderTrustedImageFolder(folderURL: folderURL)
        let deduplicated = existingEntries.filter { $0.folderPath != newEntry.folderPath }
        return Array(([newEntry] + deduplicated).prefix(ReaderTrustedImageFolder.maximumCount))
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

        return Dictionary(entries.map { entry in
            let excludedCount = entry.options.excludedSubdirectoryPaths.count
            guard entry.options.scope == .includeSubfolders, excludedCount > 0 else {
                return (entry.folderPath, baseTitlesByPath[entry.folderPath] ?? entry.displayName)
            }

            let noun = excludedCount == 1 ? "folder" : "folders"
            let baseTitle = baseTitlesByPath[entry.folderPath] ?? entry.displayName
            return (entry.folderPath, "\(baseTitle) [\(excludedCount) filtered \(noun)]")
        }, uniquingKeysWith: { first, _ in first })
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

        return Dictionary(entries.map { entry in
            let key = entry[keyPath: keyPath]
            let resolvedDisplayName = entry[keyPath: displayName]
            return (
                key,
                context.title(
                    displayName: resolvedDisplayName,
                    pathText: entry[keyPath: pathText]
                )
            )
        }, uniquingKeysWith: { first, _ in first })
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
        let parentComponentsByPath = Dictionary(allPaths.map { path in
            (path, parentComponents(for: path))
        }, uniquingKeysWith: { first, _ in first })

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
    var sidebarGroupSortMode: ReaderSidebarSortMode
    var favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    var recentWatchedFolders: [ReaderRecentWatchedFolder]
    var recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    var trustedImageFolders: [ReaderTrustedImageFolder]

    init(
        appAppearance: AppAppearance,
        readerTheme: ReaderThemeKind,
        syntaxTheme: SyntaxThemeKind,
        baseFontSize: Double,
        autoRefreshOnExternalChange: Bool,
        notificationsEnabled: Bool,
        multiFileDisplayMode: ReaderMultiFileDisplayMode,
        sidebarSortMode: ReaderSidebarSortMode,
        sidebarGroupSortMode: ReaderSidebarSortMode = .lastChangedNewestFirst,
        favoriteWatchedFolders: [ReaderFavoriteWatchedFolder] = [],
        recentWatchedFolders: [ReaderRecentWatchedFolder],
        recentManuallyOpenedFiles: [ReaderRecentOpenedFile],
        trustedImageFolders: [ReaderTrustedImageFolder] = []
    ) {
        self.appAppearance = appAppearance
        self.readerTheme = readerTheme
        self.syntaxTheme = syntaxTheme
        self.baseFontSize = baseFontSize
        self.autoRefreshOnExternalChange = autoRefreshOnExternalChange
        self.notificationsEnabled = notificationsEnabled
        self.multiFileDisplayMode = multiFileDisplayMode
        self.sidebarSortMode = sidebarSortMode
        self.sidebarGroupSortMode = sidebarGroupSortMode
        self.favoriteWatchedFolders = favoriteWatchedFolders
        self.recentWatchedFolders = recentWatchedFolders
        self.recentManuallyOpenedFiles = recentManuallyOpenedFiles
        self.trustedImageFolders = trustedImageFolders
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
        case sidebarGroupSortMode
        case favoriteWatchedFolders
        case recentWatchedFolders
        case recentManuallyOpenedFiles
        case trustedImageFolders
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
        sidebarGroupSortMode: .lastChangedNewestFirst,
        favoriteWatchedFolders: [],
        recentWatchedFolders: [],
        recentManuallyOpenedFiles: [],
        trustedImageFolders: []
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
        sidebarGroupSortMode = try container.decodeIfPresent(ReaderSidebarSortMode.self, forKey: .sidebarGroupSortMode) ?? .lastChangedNewestFirst
        favoriteWatchedFolders = try container.decodeIfPresent([ReaderFavoriteWatchedFolder].self, forKey: .favoriteWatchedFolders) ?? []
        recentWatchedFolders = try container.decodeIfPresent([ReaderRecentWatchedFolder].self, forKey: .recentWatchedFolders) ?? []
        recentManuallyOpenedFiles = try container.decodeIfPresent([ReaderRecentOpenedFile].self, forKey: .recentManuallyOpenedFiles) ?? []
        trustedImageFolders = try container.decodeIfPresent([ReaderTrustedImageFolder].self, forKey: .trustedImageFolders) ?? []
    }
}

@MainActor protocol ReaderSettingsReading: AnyObject {
    var settingsPublisher: AnyPublisher<ReaderSettings, Never> { get }
    var currentSettings: ReaderSettings { get }
}

@MainActor protocol ReaderSettingsWriting: AnyObject {
    func updateAppAppearance(_ appearance: AppAppearance)
    func updateTheme(_ kind: ReaderThemeKind)
    func updateSyntaxTheme(_ kind: SyntaxThemeKind)
    func updateBaseFontSize(_ value: Double)
    func updateNotificationsEnabled(_ isEnabled: Bool)
    func updateMultiFileDisplayMode(_ mode: ReaderMultiFileDisplayMode)
    func updateSidebarSortMode(_ mode: ReaderSidebarSortMode)
    func updateSidebarGroupSortMode(_ mode: ReaderSidebarSortMode)
    func addFavoriteWatchedFolder(
        name: String,
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        openDocumentFileURLs: [URL],
        workspaceState: ReaderFavoriteWorkspaceState
    )
    func removeFavoriteWatchedFolder(id: UUID)
    func renameFavoriteWatchedFolder(id: UUID, newName: String)
    func updateFavoriteWatchedFolderOpenDocuments(
        id: UUID,
        folderURL: URL,
        openDocumentFileURLs: [URL]
    )
    func updateFavoriteWatchedFolderKnownDocuments(
        id: UUID,
        folderURL: URL,
        knownDocumentFileURLs: [URL]
    )
    func updateFavoriteWorkspaceState(id: UUID, workspaceState: ReaderFavoriteWorkspaceState)
    func resolvedFavoriteWatchedFolderURL(for entry: ReaderFavoriteWatchedFolder) -> URL
    func clearFavoriteWatchedFolders()
    func addRecentWatchedFolder(_ folderURL: URL, options: ReaderFolderWatchOptions)
    func resolvedRecentWatchedFolderURL(matching folderURL: URL) -> URL?
    func clearRecentWatchedFolders()
    func addRecentManuallyOpenedFile(_ fileURL: URL)
    func resolvedRecentManuallyOpenedFileURL(matching fileURL: URL) -> URL?
    func clearRecentManuallyOpenedFiles()
    func addTrustedImageFolder(_ folderURL: URL)
    func resolvedTrustedImageFolderURL(containing fileURL: URL) -> URL?
}

typealias ReaderSettingsStoring = ReaderSettingsReading & ReaderSettingsWriting

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
    let bookmarkResolver: BookmarkResolver
    let bookmarkCreator: BookmarkCreator
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

    func updateSidebarGroupSortMode(_ mode: ReaderSidebarSortMode) {
        updateSettings(coalescePersistence: true) { settings in
            settings.sidebarGroupSortMode = mode
        }
    }

    func updateSettings(
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

}
