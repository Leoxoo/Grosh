/// A period's Daily average: its total divided by the days it covers, rounded to the cent.
enum DailyAverage {
    /// `total` a day over `days`, or `nil` when the range has no start or no end to count days from.
    static func of(_ total: Money, over days: DayRange) -> Money? {
        guard let count = days.dayCount, count > 0 else { return nil }
        let cents = (Double(total.cents) / Double(count)).rounded()
        return Money(cents: Int(cents), currencyCode: total.currencyCode)
    }
}
