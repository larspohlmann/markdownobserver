import Foundation
import Combine
import Observation
import OSLog

nonisolated struct ReaderSettings: Equatable, Codable, Sendable {
    var appAppearance: AppAppearance
    var readerTheme: ThemeKind
    var syntaxTheme: SyntaxThemeKind
    var baseFontSize: Double
    var autoRefreshOnExternalChange: Bool
    var notificationsEnabled: Bool
    var multiFileDisplayMode: MultiFileDisplayMode
    var sidebarSortMode: SidebarSortMode
    var sidebarGroupSortMode: SidebarSortMode
    var favoriteWatchedFolders: [FavoriteWatchedFolder]
    var recentWatchedFolders: [RecentWatchedFolder]
    var recentManuallyOpenedFiles: [RecentOpenedFile]
    var trustedImageFolders: [TrustedImageFolder]
    var diffBaselineLookback: DiffBaselineLookback
    var dismissedHints: Set<FirstUseHint>

    init(
        appAppearance: AppAppearance,
        readerTheme: ThemeKind,
        syntaxTheme: SyntaxThemeKind,
        baseFontSize: Double,
        autoRefreshOnExternalChange: Bool,
        notificationsEnabled: Bool,
        multiFileDisplayMode: MultiFileDisplayMode,
        sidebarSortMode: SidebarSortMode,
        sidebarGroupSortMode: SidebarSortMode = .lastChangedNewestFirst,
        favoriteWatchedFolders: [FavoriteWatchedFolder] = [],
        recentWatchedFolders: [RecentWatchedFolder],
        recentManuallyOpenedFiles: [RecentOpenedFile],
        trustedImageFolders: [TrustedImageFolder] = [],
        diffBaselineLookback: DiffBaselineLookback = .twoMinutes,
        dismissedHints: Set<FirstUseHint> = []
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
        self.dismissedHints = dismissedHints
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
        case dismissedHints
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
        diffBaselineLookback: .twoMinutes,
        dismissedHints: []
    )

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appAppearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appAppearance) ?? .system
        readerTheme = try container.decode(ThemeKind.self, forKey: .readerTheme)
        syntaxTheme = try container.decode(SyntaxThemeKind.self, forKey: .syntaxTheme)
        baseFontSize = try container.decode(Double.self, forKey: .baseFontSize)
        autoRefreshOnExternalChange = try container.decode(Bool.self, forKey: .autoRefreshOnExternalChange)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        multiFileDisplayMode = try container.decode(MultiFileDisplayMode.self, forKey: .multiFileDisplayMode)
        sidebarSortMode = try container.decodeIfPresent(SidebarSortMode.self, forKey: .sidebarSortMode) ?? .openOrder
        sidebarGroupSortMode = try container.decodeIfPresent(SidebarSortMode.self, forKey: .sidebarGroupSortMode) ?? .lastChangedNewestFirst
        let decodedFavorites = try container.decodeIfPresent([FavoriteWatchedFolder].self, forKey: .favoriteWatchedFolders) ?? []
        recentWatchedFolders = try container.decodeIfPresent([RecentWatchedFolder].self, forKey: .recentWatchedFolders) ?? []
        recentManuallyOpenedFiles = try container.decodeIfPresent([RecentOpenedFile].self, forKey: .recentManuallyOpenedFiles) ?? []
        trustedImageFolders = try container.decodeIfPresent([TrustedImageFolder].self, forKey: .trustedImageFolders) ?? []
        diffBaselineLookback = try container.decodeIfPresent(DiffBaselineLookback.self, forKey: .diffBaselineLookback) ?? .twoMinutes
        dismissedHints = try container.decodeIfPresent(Set<FirstUseHint>.self, forKey: .dismissedHints) ?? []

        // Migrate legacy favorites: replace hardcoded-default workspace state with decoded global settings
        let legacyDefaultState = FavoriteWorkspaceState.from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: FavoriteWorkspaceState.defaultSidebarWidth
        )
        let globalWorkspaceState = FavoriteWorkspaceState(
            fileSortMode: sidebarSortMode,
            groupSortMode: sidebarGroupSortMode,
            sidebarPosition: multiFileDisplayMode,
            sidebarWidth: FavoriteWorkspaceState.defaultSidebarWidth,
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
    func isHintDismissed(_ hint: FirstUseHint) -> Bool
}

@MainActor protocol ReaderThemeWriting: AnyObject {
    func updateAppAppearance(_ appearance: AppAppearance)
    func updateTheme(_ kind: ThemeKind)
    func updateSyntaxTheme(_ kind: SyntaxThemeKind)
    func updateBaseFontSize(_ value: Double)
    func increaseFontSize(step: Double)
    func decreaseFontSize(step: Double)
    func resetFontSize()
}

@MainActor protocol ReaderPreferencesWriting: AnyObject {
    func updateNotificationsEnabled(_ isEnabled: Bool)
    func updateMultiFileDisplayMode(_ mode: MultiFileDisplayMode)
    func updateSidebarSortMode(_ mode: SidebarSortMode)
    func updateSidebarGroupSortMode(_ mode: SidebarSortMode)
    func updateDiffBaselineLookback(_ lookback: DiffBaselineLookback)
}

@MainActor protocol ReaderFavoriteWriting: AnyObject {
    func addFavoriteWatchedFolder(
        name: String,
        folderURL: URL,
        options: FolderWatchOptions,
        openDocumentFileURLs: [URL],
        workspaceState: FavoriteWorkspaceState
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
    func updateFavoriteWorkspaceState(id: UUID, workspaceState: FavoriteWorkspaceState)
    func resolvedFavoriteWatchedFolderURL(for entry: FavoriteWatchedFolder) -> URL
    func clearFavoriteWatchedFolders()
    func reorderFavoriteWatchedFolders(orderedIDs: [UUID])
    func updateFavoriteWatchedFolderExclusions(id: UUID, excludedSubdirectoryPaths: [String])
}

@MainActor protocol ReaderRecentWatchedFolderWriting: AnyObject {
    func addRecentWatchedFolder(_ folderURL: URL, options: FolderWatchOptions)
    func resolvedRecentWatchedFolderURL(matching folderURL: URL) -> URL?
    func clearRecentWatchedFolders()
}

@MainActor protocol ReaderRecentOpenedFileWriting: AnyObject {
    func addRecentManuallyOpenedFile(_ fileURL: URL)
    func resolvedRecentManuallyOpenedFileURL(matching fileURL: URL) -> URL?
    func clearRecentManuallyOpenedFiles()
}

typealias ReaderRecentWriting = ReaderRecentWatchedFolderWriting & ReaderRecentOpenedFileWriting

@MainActor protocol ReaderTrustedFolderWriting: AnyObject {
    func addTrustedImageFolder(_ folderURL: URL)
    func resolvedTrustedImageFolderURL(containing fileURL: URL) -> URL?
}

@MainActor protocol ReaderHintWriting: AnyObject {
    func dismissHint(_ hint: FirstUseHint)
}

typealias ReaderSettingsWriting = ReaderThemeWriting
    & ReaderPreferencesWriting
    & ReaderFavoriteWriting
    & ReaderRecentWriting
    & ReaderTrustedFolderWriting
    & ReaderHintWriting

typealias ReaderSettingsStoring = ReaderSettingsReading & ReaderSettingsWriting

@MainActor @Observable final class ReaderSettingsStore: ReaderSettingsStoring, ChildStoreCoordinating {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ReaderSettingsStore"
    )

    typealias BookmarkResolution = (url: URL, isStale: Bool)
    typealias BookmarkResolver = (Data) throws -> BookmarkResolution
    typealias BookmarkCreator = (URL) throws -> Data

    var settingsPublisher: AnyPublisher<ReaderSettings, Never> {
        subject.eraseToAnyPublisher()
    }

    private(set) var currentSettings: ReaderSettings

    let preferences: ReaderPreferencesStore
    let favorites: FavoriteWatchedFoldersStore
    let recentWatchedFolders: RecentWatchedFoldersStore
    let recentOpenedFiles: RecentOpenedFilesStore
    let trustedImageFolders: TrustedImageFoldersStore

    @ObservationIgnored private let storage: ReaderSettingsKeyValueStoring
    @ObservationIgnored private let storageKey: String
    @ObservationIgnored private let subject: CurrentValueSubject<ReaderSettings, Never>
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private let minimumPersistInterval: TimeInterval
    @ObservationIgnored private var pendingPersistWorkItem: DispatchWorkItem?
    @ObservationIgnored private var lastPersistAt: Date = .distantPast

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
        self.minimumPersistInterval = max(0, minimumPersistInterval)

        let initialSettings: ReaderSettings
        if let data = storage.data(forKey: storageKey),
           let decoded = try? decoder.decode(ReaderSettings.self, from: data) {
            initialSettings = decoded
        } else {
            initialSettings = .default
        }

        let bookmarkRefreshing = BookmarkRefreshing(resolve: bookmarkResolver, create: bookmarkCreator)

        self.preferences = ReaderPreferencesStore(
            initial: ReaderPreferencesSlice(
                appAppearance: initialSettings.appAppearance,
                readerTheme: initialSettings.readerTheme,
                syntaxTheme: initialSettings.syntaxTheme,
                baseFontSize: initialSettings.baseFontSize,
                autoRefreshOnExternalChange: initialSettings.autoRefreshOnExternalChange,
                notificationsEnabled: initialSettings.notificationsEnabled,
                multiFileDisplayMode: initialSettings.multiFileDisplayMode,
                sidebarSortMode: initialSettings.sidebarSortMode,
                sidebarGroupSortMode: initialSettings.sidebarGroupSortMode,
                diffBaselineLookback: initialSettings.diffBaselineLookback,
                dismissedHints: initialSettings.dismissedHints
            )
        )
        self.favorites = FavoriteWatchedFoldersStore(
            initial: initialSettings.favoriteWatchedFolders,
            bookmarkRefreshing: bookmarkRefreshing
        )
        self.recentWatchedFolders = RecentWatchedFoldersStore(
            initial: initialSettings.recentWatchedFolders,
            bookmarkRefreshing: bookmarkRefreshing
        )
        self.recentOpenedFiles = RecentOpenedFilesStore(
            initial: initialSettings.recentManuallyOpenedFiles,
            bookmarkRefreshing: bookmarkRefreshing
        )
        self.trustedImageFolders = TrustedImageFoldersStore(
            initial: initialSettings.trustedImageFolders,
            bookmarkRefreshing: bookmarkRefreshing
        )

        self.subject = CurrentValueSubject(initialSettings)
        self.currentSettings = initialSettings

        self.preferences.coordinator = self
        self.favorites.coordinator = self
        self.recentWatchedFolders.coordinator = self
        self.recentOpenedFiles.coordinator = self
        self.trustedImageFolders.coordinator = self
    }

    // MARK: - ChildStoreCoordinating

    func childStoreDidMutate(coalescePersistence: Bool) {
        let updated = reassembleSettings()
        if updated != currentSettings {
            currentSettings = updated
            subject.send(updated)
        }
        if coalescePersistence {
            schedulePersist()
        } else {
            pendingPersistWorkItem?.cancel()
            pendingPersistWorkItem = nil
            persist()
        }
    }

    private func reassembleSettings() -> ReaderSettings {
        let prefs = preferences.currentPreferences
        return ReaderSettings(
            appAppearance: prefs.appAppearance,
            readerTheme: prefs.readerTheme,
            syntaxTheme: prefs.syntaxTheme,
            baseFontSize: prefs.baseFontSize,
            autoRefreshOnExternalChange: prefs.autoRefreshOnExternalChange,
            notificationsEnabled: prefs.notificationsEnabled,
            multiFileDisplayMode: prefs.multiFileDisplayMode,
            sidebarSortMode: prefs.sidebarSortMode,
            sidebarGroupSortMode: prefs.sidebarGroupSortMode,
            favoriteWatchedFolders: favorites.currentFavorites,
            recentWatchedFolders: recentWatchedFolders.currentRecentWatchedFolders,
            recentManuallyOpenedFiles: recentOpenedFiles.currentRecentOpenedFiles,
            trustedImageFolders: trustedImageFolders.currentTrustedFolders,
            diffBaselineLookback: prefs.diffBaselineLookback,
            dismissedHints: prefs.dismissedHints
        )
    }

    // MARK: - ReaderThemeWriting

    func updateAppAppearance(_ appearance: AppAppearance) { preferences.updateAppAppearance(appearance) }
    func updateTheme(_ kind: ThemeKind) { preferences.updateTheme(kind) }
    func updateSyntaxTheme(_ kind: SyntaxThemeKind) { preferences.updateSyntaxTheme(kind) }
    func updateBaseFontSize(_ value: Double) { preferences.updateBaseFontSize(value) }
    func increaseFontSize(step: Double = 1.0) { preferences.increaseFontSize(step: step) }
    func decreaseFontSize(step: Double = 1.0) { preferences.decreaseFontSize(step: step) }
    func resetFontSize() { preferences.resetFontSize() }

    // MARK: - ReaderPreferencesWriting

    func updateNotificationsEnabled(_ isEnabled: Bool) { preferences.updateNotificationsEnabled(isEnabled) }
    func updateMultiFileDisplayMode(_ mode: MultiFileDisplayMode) { preferences.updateMultiFileDisplayMode(mode) }
    func updateSidebarSortMode(_ mode: SidebarSortMode) { preferences.updateSidebarSortMode(mode) }
    func updateSidebarGroupSortMode(_ mode: SidebarSortMode) { preferences.updateSidebarGroupSortMode(mode) }
    func updateDiffBaselineLookback(_ lookback: DiffBaselineLookback) { preferences.updateDiffBaselineLookback(lookback) }

    // MARK: - ReaderHintWriting

    func isHintDismissed(_ hint: FirstUseHint) -> Bool { preferences.isHintDismissed(hint) }
    func dismissHint(_ hint: FirstUseHint) { preferences.dismissHint(hint) }

    // MARK: - ReaderFavoriteWriting

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
        favorites.addFavoriteWatchedFolder(
            name: name,
            folderURL: folderURL,
            options: options,
            openDocumentFileURLs: openDocumentFileURLs,
            workspaceState: workspaceState
        )
    }
    func removeFavoriteWatchedFolder(id: UUID) { favorites.removeFavoriteWatchedFolder(id: id) }
    func renameFavoriteWatchedFolder(id: UUID, newName: String) {
        favorites.renameFavoriteWatchedFolder(id: id, newName: newName)
    }
    func updateFavoriteWatchedFolderOpenDocuments(id: UUID, folderURL: URL, openDocumentFileURLs: [URL]) {
        favorites.updateFavoriteWatchedFolderOpenDocuments(
            id: id,
            folderURL: folderURL,
            openDocumentFileURLs: openDocumentFileURLs
        )
    }
    func updateFavoriteWatchedFolderKnownDocuments(id: UUID, folderURL: URL, knownDocumentFileURLs: [URL]) {
        favorites.updateFavoriteWatchedFolderKnownDocuments(
            id: id,
            folderURL: folderURL,
            knownDocumentFileURLs: knownDocumentFileURLs
        )
    }
    func updateFavoriteWorkspaceState(id: UUID, workspaceState: FavoriteWorkspaceState) {
        favorites.updateFavoriteWorkspaceState(id: id, workspaceState: workspaceState)
    }
    func resolvedFavoriteWatchedFolderURL(for entry: FavoriteWatchedFolder) -> URL {
        favorites.resolvedFavoriteWatchedFolderURL(for: entry)
    }
    func clearFavoriteWatchedFolders() { favorites.clearFavoriteWatchedFolders() }
    func reorderFavoriteWatchedFolders(orderedIDs: [UUID]) {
        favorites.reorderFavoriteWatchedFolders(orderedIDs: orderedIDs)
    }
    func updateFavoriteWatchedFolderExclusions(id: UUID, excludedSubdirectoryPaths: [String]) {
        favorites.updateFavoriteWatchedFolderExclusions(id: id, excludedSubdirectoryPaths: excludedSubdirectoryPaths)
    }

    // MARK: - ReaderRecentWatchedFolderWriting

    func addRecentWatchedFolder(_ folderURL: URL, options: FolderWatchOptions) {
        recentWatchedFolders.addRecentWatchedFolder(folderURL, options: options)
    }
    func resolvedRecentWatchedFolderURL(matching folderURL: URL) -> URL? {
        recentWatchedFolders.resolvedRecentWatchedFolderURL(matching: folderURL)
    }
    func clearRecentWatchedFolders() { recentWatchedFolders.clearRecentWatchedFolders() }

    // MARK: - ReaderRecentOpenedFileWriting

    func addRecentManuallyOpenedFile(_ fileURL: URL) {
        recentOpenedFiles.addRecentManuallyOpenedFile(fileURL)
    }
    func resolvedRecentManuallyOpenedFileURL(matching fileURL: URL) -> URL? {
        recentOpenedFiles.resolvedRecentManuallyOpenedFileURL(matching: fileURL)
    }
    func clearRecentManuallyOpenedFiles() { recentOpenedFiles.clearRecentManuallyOpenedFiles() }

    // MARK: - ReaderTrustedFolderWriting

    func addTrustedImageFolder(_ folderURL: URL) { trustedImageFolders.addTrustedImageFolder(folderURL) }
    func resolvedTrustedImageFolderURL(containing fileURL: URL) -> URL? {
        trustedImageFolders.resolvedTrustedImageFolderURL(containing: fileURL)
    }

    // MARK: - Persistence

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
            guard let self else { return }
            self.pendingPersistWorkItem = nil
            self.persist()
        }
        pendingPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func persist() {
        let data: Data
        do {
            data = try encoder.encode(subject.value)
        } catch {
            let nsError = error as NSError
            Self.logger.error(
                "settings persist encode failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .private)"
            )
            return
        }
        lastPersistAt = Date()
        storage.set(data, forKey: storageKey)
    }
}
