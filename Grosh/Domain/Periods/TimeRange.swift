/// How long each period in the Transactions tab's strip is. A month by default.
nonisolated enum TimeRange: Hashable, Sendable, CaseIterable {
    case month

    /// The periods the strip steps through, oldest first: one for each span from the one holding `earliest`
    /// (the first day with data) through the one holding `today`, then Future.
    func periods(from earliest: CalendarDay?, today: CalendarDay) -> [Period] {
        switch self {
        case .month:
            let thisMonth = CalendarMonth(today)
            var month = min(earliest.map(CalendarMonth.init) ?? thisMonth, thisMonth)
            var periods: [Period] = []
            while month <= thisMonth {
                periods.append(.month(month))
                month = month.adding(months: 1)
            }
            return periods + [.future]
        }
    }
}
