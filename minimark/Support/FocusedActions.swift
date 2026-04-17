import Foundation
import SwiftUI

enum CommandNotification {
    static let openRecentFile = Notification.Name("minimark.openRecentFile")
    static let prepareRecentWatchedFolder = Notification.Name("minimark.prepareRecentWatchedFolder")

    struct Payload {
        let targetWindowNumber: Int
        let recentFileEntry: RecentOpenedFile?
        let recentWatchedFolderEntry: RecentWatchedFolder?

        init(targetWindowNumber: Int, recentFileEntry: RecentOpenedFile) {
            self.targetWindowNumber = targetWindowNumber
            self.recentFileEntry = recentFileEntry
            self.recentWatchedFolderEntry = nil
        }

        init(targetWindowNumber: Int, recentWatchedFolderEntry: RecentWatchedFolder) {
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
            self.recentFileEntry = userInfo[Keys.recentFileEntry] as? RecentOpenedFile
            self.recentWatchedFolderEntry = userInfo[Keys.recentWatchedFolderEntry] as? RecentWatchedFolder
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

enum ChangedRegionNavigationDirection: String, Sendable {
    case previous
    case next
}

struct ChangedRegionNavigationAction {
    let canNavigate: Bool
    let navigate: (ChangedRegionNavigationDirection) -> Void

    func callAsFunction(_ direction: ChangedRegionNavigationDirection) {
        guard canNavigate else {
            return
        }

        navigate(direction)
    }
}

struct WatchFolderAction {
    let openOptions: (URL) -> Void

    func callAsFunction(_ url: URL) {
        openOptions(url)
    }
}

struct StartRecentFolderWatchAction {
    let start: (RecentWatchedFolder) -> Void

    func callAsFunction(_ entry: RecentWatchedFolder) {
        start(entry)
    }
}

struct StopFolderWatchAction {
    let stop: () -> Void

    func callAsFunction() {
        stop()
    }
}

struct OpenDocumentInCurrentWindowAction {
    let open: (URL) -> Void

    func callAsFunction(_ url: URL) {
        open(url)
    }
}

struct OpenDocumentAction {
    let open: (URL) -> Void

    func callAsFunction(_ url: URL) {
        open(url)
    }
}

struct OpenAdditionalDocumentAction {
    let open: (URL) -> Void

    func callAsFunction(_ url: URL) {
        open(url)
    }
}

struct DocumentViewModeContext {
    let currentMode: DocumentViewMode
    let canSetMode: Bool
    let setMode: (DocumentViewMode) -> Void
    let toggleMode: () -> Void
}

struct SourceEditingContext {
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

struct ToggleTOCAction {
    let canToggle: Bool
    let toggle: () -> Void

    func callAsFunction() {
        guard canToggle else { return }
        toggle()
    }
}

private struct OpenDocumentInCurrentWindowActionKey: FocusedValueKey {
    typealias Value = OpenDocumentInCurrentWindowAction
}

private struct WatchFolderActionKey: FocusedValueKey {
    typealias Value = WatchFolderAction
}

private struct StartRecentFolderWatchActionKey: FocusedValueKey {
    typealias Value = StartRecentFolderWatchAction
}

private struct StopFolderWatchActionKey: FocusedValueKey {
    typealias Value = StopFolderWatchAction
}

private struct HasActiveFolderWatchKey: FocusedValueKey {
    typealias Value = Bool
}

private struct OpenDocumentActionKey: FocusedValueKey {
    typealias Value = OpenDocumentAction
}

private struct OpenAdditionalDocumentActionKey: FocusedValueKey {
    typealias Value = OpenAdditionalDocumentAction
}

private struct DocumentViewModeContextKey: FocusedValueKey {
    typealias Value = DocumentViewModeContext
}

private struct ChangedRegionNavigationActionKey: FocusedValueKey {
    typealias Value = ChangedRegionNavigationAction
}

private struct SourceEditingContextKey: FocusedValueKey {
    typealias Value = SourceEditingContext
}

private struct ToggleTOCActionKey: FocusedValueKey {
    typealias Value = ToggleTOCAction
}

extension FocusedValues {
    var openDocument: OpenDocumentAction? {
        get { self[OpenDocumentActionKey.self] }
        set { self[OpenDocumentActionKey.self] = newValue }
    }

    var openDocumentInCurrentWindow: OpenDocumentInCurrentWindowAction? {
        get { self[OpenDocumentInCurrentWindowActionKey.self] }
        set { self[OpenDocumentInCurrentWindowActionKey.self] = newValue }
    }

    var watchFolder: WatchFolderAction? {
        get { self[WatchFolderActionKey.self] }
        set { self[WatchFolderActionKey.self] = newValue }
    }

    var startRecentFolderWatch: StartRecentFolderWatchAction? {
        get { self[StartRecentFolderWatchActionKey.self] }
        set { self[StartRecentFolderWatchActionKey.self] = newValue }
    }

    var stopFolderWatch: StopFolderWatchAction? {
        get { self[StopFolderWatchActionKey.self] }
        set { self[StopFolderWatchActionKey.self] = newValue }
    }

    var hasActiveFolderWatch: Bool? {
        get { self[HasActiveFolderWatchKey.self] }
        set { self[HasActiveFolderWatchKey.self] = newValue }
    }

    var openAdditionalDocument: OpenAdditionalDocumentAction? {
        get { self[OpenAdditionalDocumentActionKey.self] }
        set { self[OpenAdditionalDocumentActionKey.self] = newValue }
    }

    var documentViewModeContext: DocumentViewModeContext? {
        get { self[DocumentViewModeContextKey.self] }
        set { self[DocumentViewModeContextKey.self] = newValue }
    }

    var changedRegionNavigation: ChangedRegionNavigationAction? {
        get { self[ChangedRegionNavigationActionKey.self] }
        set { self[ChangedRegionNavigationActionKey.self] = newValue }
    }

    var sourceEditingContext: SourceEditingContext? {
        get { self[SourceEditingContextKey.self] }
        set { self[SourceEditingContextKey.self] = newValue }
    }

    var toggleTOC: ToggleTOCAction? {
        get { self[ToggleTOCActionKey.self] }
        set { self[ToggleTOCActionKey.self] = newValue }
    }
}
