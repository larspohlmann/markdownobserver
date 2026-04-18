import Foundation

@MainActor protocol ChildStoreCoordinating: AnyObject {
    func childStoreDidMutate(coalescePersistence: Bool)
}
