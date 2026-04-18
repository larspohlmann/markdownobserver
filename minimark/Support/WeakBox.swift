/// Forward-reference cell used when constructing a graph of objects that
/// need to point back at each other. The owning side stores a strong
/// reference; the forward-referring side reads the cell via a closure so
/// that both objects can be constructed before the cycle is wired.
@MainActor
final class WeakBox<T: AnyObject> {
    weak var value: T?

    init(_ value: T? = nil) {
        self.value = value
    }

    // Explicit empty deinit works around a Swift 6.2.4 EarlyPerfInliner SIL crash
    // on the synthesized deinit of @MainActor generic classes under -O.
    deinit {}
}
