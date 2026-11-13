import SwiftUI

extension View {
    /// Shows why a change was refused: an alert titled `title` with `message`, up while `message` isn't `nil`.
    /// OK clears it.
    func errorAlert(_ title: LocalizedStringResource, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button(Strings.Common.ok) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
