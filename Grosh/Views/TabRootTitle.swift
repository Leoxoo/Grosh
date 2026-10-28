import SwiftUI

extension View {
    /// The title of a tab's first screen: the standard large title, which slides away as the content scrolls up, and
    /// no small title in the bar once it has gone, unless `showsSmallTitle`, as while selecting, when the bar is where
    /// the count shows (ADR-0009). Use inside the tab's `NavigationStack`.
    func tabRootTitle(showsSmallTitle: Bool = false) -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !showsSmallTitle {
                    // Takes the place of the bar's small title, leaving the large one as it is.
                    ToolbarItem(placement: .principal) {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
        #else
        self
        #endif
    }
}
