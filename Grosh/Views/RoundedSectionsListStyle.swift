import SwiftUI

extension View {
    /// The list style of the transaction lists: each section a rounded group, as on iPhone. Mac has no grouped list
    /// style, so there the lists use the inset style: one rounded panel, with the section headers inside it. Without
    /// this, a list in a split view's sidebar column floats its rows outside any group.
    func roundedSectionsListStyle() -> some View {
        #if os(macOS)
        listStyle(.inset)
        #else
        listStyle(.insetGrouped)
        #endif
    }
}
