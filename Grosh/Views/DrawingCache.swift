/// A value a view works out while it draws, kept until what it was made from (its key) changes. SwiftUI builds a body
/// again whenever anything it reads changes, so a value read from the store in `body` would be fetched again on every
/// draw, such as each keystroke in a form. Hold one in `@State`: it is a class SwiftUI doesn't observe, so filling it
/// in doesn't redraw anything, and it is safe to do while drawing.
final class DrawingCache<Key: Equatable, Value> {
    private var kept: (key: Key, value: Value)?

    /// The value made for `key`: the one kept, when it was made for the same key, or else what `make` works out now,
    /// which is kept in its place.
    func value(for key: Key, make: () -> Value) -> Value {
        if let kept, kept.key == key { return kept.value }
        let made = make()
        kept = (key, made)
        return made
    }
}
