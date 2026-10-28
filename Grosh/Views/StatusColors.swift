import SwiftUI

/// The colors that mean something, so every screen shows the same state in the same color. Change one here and
/// every badge, label and footer that shows that state follows. Amounts take theirs from `AmountText`.
extension ShapeStyle where Self == Color {
    /// Something to look at before relying on it: an estimated amount, a transaction left out of reports, an item
    /// that can't be restored yet.
    static var attention: Color { .orange }

    /// Done with: a settled or forgiven Loan or Debt.
    static var settled: Color { .green }

    /// What was typed can't be saved yet.
    static var invalid: Color { .red }

    /// A button that deletes. Its role alone doesn't color it in every form style, so it says so too.
    static var destructive: Color { .red }
}
