import AppKit
import Combine
import Foundation
import UserNotifications

struct ReaderUserNotificationSettings: Equatable, Sendable {
    let authorizationStatus: UNAuthorizationStatus
    let alertSetting: UNNotificationSetting
    let soundSetting: UNNotificationSetting
    let notificationCenterSetting: UNNotificationSetting
}

protocol ReaderUserNotificationCentering: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    )

    func notificationSettings(
        completionHandler: @escaping @Sendable (ReaderUserNotificationSettings) -> Void
    )

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    )
}

extension UNUserNotificationCenter: ReaderUserNotificationCentering {
    func notificationSettings(
        completionHandler: @escaping @Sendable (ReaderUserNotificationSettings) -> Void
    ) {
        getNotificationSettings { settings in
            completionHandler(
                ReaderUserNotificationSettings(
                    authorizationStatus: settings.authorizationStatus,
                    alertSetting: settings.alertSetting,
                    soundSetting: settings.soundSetting,
                    notificationCenterSetting: settings.notificationCenterSetting
                )
            )
        }
    }
}

protocol ReaderNotificationSettingsOpening {
    func openNotificationSettings()
}

struct ReaderSystemNotificationSettingsOpener: ReaderNotificationSettingsOpening {
    private static let notificationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    )

    func openNotificationSettings() {
        guard let notificationSettingsURL = Self.notificationSettingsURL,
              NSWorkspace.shared.open(notificationSettingsURL) else {
            return
        }
    }
}

enum ReaderNotificationAuthorizationState: Equatable {
    case notDetermined
    case denied
    case authorized
    case unknown

    init(_ authorizationStatus: UNAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized, .provisional, .ephemeral:
            self = .authorized
        @unknown default:
            self = .unknown
        }
    }
}

struct ReaderNotificationStatus: Equatable {
    let authorizationState: ReaderNotificationAuthorizationState
    let alertsEnabled: Bool
    let soundsEnabled: Bool
    let notificationCenterEnabled: Bool

    init(
        authorizationState: ReaderNotificationAuthorizationState,
        alertsEnabled: Bool,
        soundsEnabled: Bool,
        notificationCenterEnabled: Bool
    ) {
        self.authorizationState = authorizationState
        self.alertsEnabled = alertsEnabled
        self.soundsEnabled = soundsEnabled
        self.notificationCenterEnabled = notificationCenterEnabled
    }

    static let unknown = ReaderNotificationStatus(
        authorizationState: .unknown,
        alertsEnabled: false,
        soundsEnabled: false,
        notificationCenterEnabled: false
    )

    init(settings: ReaderUserNotificationSettings) {
        authorizationState = ReaderNotificationAuthorizationState(settings.authorizationStatus)
        alertsEnabled = settings.alertSetting == .enabled
        soundsEnabled = settings.soundSetting == .enabled
        notificationCenterEnabled = settings.notificationCenterSetting == .enabled
    }

    var isAuthorized: Bool {
        authorizationState == .authorized
    }

    var canRequestAuthorization: Bool {
        authorizationState == .notDetermined
    }

    var title: String {
        switch authorizationState {
        case .authorized:
            if alertsEnabled {
                return "Notifications are allowed"
            }
            return "Notifications are allowed, but alerts are off"
        case .denied:
            return "Notifications are turned off"
        case .notDetermined:
            return "Notification permission is not set"
        case .unknown:
            return "Notification status is unavailable"
        }
    }

    var message: String {
        switch authorizationState {
        case .authorized:
            if alertsEnabled {
                return "MarkdownObserver can post notifications. Banner style and whether they appear on the desktop are still controlled by macOS Notification Settings."
            }
            return "MarkdownObserver can add notifications to Notification Center, but desktop alerts are currently disabled in macOS Notification Settings."
        case .denied:
            return "Enable notifications for MarkdownObserver in macOS Notification Settings if you want desktop banners or Notification Center entries."
        case .notDetermined:
            return "Allow notifications to let MarkdownObserver send file-change and auto-open alerts while it stays in the background."
        case .unknown:
            return "Open macOS Notification Settings to verify alert delivery for MarkdownObserver."
        }
    }
}

private enum ReaderNotificationCopy {
    static let appName = "MarkdownObserver"
}

protocol ReaderSystemNotifying {
    func notifyFileAutoLoaded(
        _ fileURL: URL,
        changeKind: ReaderFolderWatchChangeKind,
        watchedFolderURL: URL?
    )
    func notifyExternalChange(for fileURL: URL, autoRefreshed: Bool, watchedFolderURL: URL?)
}

private enum ReaderSystemNotificationUserInfoKey {
    static let filePath = "filePath"
    static let watchedFolderPath = "watchedFolderPath"
}

private enum ReaderSystemNotificationEvent {
    case fileAutoLoaded(changeKind: ReaderFolderWatchChangeKind)
    case externalChange(autoRefreshed: Bool)

    var statusText: String {
        switch self {
        case .fileAutoLoaded(changeKind: .added):
            return "Opened automatically in \(ReaderNotificationCopy.appName)"
        case .fileAutoLoaded(changeKind: .modified):
            return "Updated and opened in \(ReaderNotificationCopy.appName)"
        case .externalChange(autoRefreshed: true):
            return "Reloaded after edits outside \(ReaderNotificationCopy.appName)"
        case .externalChange(autoRefreshed: false):
            return "Edited outside \(ReaderNotificationCopy.appName)"
        }
    }

    var folderlessSubtitle: String {
        switch self {
        case .fileAutoLoaded(changeKind: .added):
            return "New file"
        case .fileAutoLoaded(changeKind: .modified):
            return "Updated file"
        case .externalChange(autoRefreshed: true):
            return "External edit reloaded"
        case .externalChange(autoRefreshed: false):
            return "External edit detected"
        }
    }
}

private struct ReaderSystemNotificationDescriptor {
    let title: String
    let subtitle: String
    let body: String
    let userInfo: [AnyHashable: Any]

    init(
        title: String,
        subtitle: String,
        body: String,
        userInfo: [AnyHashable: Any]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.userInfo = userInfo
    }

    init(fileURL: URL, watchedFolderURL: URL?, event: ReaderSystemNotificationEvent) {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        let normalizedWatchedFolderURL = watchedFolderURL.map(ReaderFileRouting.normalizedFileURL)
        let fileName = normalizedFileURL.lastPathComponent
        let watchedFolderName = normalizedWatchedFolderURL.map(Self.displayName(for:))
        let parentFolderName = Self.displayName(for: normalizedFileURL.deletingLastPathComponent())

        title = fileName.isEmpty ? normalizedFileURL.path : fileName
        subtitle = watchedFolderName.map { "Folder watch: \($0)" } ?? event.folderlessSubtitle

        var bodyLines = [event.statusText]
        if watchedFolderName == nil {
            bodyLines.append("Folder: \(parentFolderName)")
        } else if watchedFolderName != parentFolderName {
            bodyLines.append("Subfolder: \(parentFolderName)")
        }
        body = bodyLines.joined(separator: "\n")

        var userInfo: [AnyHashable: Any] = [
            ReaderSystemNotificationUserInfoKey.filePath: normalizedFileURL.path
        ]
        if let normalizedWatchedFolderURL {
            userInfo[ReaderSystemNotificationUserInfoKey.watchedFolderPath] = normalizedWatchedFolderURL.path
        }
        self.userInfo = userInfo
    }

    private nonisolated static func displayName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }
}

protocol ReaderNotificationTargetFocusing {
    @discardableResult
    func focusNotificationTarget(fileURL: URL?, watchedFolderURL: URL?) -> Bool
}

struct ReaderNotificationTargetFocusCoordinator: ReaderNotificationTargetFocusing {
    @discardableResult
    func focusNotificationTarget(fileURL: URL?, watchedFolderURL: URL?) -> Bool {
        ReaderWindowRegistry.shared.focusNotificationTarget(
            fileURL: fileURL,
            watchedFolderURL: watchedFolderURL
        )
    }
}

final class ReaderSystemNotifier: NSObject, ObservableObject, ReaderSystemNotifying, UNUserNotificationCenterDelegate {
    static let shared = ReaderSystemNotifier()

    @Published private(set) var notificationStatus: ReaderNotificationStatus = .unknown

    private let notificationCenter: ReaderUserNotificationCentering
    private let settingsOpener: ReaderNotificationSettingsOpening
    private let notificationTargetFocuser: ReaderNotificationTargetFocusing

    init(
        notificationCenter: ReaderUserNotificationCentering = UNUserNotificationCenter.current(),
        settingsOpener: ReaderNotificationSettingsOpening = ReaderSystemNotificationSettingsOpener(),
        notificationTargetFocuser: ReaderNotificationTargetFocusing = ReaderNotificationTargetFocusCoordinator()
    ) {
        self.notificationCenter = notificationCenter
        self.settingsOpener = settingsOpener
        self.notificationTargetFocuser = notificationTargetFocuser
        super.init()
    }

    func configure() {
        notificationCenter.delegate = self
        refreshNotificationStatus()
    }

    func refreshNotificationStatus() {
        notificationCenter.notificationSettings { [weak self] settings in
            self?.updateNotificationStatus(with: settings)
        }
    }

    func requestAuthorizationIfNeeded() {
        ensureAuthorizationIfNeeded { _ in }
    }

    func openSystemNotificationSettings() {
        settingsOpener.openNotificationSettings()
    }

    func sendTestNotification(after delay: TimeInterval = 5) {
        let roundedDelay = max(delay.rounded(.up), 1)
        postNotification(
            ReaderSystemNotificationDescriptor(
                title: "Test notification",
                subtitle: "Background delivery check",
                body: "This test was scheduled by MarkdownObserver. Switch away from the app before it fires to verify background delivery.",
                userInfo: [:]
            ),
            timeInterval: roundedDelay
        )
    }

    func notifyFileAutoLoaded(
        _ fileURL: URL,
        changeKind: ReaderFolderWatchChangeKind,
        watchedFolderURL: URL?
    ) {
        postNotification(
            ReaderSystemNotificationDescriptor(
                fileURL: fileURL,
                watchedFolderURL: watchedFolderURL,
                event: .fileAutoLoaded(changeKind: changeKind)
            )
        )
    }

    func notifyExternalChange(for fileURL: URL, autoRefreshed: Bool, watchedFolderURL: URL?) {
        postNotification(
            ReaderSystemNotificationDescriptor(
                fileURL: fileURL,
                watchedFolderURL: watchedFolderURL,
                event: .externalChange(autoRefreshed: autoRefreshed)
            )
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponseUserInfo(response.notification.request.content.userInfo)
        completionHandler()
    }

    func handleNotificationResponseUserInfo(_ userInfo: [AnyHashable: Any]) {
        let fileURL = Self.url(from: userInfo[ReaderSystemNotificationUserInfoKey.filePath])
        let watchedFolderURL = Self.url(from: userInfo[ReaderSystemNotificationUserInfoKey.watchedFolderPath])

        _ = notificationTargetFocuser.focusNotificationTarget(
            fileURL: fileURL,
            watchedFolderURL: watchedFolderURL
        )
    }

    private func postNotification(
        _ descriptor: ReaderSystemNotificationDescriptor,
        timeInterval: TimeInterval? = nil
    ) {
        ensureAuthorizationIfNeeded { [weak self] isAuthorized in
            guard isAuthorized else {
                return
            }

            self?.addNotificationRequest(
                descriptor,
                timeInterval: timeInterval
            )
        }
    }

    private func addNotificationRequest(
        _ descriptor: ReaderSystemNotificationDescriptor,
        timeInterval: TimeInterval?
    ) {
        let trigger = timeInterval.map {
            UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false)
        }

        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.subtitle = descriptor.subtitle
        content.body = descriptor.body
        content.userInfo = descriptor.userInfo
        if #available(macOS 15.0, *) {
            content.interruptionLevel = .active
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        notificationCenter.add(request, withCompletionHandler: nil)
    }

    private func ensureAuthorizationIfNeeded(
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        notificationCenter.notificationSettings { [weak self] settings in
            self?.handleAuthorizationState(settings, completion: completion)
        }
    }

    private func handleAuthorizationState(
        _ settings: ReaderUserNotificationSettings,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        updateNotificationStatus(with: settings)

        switch ReaderNotificationAuthorizationState(settings.authorizationStatus) {
        case .authorized:
            completion(true)
        case .denied, .unknown:
            completion(false)
        case .notDetermined:
            notificationCenter.requestAuthorization(options: [.alert]) { [weak self] isGranted, _ in
                self?.refreshNotificationStatus()
                completion(isGranted)
            }
        }
    }

    private func updateNotificationStatus(with settings: ReaderUserNotificationSettings) {
        let status = ReaderNotificationStatus(settings: settings)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.notificationStatus = status
        }
    }

    private static func url(from rawValue: Any?) -> URL? {
        guard let path = rawValue as? String,
              !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }
}