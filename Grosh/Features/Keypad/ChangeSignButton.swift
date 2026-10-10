import SwiftUI

/// Changes the sign of an amount typed on ``AmountKeypad``, for amounts that may be below zero, such as a balance.
/// Disabled while the keypad shows an error.
struct ChangeSignButton: View {
    @Binding var entry: AmountEntry

    var body: some View {
        Button("Change Sign", systemImage: "plusminus") { entry.changeSign() }
            .disabled(entry.cents == nil)
    }
}
