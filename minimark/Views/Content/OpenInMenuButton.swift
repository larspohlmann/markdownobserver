import AppKit
import SwiftUI

@MainActor
func appIconImage(for app: ExternalApplication) -> NSImage? {
    let iconPath: String
    if let bundleIdentifier = app.bundleIdentifier,
       let installedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
        iconPath = installedURL.path
    } else {
        iconPath = app.bundleURL.path
    }

    guard FileManager.default.fileExists(atPath: iconPath) else {
        return NSImage(systemSymbolName: "app", accessibilityDescription: "App")
    }

    let icon = NSWorkspace.shared.icon(forFile: iconPath)
    icon.size = NSSize(width: 16, height: 16)
    icon.isTemplate = false
    return icon
}

enum OpenInMenuAction {
    case openFiles([URL])
    case openInApp(ExternalApplication)
    case revealInFinder
    case requestFolderWatch(URL)
    case stopFolderWatch
    case startFavoriteWatch(FavoriteWatchedFolder)
    case clearFavoriteWatchedFolders
    case editFavoriteWatchedFolders
    case startRecentManuallyOpenedFile(RecentOpenedFile)
    case startRecentFolderWatch(RecentWatchedFolder)
    case clearRecentWatchedFolders
    case clearRecentManuallyOpenedFiles
}

struct OpenInMenuButton: NSViewRepresentable {
    let hasFile: Bool
    let hasActiveFolderWatch: Bool
    let apps: [ExternalApplication]
    let favoriteWatchedFolders: [FavoriteWatchedFolder]
    let recentWatchedFolders: [RecentWatchedFolder]
    let recentManuallyOpenedFiles: [RecentOpenedFile]
    let iconProvider: (ExternalApplication) -> NSImage?
    let onAction: (OpenInMenuAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More actions")
        button.contentTintColor = .labelColor
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
        button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        button.layer?.masksToBounds = true
        button.setAccessibilityLabel("Open in and watch actions")
        button.toolTip = "Open a file, choose an app, reveal in Finder, or manage folder watch"
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.appByID = apps.reduce(into: [:]) { result, app in
            result[app.id] = app
        }
        button.alphaValue = hasFile ? 1 : 0.9
        button.layer?.backgroundColor = hasFile
            ? NSColor.labelColor.withAlphaComponent(0.09).cgColor
            : NSColor.labelColor.withAlphaComponent(0.06).cgColor
        button.layer?.borderColor = NSColor.labelColor.withAlphaComponent(hasFile ? 0.14 : 0.10).cgColor
    }

    final class Coordinator: NSObject {
        var parent: OpenInMenuButton
        var appByID: [String: ExternalApplication] = [:]
        weak var button: NSButton?

        init(parent: OpenInMenuButton) {
            self.parent = parent
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()

            let openFile = NSMenuItem(title: "Open File(s)...", action: #selector(openFileFromPicker), keyEquivalent: "")
            openFile.target = self
            menu.addItem(openFile)

            menu.addItem(makeRecentFilesMenuItem())

            menu.addItem(.separator())

            let heading = NSMenuItem(title: "Open in:", action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            menu.addItem(.separator())

            if parent.hasFile {
                if parent.apps.isEmpty {
                    let empty = NSMenuItem(title: "No compatible apps found", action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                    menu.addItem(empty)
                } else {
                    for app in parent.apps {
                        let item = NSMenuItem(title: app.displayName, action: #selector(openApp(_:)), keyEquivalent: "")
                        item.target = self
                        item.representedObject = app.id
                        if let icon = parent.iconProvider(app) {
                            icon.size = NSSize(width: 16, height: 16)
                            icon.isTemplate = false
                            item.image = icon
                        }
                        menu.addItem(item)
                    }
                }

                menu.addItem(.separator())

                let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
                reveal.target = self
                menu.addItem(reveal)
            } else {
                let noFile = NSMenuItem(title: "No file selected", action: nil, keyEquivalent: "")
                noFile.isEnabled = false
                menu.addItem(noFile)
                menu.addItem(.separator())

                let reveal = NSMenuItem(title: "Reveal in Finder", action: nil, keyEquivalent: "")
                reveal.isEnabled = false
                menu.addItem(reveal)
            }

            menu.addItem(.separator())

            let watchFolder = NSMenuItem(title: "Watch Folder...", action: #selector(watchFolderFromPicker), keyEquivalent: "")
            watchFolder.target = self
            menu.addItem(watchFolder)

            menu.addItem(makeFavoriteWatchedFoldersMenuItem())

            menu.addItem(makeRecentWatchedFoldersMenuItem())

            let stopWatching = NSMenuItem(title: "Stop Watching Folder", action: #selector(stopWatchingFolder), keyEquivalent: "")
            stopWatching.target = self
            stopWatching.isEnabled = parent.hasActiveFolderWatch
            if !parent.hasActiveFolderWatch {
                stopWatching.action = nil
                stopWatching.target = nil
            }
            menu.addItem(stopWatching)

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: sender)
        }

        private func makeRecentFilesMenuItem() -> NSMenuItem {
            let item = NSMenuItem(title: "Recent Opened Files", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)
            let titlesByPath = ReaderRecentHistory.menuTitles(for: parent.recentManuallyOpenedFiles)

            if parent.recentManuallyOpenedFiles.isEmpty {
                let empty = NSMenuItem(title: "No recent manually opened files", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                for entry in parent.recentManuallyOpenedFiles {
                    let recentItem = NSMenuItem(
                        title: titlesByPath[entry.filePath] ?? entry.displayName,
                        action: #selector(openRecentFile(_:)),
                        keyEquivalent: ""
                    )
                    recentItem.target = self
                    recentItem.representedObject = entry.filePath
                    recentItem.toolTip = entry.pathText
                    submenu.addItem(recentItem)
                }

                submenu.addItem(.separator())
            }

            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearRecentFiles), keyEquivalent: "")
            clearItem.target = self
            clearItem.isEnabled = !parent.recentManuallyOpenedFiles.isEmpty
            submenu.addItem(clearItem)

            item.submenu = submenu
            return item
        }

        private func makeFavoriteWatchedFoldersMenuItem() -> NSMenuItem {
            let item = NSMenuItem(title: "Favorite Watched Folders", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)

            if parent.favoriteWatchedFolders.isEmpty {
                let empty = NSMenuItem(title: "No favorite watched folders", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                for entry in parent.favoriteWatchedFolders {
                    let favoriteItem = NSMenuItem(
                        title: entry.name,
                        action: #selector(startFavoriteWatch(_:)),
                        keyEquivalent: ""
                    )
                    favoriteItem.target = self
                    favoriteItem.representedObject = entry.id.uuidString
                    favoriteItem.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: "Favorite")
                    favoriteItem.image?.isTemplate = true
                    favoriteItem.toolTip = [
                        entry.pathText,
                        "When watch starts: \(entry.options.openMode.label)",
                        "Scope: \(entry.options.scope.label)"
                    ].joined(separator: "\n")
                    submenu.addItem(favoriteItem)
                }

                submenu.addItem(.separator())
            }

            let editItem = NSMenuItem(title: "Edit Favorites\u{2026}", action: #selector(editFavoriteWatchedFolders), keyEquivalent: "")
            editItem.target = self
            editItem.isEnabled = !parent.favoriteWatchedFolders.isEmpty
            submenu.addItem(editItem)

            let clearItem = NSMenuItem(title: "Clear Favorites", action: #selector(clearFavoriteWatchedFolders), keyEquivalent: "")
            clearItem.target = self
            clearItem.isEnabled = !parent.favoriteWatchedFolders.isEmpty
            submenu.addItem(clearItem)

            item.submenu = submenu
            return item
        }

        private func makeRecentWatchedFoldersMenuItem() -> NSMenuItem {
            let item = NSMenuItem(title: "Recent Watched Folders", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)
            let titlesByPath = ReaderRecentHistory.menuTitles(for: parent.recentWatchedFolders)

            if parent.recentWatchedFolders.isEmpty {
                let empty = NSMenuItem(title: "No recent watched folders", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            } else {
                for entry in parent.recentWatchedFolders {
                    let recentItem = NSMenuItem(
                        title: titlesByPath[entry.folderPath] ?? entry.displayName,
                        action: #selector(startRecentFolderWatch(_:)),
                        keyEquivalent: ""
                    )
                    recentItem.target = self
                    recentItem.representedObject = entry.folderPath
                    recentItem.toolTip = [
                        entry.pathText,
                        "When watch starts: \(entry.options.openMode.label)",
                        "Scope: \(entry.options.scope.label)"
                    ].joined(separator: "\n")
                    submenu.addItem(recentItem)
                }

                submenu.addItem(.separator())
            }

            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearRecentWatchedFolders), keyEquivalent: "")
            clearItem.target = self
            clearItem.isEnabled = !parent.recentWatchedFolders.isEmpty
            submenu.addItem(clearItem)

            item.submenu = submenu
            return item
        }

        @objc private func openApp(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let app = appByID[id] else {
                return
            }
            parent.onAction(.openInApp(app))
        }

        @objc private func openFileFromPicker() {
            guard let fileURLs = MarkdownOpenPanel.pickFiles(allowsMultipleSelection: true) else {
                return
            }

            parent.onAction(.openFiles(fileURLs))
        }

        @objc private func openRecentFile(_ sender: NSMenuItem) {
            guard let filePath = sender.representedObject as? String,
                  let entry = parent.recentManuallyOpenedFiles.first(where: { $0.filePath == filePath }) else {
                return
            }

            parent.onAction(.startRecentManuallyOpenedFile(entry))
        }

        @objc private func revealInFinder() {
            parent.onAction(.revealInFinder)
        }

        @objc private func watchFolderFromPicker() {
            guard let folderURL = pickFolder() else {
                return
            }
            parent.onAction(.requestFolderWatch(folderURL))
        }

        @objc private func startRecentFolderWatch(_ sender: NSMenuItem) {
            guard let folderPath = sender.representedObject as? String,
                  let entry = parent.recentWatchedFolders.first(where: { $0.folderPath == folderPath }) else {
                return
            }

            parent.onAction(.startRecentFolderWatch(entry))
        }

        @objc private func stopWatchingFolder() {
            parent.onAction(.stopFolderWatch)
        }

        @objc private func clearRecentFiles() {
            parent.onAction(.clearRecentManuallyOpenedFiles)
        }

        @objc private func startFavoriteWatch(_ sender: NSMenuItem) {
            guard let idString = sender.representedObject as? String,
                  let id = UUID(uuidString: idString),
                  let entry = parent.favoriteWatchedFolders.first(where: { $0.id == id }) else {
                return
            }

            parent.onAction(.startFavoriteWatch(entry))
        }

        @objc private func editFavoriteWatchedFolders() {
            parent.onAction(.editFavoriteWatchedFolders)
        }

        @objc private func clearFavoriteWatchedFolders() {
            parent.onAction(.clearFavoriteWatchedFolders)
        }

        @objc private func clearRecentWatchedFolders() {
            parent.onAction(.clearRecentWatchedFolders)
        }

        private func pickFolder() -> URL? {
            MarkdownOpenPanel.pickFolder(
                title: "Choose Folder to Watch",
                message: "Select a folder, then choose watch options."
            )
        }
    }
}
