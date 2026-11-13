import SwiftUI

/// Shows `content` with what `make` works out the first time it is drawn, and keeps that for as long as it stays on
/// screen. A sheet's starting draft comes from the store (the suggested wallet and category, the Loan or Debt as it
/// stands), and SwiftUI builds a body again whenever anything it reads changes; worked out in `body`, the draft would
/// be fetched again each time, though the form keeps only the first one as its state.
struct MadeOnce<Value, Content: View>: View {
    let make: () -> Value
    @ViewBuilder let content: (Value) -> Content

    /// Kept under one key, so it is made only once.
    @State private var made = DrawingCache<Bool, Value>()

    var body: some View {
        content(made.value(for: true, make: make))
    }
}
