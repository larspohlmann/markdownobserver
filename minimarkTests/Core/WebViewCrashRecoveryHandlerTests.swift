import Foundation
import OSLog
import Testing
@testable import minimark

struct WebViewCrashRecoveryHandlerTests {
    private let logger = Logger(subsystem: "minimark-tests", category: "CrashRecoveryTests")
    private let diagnosticName = "TestWebView"

    @Test func initialStateIsUnlocked() {
        let handler = WebViewCrashRecoveryHandler()
        #expect(handler.isCrashRecoveryLocked == false)
        #expect(handler.rapidTerminationCount == 0)
        #expect(handler.lastTerminationAt == nil)
    }

    @Test func firstTerminationReturnsRecover() {
        let handler = WebViewCrashRecoveryHandler()
        let action = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        #expect(action == .recover)
        #expect(handler.rapidTerminationCount == 1)
    }

    @Test func terminationWhenLockedReturnsAlreadyLocked() {
        let handler = WebViewCrashRecoveryHandler()
        handler.lock()
        let action = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        #expect(action == .alreadyLocked)
    }

    @Test func rapidTerminationsLockOut() {
        let handler = WebViewCrashRecoveryHandler()
        let firstAction = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        let secondAction = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        #expect(firstAction == .recover)
        #expect(secondAction == .lockedOut)
        #expect(handler.isCrashRecoveryLocked == true)
    }

    @Test func lockSetsLockedState() {
        let handler = WebViewCrashRecoveryHandler()
        handler.lock()
        #expect(handler.isCrashRecoveryLocked == true)
    }

    @Test func unlockClearsLockedStateAndCounters() {
        let handler = WebViewCrashRecoveryHandler()
        _ = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        _ = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        #expect(handler.isCrashRecoveryLocked == true)
        handler.unlock()
        #expect(handler.isCrashRecoveryLocked == false)
        #expect(handler.rapidTerminationCount == 0)
        #expect(handler.lastTerminationAt == nil)
    }

    @Test func resetStateClearsEverything() {
        let handler = WebViewCrashRecoveryHandler()
        _ = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        handler.lock()
        handler.resetState()
        #expect(handler.isCrashRecoveryLocked == false)
        #expect(handler.rapidTerminationCount == 0)
        #expect(handler.lastTerminationAt == nil)
    }

    @Test func recoverAfterUnlockWorks() {
        let handler = WebViewCrashRecoveryHandler()
        _ = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        _ = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        #expect(handler.isCrashRecoveryLocked == true)
        handler.unlock()
        let action = handler.handleTermination(logger: logger, diagnosticName: diagnosticName)
        #expect(action == .recover)
    }
}
