import AppKit
import Combine
import Foundation
import UserNotifications

struct UserNotificationSettings: Equatable, Sendable {
    let authorizationStatus: UNAuthorizationStatus
    let alertSetting: UNNotificationSetting
    let soundSetting: UNNotificationSetting
    let notificationCenterSetting: UNNotificationSetting
}

protocol UserNotificationCentering: AnyObject {
    var delegate: UNUserNotificationCenterDelegate? { get set }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping @Sendable (Bool, Error?) -> Void
    )

    func notificationSettings(
        completionHandler: @escaping @Sendable (UserNotificationSettings) -> Void
    )

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
    )
}

extension UNUserNotificationCenter: UserNotificationCentering {
    func notificationSettings(
        completionHandler: @escaping @Sendable (UserNotificationSettings) -> Void
    ) {
        getNotificationSettings { settings in
            completionHandler(
                UserNotificationSettings(
                    authorizationStatus: settings.authorizationStatus,
                    alertSetting: settings.alertSetting,
                    soundSetting: settings.soundSetting,
                    notificationCenterSetting: settings.notificationCenterSetting
                )
            )
        }
    }
}

protocol NotificationSettingsOpening {
    func openNotificationSettings()
}

struct SystemNotificationSettingsOpener: NotificationSettingsOpening {
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

enum NotificationAuthorizationState: Equatable {
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

struct NotificationStatus: Equatable {
    let authorizationState: NotificationAuthorizationState
    let alertsEnabled: Bool
    let soundsEnabled: Bool
    let notificationCenterEnabled: Bool

    init(
        authorizationState: NotificationAuthorizationState,
        alertsEnabled: Bool,
        soundsEnabled: Bool,
        notificationCenterEnabled: Bool
    ) {
        self.authorizationState = authorizationState
        self.alertsEnabled = alertsEnabled
        self.soundsEnabled = soundsEnabled
        self.notificationCenterEnabled = notificationCenterEnabled
    }

    static let unknown = NotificationStatus(
        authorizationState: .unknown,
        alertsEnabled: false,
        soundsEnabled: false,
        notificationCenterEnabled: false
    )

    init(settings: UserNotificationSettings) {
        authorizationState = NotificationAuthorizationState(settings.authorizationStatus)
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

protocol SystemNotifying {
    func notifyFileChanged(
        _ fileURL: URL,
        changeKind: FolderWatchChangeKind,
        watchedFolderURL: URL?
    )
}

private enum SystemNotificationUserInfoKey {
    static let filePath = "filePath"
    static let watchedFolderPath = "watchedFolderPath"
}

private enum SystemNotificationEvent {
    case fileChanged(changeKind: FolderWatchChangeKind)

    var titleText: String {
        switch self {
        case .fileChanged(changeKind: .added):
            return "🟢 Created"
        case .fileChanged(changeKind: .modified):
            return "🟡 Modified"
        case .fileChanged(changeKind: .deleted):
            return "🔴 Deleted"
        }
    }
}

private struct SystemNotificationDescriptor {
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

    init(fileURL: URL, watchedFolderURL: URL?, event: SystemNotificationEvent) {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)
        let normalizedWatchedFolderURL = watchedFolderURL.map(FileRouting.normalizedFileURL)
        let fileName = normalizedFileURL.lastPathComponent

        title = event.titleText
        subtitle = fileName.isEmpty ? normalizedFileURL.path : fileName
        body = ""

        var userInfo: [AnyHashable: Any] = [
            SystemNotificationUserInfoKey.filePath: normalizedFileURL.path
        ]
        if let normalizedWatchedFolderURL {
            userInfo[SystemNotificationUserInfoKey.watchedFolderPath] = normalizedWatchedFolderURL.path
        }
        self.userInfo = userInfo
    }
}

protocol NotificationTargetFocusing {
    @discardableResult
    func focusNotificationTarget(fileURL: URL?, watchedFolderURL: URL?) -> Bool
}

struct NotificationTargetFocusCoordinator: NotificationTargetFocusing {
    @discardableResult
    func focusNotificationTarget(fileURL: URL?, watchedFolderURL: URL?) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                WindowRegistry.shared.focusNotificationTarget(
                    fileURL: fileURL,
                    watchedFolderURL: watchedFolderURL
                )
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                WindowRegistry.shared.focusNotificationTarget(
                    fileURL: fileURL,
                    watchedFolderURL: watchedFolderURL
                )
            }
        }
    }
}

final class SystemNotifier: NSObject, ObservableObject, SystemNotifying, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()

    @Published private(set) var notificationStatus: NotificationStatus = .unknown

    private let notificationCenter: UserNotificationCentering
    private let settingsOpener: NotificationSettingsOpening
    private let notificationTargetFocuser: NotificationTargetFocusing

    init(
        notificationCenter: UserNotificationCentering = UNUserNotificationCenter.current(),
        settingsOpener: NotificationSettingsOpening = SystemNotificationSettingsOpener(),
        notificationTargetFocuser: NotificationTargetFocusing = NotificationTargetFocusCoordinator()
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
            SystemNotificationDescriptor(
                title: "Test notification",
                subtitle: "Background delivery check",
                body: "This test was scheduled by MarkdownObserver. Switch away from the app before it fires to verify background delivery.",
                userInfo: [:]
            ),
            timeInterval: roundedDelay
        )
    }

    func notifyFileChanged(
        _ fileURL: URL,
        changeKind: FolderWatchChangeKind,
        watchedFolderURL: URL?
    ) {
        postNotification(
            SystemNotificationDescriptor(
                fileURL: fileURL,
                watchedFolderURL: watchedFolderURL,
                event: .fileChanged(changeKind: changeKind)
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
        let fileURL = Self.url(from: userInfo[SystemNotificationUserInfoKey.filePath])
        let watchedFolderURL = Self.url(from: userInfo[SystemNotificationUserInfoKey.watchedFolderPath])

        _ = notificationTargetFocuser.focusNotificationTarget(
            fileURL: fileURL,
            watchedFolderURL: watchedFolderURL
        )
    }

    private func postNotification(
        _ descriptor: SystemNotificationDescriptor,
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
        _ descriptor: SystemNotificationDescriptor,
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
        _ settings: UserNotificationSettings,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        updateNotificationStatus(with: settings)

        switch NotificationAuthorizationState(settings.authorizationStatus) {
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

    private func updateNotificationStatus(with settings: UserNotificationSettings) {
        let status = NotificationStatus(settings: settings)
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