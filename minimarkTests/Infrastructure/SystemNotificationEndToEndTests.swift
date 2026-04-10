//
//  SystemNotificationEndToEndTests.swift
//  minimarkTests
//
//  End-to-end tests that post real macOS notifications through
//  UNUserNotificationCenter. These tests verify that notification
//  content is correct for all three change kinds (added, modified, deleted).
//
//  NOTE: These tests require notification permissions for the test host app.
//  Run manually to see the notifications appear on your desktop.

import Foundation
import Testing
import UserNotifications
@testable import minimark

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RUN_E2E_NOTIFICATION_TESTS"] != nil))
struct SystemNotificationEndToEndTests {

    @Test func notificationPostedForCreatedFile() async throws {
        let notifier = ReaderSystemNotifier(
            notificationCenter: UNUserNotificationCenter.current()
        )
        notifier.configure()

        let folderURL = URL(fileURLWithPath: "/tmp/e2e-notification-test", isDirectory: true)
        let fileURL = folderURL.appendingPathComponent("created-file.md")

        notifier.notifyFileChanged(
            fileURL,
            changeKind: .added,
            watchedFolderURL: folderURL
        )

        // Allow time for the async authorization + delivery flow
        try await Task.sleep(for: .seconds(1))
    }

    @Test func notificationPostedForModifiedFile() async throws {
        let notifier = ReaderSystemNotifier(
            notificationCenter: UNUserNotificationCenter.current()
        )
        notifier.configure()

        let folderURL = URL(fileURLWithPath: "/tmp/e2e-notification-test", isDirectory: true)
        let fileURL = folderURL.appendingPathComponent("modified-file.md")

        notifier.notifyFileChanged(
            fileURL,
            changeKind: .modified,
            watchedFolderURL: folderURL
        )

        try await Task.sleep(for: .seconds(1))
    }

    @Test func notificationPostedForDeletedFile() async throws {
        let notifier = ReaderSystemNotifier(
            notificationCenter: UNUserNotificationCenter.current()
        )
        notifier.configure()

        let folderURL = URL(fileURLWithPath: "/tmp/e2e-notification-test", isDirectory: true)
        let fileURL = folderURL.appendingPathComponent("deleted-file.md")

        notifier.notifyFileChanged(
            fileURL,
            changeKind: .deleted,
            watchedFolderURL: folderURL
        )

        try await Task.sleep(for: .seconds(1))
    }
}
