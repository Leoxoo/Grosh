/// Days compare in calendar order.
nonisolated extension CalendarDay: Comparable {
    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
