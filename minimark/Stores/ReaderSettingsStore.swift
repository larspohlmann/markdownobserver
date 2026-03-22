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
}

nonisolated enum ReaderRecentHistory {
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

    static func menuTitle(
        for entry: ReaderRecentWatchedFolder,
        among entries: [ReaderRecentWatchedFolder]
    ) -> String {
        menuTitle(
            for: entry,
            among: entries,
            displayName: \ .displayName,
            pathText: \ .pathText
        )
    }

    private static func menuTitle<Entry>(
        for entry: Entry,
        among entries: [Entry],
        displayName: KeyPath<Entry, String>,
        pathText: KeyPath<Entry, String>
    ) -> String {
        let siblingPaths = entries
            .filter { $0[keyPath: displayName] == entry[keyPath: displayName] }
            .map { $0[keyPath: pathText] }

        guard siblingPaths.count > 1,
              let suffix = uniqueParentSuffix(for: entry[keyPath: pathText], among: siblingPaths) else {
            return entry[keyPath: displayName]
        }

        return "\(entry[keyPath: displayName]) (\(suffix))"
    }

    private static func uniqueParentSuffix(for path: String, among siblingPaths: [String]) -> String? {
        let siblingParentComponents = siblingPaths.map(parentComponents(for:))
        let targetParentComponents = parentComponents(for: path)
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
    func clearRecentManuallyOpenedFiles()
}

@MainActor final class ReaderSettingsStore: ObservableObject, ReaderSettingsStoring {
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

    init(
        storage: ReaderSettingsKeyValueStoring = UserDefaults.standard,
        storageKey: String = "reader.settings.v1"
    ) {
        self.storage = storage
        self.storageKey = storageKey
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
        updateSettings { settings in
            settings.appAppearance = appearance
        }
    }

    func updateTheme(_ kind: ReaderThemeKind) {
        updateSettings { settings in
            settings.readerTheme = kind
        }
    }

    func updateSyntaxTheme(_ kind: SyntaxThemeKind) {
        updateSettings { settings in
            settings.syntaxTheme = kind
        }
    }

    func updateBaseFontSize(_ value: Double) {
        updateSettings { settings in
            settings.baseFontSize = min(max(value, 10), 48)
        }
    }

    func updateNotificationsEnabled(_ isEnabled: Bool) {
        updateSettings { settings in
            settings.notificationsEnabled = isEnabled
        }
    }

    func updateMultiFileDisplayMode(_ mode: ReaderMultiFileDisplayMode) {
        updateSettings { settings in
            settings.multiFileDisplayMode = mode
        }
    }

    func updateSidebarSortMode(_ mode: ReaderSidebarSortMode) {
        updateSettings { settings in
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
        return currentSettings.recentWatchedFolders.first(where: { entry in
            ReaderFileRouting.normalizedFileURL(entry.folderURL) == normalizedFolderURL
        })?.resolvedFolderURL
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

    func clearRecentManuallyOpenedFiles() {
        updateSettings { settings in
            settings.recentManuallyOpenedFiles = []
        }
    }

    private func updateSettings(_ mutate: (inout ReaderSettings) -> Void) {
        let current = subject.value
        var updated = current
        mutate(&updated)
        guard updated != current else {
            return
        }
        objectWillChange.send()
        subject.send(updated)
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(subject.value) else {
            return
        }
        storage.set(data, forKey: storageKey)
    }
}
