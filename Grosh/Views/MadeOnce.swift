import SwiftUI

/// Shows `content` with what `make` works out the first time it is drawn, and keeps that for as long as it stays on
/// screen. A sheet's starting draft comes from the store (the suggested wallet and category, the Loan or Debt as it
/// stands), and SwiftUI builds a body again whenever anything it reads changes; worked out in `body`, the draft would
/// be fetched again each time, though the form keeps only the first one as its state.
struct MadeOnce<Value, Content: View>: View {
    let make: () -> Value
    @ViewBuilder let content: (Value) -> Content

    @State private var made = Made()

    var body: some View {
        content(made.value(make))
    }

    /// Holds the value once it is made. Filling it in doesn't redraw anything, so it is safe to do while drawing.
    private final class Made {
        private var value: Value?

        func value(_ make: () -> Value) -> Value {
            if let value { return value }
            let made = make()
            value = made
            return made
        }
    }
}
