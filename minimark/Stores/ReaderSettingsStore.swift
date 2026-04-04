import Foundation
import Combine

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
    var diffBaselineLookback: DiffBaselineLookback

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
        trustedImageFolders: [ReaderTrustedImageFolder] = [],
        diffBaselineLookback: DiffBaselineLookback = .twoMinutes
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
        self.diffBaselineLookback = diffBaselineLookback
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
        case diffBaselineLookback
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
        trustedImageFolders: [],
        diffBaselineLookback: .twoMinutes
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
        let decodedFavorites = try container.decodeIfPresent([ReaderFavoriteWatchedFolder].self, forKey: .favoriteWatchedFolders) ?? []
        recentWatchedFolders = try container.decodeIfPresent([ReaderRecentWatchedFolder].self, forKey: .recentWatchedFolders) ?? []
        recentManuallyOpenedFiles = try container.decodeIfPresent([ReaderRecentOpenedFile].self, forKey: .recentManuallyOpenedFiles) ?? []
        trustedImageFolders = try container.decodeIfPresent([ReaderTrustedImageFolder].self, forKey: .trustedImageFolders) ?? []
        diffBaselineLookback = try container.decodeIfPresent(DiffBaselineLookback.self, forKey: .diffBaselineLookback) ?? .twoMinutes

        // Migrate legacy favorites: replace hardcoded-default workspace state with decoded global settings
        let legacyDefaultState = ReaderFavoriteWorkspaceState.from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        )
        let globalWorkspaceState = ReaderFavoriteWorkspaceState(
            fileSortMode: sidebarSortMode,
            groupSortMode: sidebarGroupSortMode,
            sidebarPosition: multiFileDisplayMode,
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth,
            pinnedGroupIDs: [],
            collapsedGroupIDs: []
        )
        if legacyDefaultState != globalWorkspaceState {
            favoriteWatchedFolders = decodedFavorites.map { favorite in
                guard favorite.workspaceState == legacyDefaultState else { return favorite }
                var patched = favorite
                patched.workspaceState = globalWorkspaceState
                return patched
            }
        } else {
            favoriteWatchedFolders = decodedFavorites
        }
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
    func increaseFontSize(step: Double)
    func decreaseFontSize(step: Double)
    func resetFontSize()
    func updateNotificationsEnabled(_ isEnabled: Bool)
    func updateMultiFileDisplayMode(_ mode: ReaderMultiFileDisplayMode)
    func updateSidebarSortMode(_ mode: ReaderSidebarSortMode)
    func updateSidebarGroupSortMode(_ mode: ReaderSidebarSortMode)
    func updateDiffBaselineLookback(_ lookback: DiffBaselineLookback)
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

    func increaseFontSize(step: Double = 1.0) {
        let next = currentSettings.baseFontSize + step
        updateBaseFontSize(next)
    }

    func decreaseFontSize(step: Double = 1.0) {
        let next = currentSettings.baseFontSize - step
        updateBaseFontSize(next)
    }

    func resetFontSize() {
        updateBaseFontSize(ReaderSettings.default.baseFontSize)
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

    func updateDiffBaselineLookback(_ lookback: DiffBaselineLookback) {
        updateSettings(coalescePersistence: true) { settings in
            settings.diffBaselineLookback = lookback
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
