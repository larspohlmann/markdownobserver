import Foundation
import Testing
@testable import minimark

@Suite("FolderChangeFailureReporter")
@MainActor
struct FolderChangeFailureReporterTests {

    private static let folderURL = URL(fileURLWithPath: "/private/tmp/folder-change-reporter-tests")

    private func makeError(domain: String = "TestDomain", code: Int = 42) -> NSError {
        NSError(domain: domain, code: code, userInfo: nil)
    }

    @Test func reportDeliversFailureOnMainThreadWithSanitizedFields() async throws {
        let collector = FailureCollector()
        var reporter = FolderChangeFailureReporter(onFailure: { failure in
            collector.append(failure, isMainThread: Thread.isMainThread)
        })

        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())

        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 1 })

        let failure = try #require(collector.first)
        #expect(failure.stage == .startupSnapshot)
        #expect(!failure.folderIdentifier.contains("/"))
        #expect(!failure.folderIdentifier.contains(Self.folderURL.path))
        #expect(failure.errorDescription == "domain: TestDomain, code: 42")
        #expect(collector.allObservedOnMainThread)
    }

    @Test func reportDeduplicatesRepeatedFailuresWithSameSignatureForSameStage() async throws {
        let collector = FailureCollector()
        var reporter = FolderChangeFailureReporter(onFailure: { failure in
            collector.append(failure, isMainThread: Thread.isMainThread)
        })

        reporter.report(stage: .verificationSnapshot, folderURL: Self.folderURL, error: makeError())
        reporter.report(stage: .verificationSnapshot, folderURL: Self.folderURL, error: makeError())
        reporter.report(stage: .verificationSnapshot, folderURL: Self.folderURL, error: makeError())

        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 1 })

        // Give any spurious extra dispatches a chance to arrive before asserting deduplication.
        try await Task.sleep(for: .milliseconds(100))
        #expect(collector.count == 1)
    }

    @Test func reportEmitsSeparateFailuresWhenErrorSignatureChanges() async throws {
        let collector = FailureCollector()
        var reporter = FolderChangeFailureReporter(onFailure: { failure in
            collector.append(failure, isMainThread: Thread.isMainThread)
        })

        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError(code: 1))
        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError(code: 1))
        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError(code: 2))
        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError(domain: "OtherDomain", code: 2))

        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 3 })
        let descriptions = collector.snapshot.map(\.errorDescription)
        #expect(descriptions == [
            "domain: TestDomain, code: 1",
            "domain: TestDomain, code: 2",
            "domain: OtherDomain, code: 2"
        ])
    }

    @Test func reportDedupIsTrackedPerStage() async throws {
        let collector = FailureCollector()
        var reporter = FolderChangeFailureReporter(onFailure: { failure in
            collector.append(failure, isMainThread: Thread.isMainThread)
        })

        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())
        reporter.report(stage: .verificationSnapshot, folderURL: Self.folderURL, error: makeError())
        reporter.report(stage: .watchedDirectoryEnumeration, folderURL: Self.folderURL, error: makeError())

        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 3 })
        #expect(collector.snapshot.map(\.stage) == [
            .startupSnapshot,
            .verificationSnapshot,
            .watchedDirectoryEnumeration
        ])
    }

    @Test func clearReportedFailureForStageAllowsNextIdenticalErrorThrough() async throws {
        let collector = FailureCollector()
        var reporter = FolderChangeFailureReporter(onFailure: { failure in
            collector.append(failure, isMainThread: Thread.isMainThread)
        })

        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())
        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 1 })

        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())
        try await Task.sleep(for: .milliseconds(100))
        #expect(collector.count == 1)

        reporter.clearReportedFailure(for: .startupSnapshot)
        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())

        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 2 })
    }

    @Test func clearReportedFailureDoesNotAffectOtherStages() async throws {
        let collector = FailureCollector()
        var reporter = FolderChangeFailureReporter(onFailure: { failure in
            collector.append(failure, isMainThread: Thread.isMainThread)
        })

        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())
        reporter.report(stage: .verificationSnapshot, folderURL: Self.folderURL, error: makeError())
        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 2 })

        reporter.clearReportedFailure(for: .startupSnapshot)

        // Verification stage still deduplicated.
        reporter.report(stage: .verificationSnapshot, folderURL: Self.folderURL, error: makeError())
        try await Task.sleep(for: .milliseconds(100))
        #expect(collector.count == 2)
    }

    @Test func resetAllReportedFailuresClearsEveryStage() async throws {
        let collector = FailureCollector()
        var reporter = FolderChangeFailureReporter(onFailure: { failure in
            collector.append(failure, isMainThread: Thread.isMainThread)
        })

        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())
        reporter.report(stage: .verificationSnapshot, folderURL: Self.folderURL, error: makeError())
        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 2 })

        reporter.resetAllReportedFailures()

        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())
        reporter.report(stage: .verificationSnapshot, folderURL: Self.folderURL, error: makeError())

        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 4 })
    }

    @Test func sanitizedFolderIdentifierIsStableForEquivalentURLs() async throws {
        let collector = FailureCollector()
        var reporter = FolderChangeFailureReporter(onFailure: { failure in
            collector.append(failure, isMainThread: Thread.isMainThread)
        })

        let resolvedURL = Self.folderURL.resolvingSymlinksInPath()
        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError(code: 1))
        reporter.clearReportedFailure(for: .startupSnapshot)
        reporter.report(stage: .startupSnapshot, folderURL: resolvedURL, error: makeError(code: 1))

        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 2 })
        let identifiers = collector.snapshot.map(\.folderIdentifier)
        #expect(identifiers.count == 2)
        #expect(identifiers[0] == identifiers[1])
    }

    @Test func reportWithoutHandlerStillUpdatesDedupState() async throws {
        var reporter = FolderChangeFailureReporter(onFailure: nil)
        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())
        reporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())

        let collector = FailureCollector()
        // New reporter with a handler to prove clearing allows delivery.
        var observedReporter = FolderChangeFailureReporter(onFailure: { failure in
            collector.append(failure, isMainThread: Thread.isMainThread)
        })
        observedReporter.report(stage: .startupSnapshot, folderURL: Self.folderURL, error: makeError())
        #expect(await waitUntil(timeout: .seconds(1)) { collector.count == 1 })
    }
}

private final class FailureCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [FolderChangeWatcherFailure] = []
    private var mainThreadFlags: [Bool] = []

    func append(_ failure: FolderChangeWatcherFailure, isMainThread: Bool) {
        lock.lock()
        failures.append(failure)
        mainThreadFlags.append(isMainThread)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return failures.count
    }

    var first: FolderChangeWatcherFailure? {
        lock.lock()
        defer { lock.unlock() }
        return failures.first
    }

    var snapshot: [FolderChangeWatcherFailure] {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }

    var allObservedOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadFlags.allSatisfy { $0 }
    }
}
