import Foundation
import SwiftUI

enum ReaderCommandNotification {
    static let openRecentFile = Notification.Name("minimark.openRecentFile")
    static let prepareRecentWatchedFolder = Notification.Name("minimark.prepareRecentWatchedFolder")

    struct Payload {
        let targetWindowNumber: Int
        let recentFileEntry: ReaderRecentOpenedFile?
        let recentWatchedFolderEntry: ReaderRecentWatchedFolder?

        init(targetWindowNumber: Int, recentFileEntry: ReaderRecentOpenedFile) {
            self.targetWindowNumber = targetWindowNumber
            self.recentFileEntry = recentFileEntry
            self.recentWatchedFolderEntry = nil
        }

        init(targetWindowNumber: Int, recentWatchedFolderEntry: ReaderRecentWatchedFolder) {
            self.targetWindowNumber = targetWindowNumber
            self.recentFileEntry = nil
            self.recentWatchedFolderEntry = recentWatchedFolderEntry
        }

        init?(notification: Notification) {
            guard let userInfo = notification.userInfo,
                  let targetWindowNumber = userInfo[Keys.targetWindowNumber] as? Int else {
                return nil
            }
            self.targetWindowNumber = targetWindowNumber
            self.recentFileEntry = userInfo[Keys.recentFileEntry] as? ReaderRecentOpenedFile
            self.recentWatchedFolderEntry = userInfo[Keys.recentWatchedFolderEntry] as? ReaderRecentWatchedFolder
        }

        var asUserInfo: [String: Any] {
            var info: [String: Any] = [Keys.targetWindowNumber: targetWindowNumber]
            if let recentFileEntry {
                info[Keys.recentFileEntry] = recentFileEntry
            }
            if let recentWatchedFolderEntry {
                info[Keys.recentWatchedFolderEntry] = recentWatchedFolderEntry
            }
            return info
        }

        private enum Keys {
            static let targetWindowNumber = "targetWindowNumber"
            static let recentFileEntry = "recentFileEntry"
            static let recentWatchedFolderEntry = "recentWatchedFolderEntry"
        }
    }
}

enum ReaderChangedRegionNavigationDirection: String, Sendable {
    case previous
    case next
}

struct ReaderChangedRegionNavigationAction {
    let canNavigate: Bool
    let navigate: (ReaderChangedRegionNavigationDirection) -> Void

    func callAsFunction(_ direction: ReaderChangedRegionNavigationDirection) {
        guard canNavigate else {
            return
        }

        navigate(direction)
    }
}

struct ReaderWatchFolderAction {
    let openOptions: (URL) -> Void

    func callAsFunction(_ url: URL) {
        openOptions(url)
    }
}

struct ReaderStartRecentFolderWatchAction {
    let start: (ReaderRecentWatchedFolder) -> Void

    func callAsFunction(_ entry: ReaderRecentWatchedFolder) {
        start(entry)
    }
}

struct ReaderStopFolderWatchAction {
    let stop: () -> Void

    func callAsFunction() {
        stop()
    }
}

struct ReaderOpenDocumentInCurrentWindowAction {
    let open: (URL) -> Void

    func callAsFunction(_ url: URL) {
        open(url)
    }
}

struct ReaderOpenDocumentAction {
    let open: (URL) -> Void

    func callAsFunction(_ url: URL) {
        open(url)
    }
}

struct ReaderOpenAdditionalDocumentAction {
    let open: (URL) -> Void

    func callAsFunction(_ url: URL) {
        open(url)
    }
}

struct ReaderDocumentViewModeContext {
    let currentMode: ReaderDocumentViewMode
    let canSetMode: Bool
    let setMode: (ReaderDocumentViewMode) -> Void
    let toggleMode: () -> Void
}

struct ReaderSourceEditingContext {
    let canStartEditing: Bool
    let canSave: Bool
    let canDiscard: Bool
    let startEditing: () -> Void
    let save: () -> Void
    let discard: () -> Void

    func startIfAvailable() {
        guard canStartEditing else {
            return
        }

        startEditing()
    }

    func saveIfAvailable() {
        guard canSave else {
            return
        }

        save()
    }

    func discardIfAvailable() {
        guard canDiscard else {
            return
        }

        discard()
    }
}

private struct ReaderOpenDocumentInCurrentWindowActionKey: FocusedValueKey {
    typealias Value = ReaderOpenDocumentInCurrentWindowAction
}

private struct ReaderWatchFolderActionKey: FocusedValueKey {
    typealias Value = ReaderWatchFolderAction
}

private struct ReaderStartRecentFolderWatchActionKey: FocusedValueKey {
    typealias Value = ReaderStartRecentFolderWatchAction
}

private struct ReaderStopFolderWatchActionKey: FocusedValueKey {
    typealias Value = ReaderStopFolderWatchAction
}

private struct ReaderHasActiveFolderWatchKey: FocusedValueKey {
    typealias Value = Bool
}

private struct ReaderOpenDocumentActionKey: FocusedValueKey {
    typealias Value = ReaderOpenDocumentAction
}

private struct ReaderOpenAdditionalDocumentActionKey: FocusedValueKey {
    typealias Value = ReaderOpenAdditionalDocumentAction
}

private struct ReaderDocumentViewModeContextKey: FocusedValueKey {
    typealias Value = ReaderDocumentViewModeContext
}

private struct ReaderChangedRegionNavigationActionKey: FocusedValueKey {
    typealias Value = ReaderChangedRegionNavigationAction
}

private struct ReaderSourceEditingContextKey: FocusedValueKey {
    typealias Value = ReaderSourceEditingContext
}

extension FocusedValues {
    var readerOpenDocument: ReaderOpenDocumentAction? {
        get { self[ReaderOpenDocumentActionKey.self] }
        set { self[ReaderOpenDocumentActionKey.self] = newValue }
    }

    var readerOpenDocumentInCurrentWindow: ReaderOpenDocumentInCurrentWindowAction? {
        get { self[ReaderOpenDocumentInCurrentWindowActionKey.self] }
        set { self[ReaderOpenDocumentInCurrentWindowActionKey.self] = newValue }
    }

    var readerWatchFolder: ReaderWatchFolderAction? {
        get { self[ReaderWatchFolderActionKey.self] }
        set { self[ReaderWatchFolderActionKey.self] = newValue }
    }

    var readerStartRecentFolderWatch: ReaderStartRecentFolderWatchAction? {
        get { self[ReaderStartRecentFolderWatchActionKey.self] }
        set { self[ReaderStartRecentFolderWatchActionKey.self] = newValue }
    }

    var readerStopFolderWatch: ReaderStopFolderWatchAction? {
        get { self[ReaderStopFolderWatchActionKey.self] }
        set { self[ReaderStopFolderWatchActionKey.self] = newValue }
    }

    var readerHasActiveFolderWatch: Bool? {
        get { self[ReaderHasActiveFolderWatchKey.self] }
        set { self[ReaderHasActiveFolderWatchKey.self] = newValue }
    }

    var readerOpenAdditionalDocument: ReaderOpenAdditionalDocumentAction? {
        get { self[ReaderOpenAdditionalDocumentActionKey.self] }
        set { self[ReaderOpenAdditionalDocumentActionKey.self] = newValue }
    }

    var readerDocumentViewModeContext: ReaderDocumentViewModeContext? {
        get { self[ReaderDocumentViewModeContextKey.self] }
        set { self[ReaderDocumentViewModeContextKey.self] = newValue }
    }

    var readerChangedRegionNavigation: ReaderChangedRegionNavigationAction? {
        get { self[ReaderChangedRegionNavigationActionKey.self] }
        set { self[ReaderChangedRegionNavigationActionKey.self] = newValue }
    }

    var readerSourceEditingContext: ReaderSourceEditingContext? {
        get { self[ReaderSourceEditingContextKey.self] }
        set { self[ReaderSourceEditingContextKey.self] = newValue }
    }
}
