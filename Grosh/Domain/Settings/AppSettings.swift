/// The settings the app remembers across launches, by the key each is stored under, so every screen that reads or sets
/// one agrees on it.
enum AppSettings {
    /// Whether the Month graph compares its period with Last year rather than the Average: the "vs last year" switch,
    /// which Home's Month graph and the Income and Spent details' comparison card share. Off at first.
    static let comparesWithLastYearKey = "home.monthGraph.comparesWithLastYear"
}
