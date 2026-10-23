import SwiftUI

extension EnvironmentValues {
    /// The day screens treat as today. The app sets it once, at its root, from the real date and moves it on when the
    /// day changes while it is open, so a screen reads it here instead of the clock. A test or a preview shows a screen
    /// as of a fixed day with `.environment(\.today, day)`.
    @Entry var today: CalendarDay = .today
}
