import Foundation

nonisolated struct FolderWatchDirectoryScanCacheKey: Hashable, Sendable {
    let folderPath: String
    let folderFingerprint: String
}

nonisolated private struct FolderWatchDirectoryScanCacheEntry: Sendable {
    let result: FolderWatchDirectoryScanResult
    let insertedAt: Date
}

actor FolderWatchDirectoryScanCache {
    private let maximumEntries = 4
    private let maximumEntryAge: TimeInterval = 30
    private var entriesByKey: [FolderWatchDirectoryScanCacheKey: FolderWatchDirectoryScanCacheEntry] = [:]
    private var keyOrder: [FolderWatchDirectoryScanCacheKey] = []

    func cachedResult(for key: FolderWatchDirectoryScanCacheKey) -> FolderWatchDirectoryScanResult? {
        guard let entry = entriesByKey[key] else {
            return nil
        }

        if Date().timeIntervalSince(entry.insertedAt) > maximumEntryAge {
            remove(key)
            return nil
        }

        touch(key)
        return entry.result
    }

    func store(_ result: FolderWatchDirectoryScanResult, for key: FolderWatchDirectoryScanCacheKey) {
        entriesByKey[key] = FolderWatchDirectoryScanCacheEntry(result: result, insertedAt: Date())
        touch(key)

        while keyOrder.count > maximumEntries,
              let oldestKey = keyOrder.first {
            keyOrder.removeFirst()
            entriesByKey.removeValue(forKey: oldestKey)
        }
    }

    private func remove(_ key: FolderWatchDirectoryScanCacheKey) {
        entriesByKey.removeValue(forKey: key)
        keyOrder.removeAll(where: { $0 == key })
    }

    private func touch(_ key: FolderWatchDirectoryScanCacheKey) {
        keyOrder.removeAll(where: { $0 == key })
        keyOrder.append(key)
    }
}
