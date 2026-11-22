import SwiftUI

extension View {
    /// Adds the system search field behind a Search button in the bar, beside the screen's other bar buttons, rather
    /// than a search field that is always there and pushes a tab's title down (ADR-0009). On iPhone and iPad the field
    /// is there only while `isOpen`, set by the screen's Search button, or while search text is left to clear. It hangs
    /// on an empty background rather than on the screen itself: a modifier that comes and goes on a list rebuilds the
    /// list, which loses its place. Mac keeps its search field in the toolbar, and has no Search button.
    func searchBehindButton(
        text: Binding<String>, isOpen: Binding<Bool>, prompt: LocalizedStringResource
    ) -> some View {
        modifier(SearchBehindButton(text: text, isOpen: isOpen, prompt: prompt))
    }
}

private struct SearchBehindButton: ViewModifier {
    @Binding var text: String
    @Binding var isOpen: Bool
    let prompt: LocalizedStringResource

    func body(content: Content) -> some View {
        #if os(macOS)
        content.searchable(text: $text, prompt: Text(prompt))
        #else
        content.background {
            if isOpen || !text.isEmpty {
                Color.clear
                    .searchable(text: $text, isPresented: $isOpen, prompt: Text(prompt))
            }
        }
        #endif
    }
}

/// The Search button that opens ``SwiftUI/View/searchBehindButton(text:isOpen:prompt:)``'s field, for the bar's primary
/// actions. None on Mac, which keeps the field in the toolbar.
struct SearchButton: ToolbarContent {
    @Binding var isOpen: Bool

    var body: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .primaryAction) {
            Button(Strings.Screens.search, systemImage: "magnifyingglass") { isOpen = true }
        }
        #endif
    }
}
