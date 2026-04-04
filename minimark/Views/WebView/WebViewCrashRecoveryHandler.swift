import Foundation
import OSLog

/// Tracks rapid WebView content-process terminations and enforces a lock-out
/// after repeated crashes to prevent infinite reload loops.
final class WebViewCrashRecoveryHandler {

    /// The action the Coordinator should take after a termination event.
    enum CrashRecoveryAction {
        /// The first termination in a window -- the Coordinator should reload.
        case recover
        /// Too many rapid terminations -- stop reloading and show a fallback.
        case lockedOut
        /// Recovery was already locked before this call (no action needed).
        case alreadyLocked
    }

    private(set) var lastTerminationAt: Date?
    private(set) var rapidTerminationCount = 0
    private(set) var isCrashRecoveryLocked = false

    /// Clears all crash-recovery state. Called when the document identity changes
    /// or a retry token resets the view.
    func resetState() {
        lastTerminationAt = nil
        rapidTerminationCount = 0
        isCrashRecoveryLocked = false
    }

    /// Unlocks crash recovery and resets termination counters.
    /// Used by retry-token resets to give the web view a fresh start.
    func unlock() {
        isCrashRecoveryLocked = false
        rapidTerminationCount = 0
        lastTerminationAt = nil
    }

    /// Locks crash recovery. Called on navigation failures that should
    /// prevent further automatic reloads.
    func lock() {
        isCrashRecoveryLocked = true
    }

    /// Evaluates a web-content-process termination and returns the
    /// appropriate recovery action.
    ///
    /// - Parameters:
    ///   - logger: The logger to write diagnostic messages to.
    ///   - diagnosticName: A label identifying the web view instance.
    /// - Returns: A ``CrashRecoveryAction`` telling the caller what to do.
    func handleTermination(logger: Logger, diagnosticName: String) -> CrashRecoveryAction {
        guard !isCrashRecoveryLocked else {
            logger.info("[\(diagnosticName, privacy: .public)] web content process terminated while recovery lock was active")
            return .alreadyLocked
        }

        let now = Date()
        if let lastTerminationAt, now.timeIntervalSince(lastTerminationAt) < 5 {
            rapidTerminationCount += 1
        } else {
            rapidTerminationCount = 1
        }
        self.lastTerminationAt = now
        logger.info("[\(diagnosticName, privacy: .public)] web content process terminated; rapidCount=\(self.rapidTerminationCount)")

        if rapidTerminationCount <= 1 {
            return .recover
        }

        isCrashRecoveryLocked = true
        return .lockedOut
    }
}
