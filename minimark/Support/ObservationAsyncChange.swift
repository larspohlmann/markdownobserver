import Foundation
import Observation

enum ObservationAsyncChange {
    @MainActor
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
            self.continuation = continuation
            lock.unlock()
        }

        nonisolated func resume(returning value: Bool) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }
}
