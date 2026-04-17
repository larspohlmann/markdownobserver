import Foundation
import Observation

@MainActor
enum ObservationAsyncChange {
    static func next(
        tracking: @escaping @MainActor () -> Void
    ) async -> Bool {
        let box = ContinuationBox()
        return await withTaskCancellationHandler {
            await withUnsafeContinuation { continuation in
                box.store(continuation)
                if Task.isCancelled {
                    box.resume(returning: true)
                    return
                }
                withObservationTracking {
                    tracking()
                } onChange: {
                    box.resume(returning: false)
                }
            }
        } onCancel: {
            box.resume(returning: true)
        }
    }

    private final class ContinuationBox: @unchecked Sendable {
        private nonisolated(unsafe) var continuation: UnsafeContinuation<Bool, Never>?
        private nonisolated let lock = NSLock()

        nonisolated func store(_ continuation: UnsafeContinuation<Bool, Never>) {
            lock.lock()
            defer { lock.unlock() }
            self.continuation = continuation
        }

        nonisolated func resume(returning value: Bool) {
            let c: UnsafeContinuation<Bool, Never>?
            do {
                lock.lock()
                defer { lock.unlock() }
                c = continuation
                continuation = nil
            }
            c?.resume(returning: value)
        }
    }
}
