import AppKit
import Foundation

@MainActor
final class WindowRegistry {
    static let shared = WindowRegistry()

    private var windowByID: [ObjectIdentifier: WeakWindow] = [:]
    private var documentFocusHandlerByWindowID: [ObjectIdentifier: DocumentFocusHandler] = [:]
    private var watchedFolderURLProviderByWindowID: [ObjectIdentifier: WatchedFolderURLProvider] = [:]

    private init() {}

    func registerWindow(
        _ window: NSWindow?,
        focusDocument: @escaping (URL) -> Bool,
        watchedFolderURLProvider: @escaping () -> URL?
    ) {
        guard let window else {
            return
        }

        let windowID = ObjectIdentifier(window)
        windowByID[windowID] = WeakWindow(window)
        documentFocusHandlerByWindowID[windowID] = DocumentFocusHandler(focusDocument: focusDocument)
        watchedFolderURLProviderByWindowID[windowID] = WatchedFolderURLProvider(resolve: watchedFolderURLProvider)
        cleanupDeadWindows()
    }

    func unregisterWindow(_ window: NSWindow?) {
        guard let window else {
            return
        }

        let windowID = ObjectIdentifier(window)
        windowByID.removeValue(forKey: windowID)
        documentFocusHandlerByWindowID.removeValue(forKey: windowID)
        watchedFolderURLProviderByWindowID.removeValue(forKey: windowID)
    }

    @discardableResult
    func focusDocumentIfAlreadyOpen(at fileURL: URL) -> Bool {
        let normalizedURL = FileRouting.normalizedFileURL(fileURL)

        for windowID in prioritizedWindowIDs() {
            guard let window = windowByID[windowID]?.window,
                  let focusHandler = documentFocusHandlerByWindowID[windowID] else {
                continue
            }

            if focusHandler.focusDocument(normalizedURL) {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }

        cleanupDeadWindows()
        return false
    }

    @discardableResult
    func focusNotificationTarget(fileURL: URL?, watchedFolderURL: URL?) -> Bool {
        if let fileURL,
           focusDocumentIfAlreadyOpen(at: fileURL) {
            return true
        }

        guard let watchedFolderURL else {
            return false
        }

        let normalizedWatchedFolderURL = FileRouting.normalizedFileURL(watchedFolderURL)
        for windowID in prioritizedWindowIDs() {
            guard let window = windowByID[windowID]?.window,
                  let watchedFolderProvider = watchedFolderURLProviderByWindowID[windowID],
                  let currentWatchedFolderURL = watchedFolderProvider.resolve() else {
                continue
            }

            if FileRouting.normalizedFileURL(currentWatchedFolderURL) == normalizedWatchedFolderURL {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }

        cleanupDeadWindows()
        return false
    }

    func resetForTesting() {
        windowByID.removeAll()
        documentFocusHandlerByWindowID.removeAll()
        watchedFolderURLProviderByWindowID.removeAll()
    }

    private func prioritizedWindowIDs() -> [ObjectIdentifier] {
        cleanupDeadWindows()

        var orderedWindowIDs: [ObjectIdentifier] = []

        if let keyWindow = NSApp.keyWindow {
            orderedWindowIDs.append(ObjectIdentifier(keyWindow))
        }

        if let mainWindow = NSApp.mainWindow {
            let mainWindowID = ObjectIdentifier(mainWindow)
            if !orderedWindowIDs.contains(mainWindowID) {
                orderedWindowIDs.append(mainWindowID)
            }
        }

        for windowID in documentFocusHandlerByWindowID.keys where !orderedWindowIDs.contains(windowID) {
            orderedWindowIDs.append(windowID)
        }

        return orderedWindowIDs
    }

    private func cleanupDeadWindows() {
        let deadWindowIDs = windowByID.compactMap { windowID, weakWindow in
            weakWindow.window == nil ? windowID : nil
        }

        for windowID in deadWindowIDs {
            windowByID.removeValue(forKey: windowID)
            documentFocusHandlerByWindowID.removeValue(forKey: windowID)
            watchedFolderURLProviderByWindowID.removeValue(forKey: windowID)
        }
    }
}

private struct WeakWindow {
    weak var window: NSWindow?

    init(_ window: NSWindow) {
        self.window = window
    }
}

private struct DocumentFocusHandler {
    let focusDocument: (URL) -> Bool
}

private struct WatchedFolderURLProvider {
    let resolve: () -> URL?
}