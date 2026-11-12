/// One preference the app remembers in `UserDefaults`: where it is kept, and what it is until the user changes it. A
/// screen reads or writes it with `@AppStorage(AppSettings.sounds)`, so its key and its default always go together.
nonisolated struct AppSetting<Value: Sendable>: Sendable {
    /// The `UserDefaults` key, which earlier versions wrote too, so it never changes.
    let key: String
    let defaultValue: Value
}

/// The preferences the app remembers in `UserDefaults`. Every screen that reads or writes one uses these.
nonisolated enum AppSettings {
    /// Settings → Sounds & Haptics → Sounds.
    static let sounds = AppSetting(key: "soundsAndHaptics.sounds", defaultValue: true)

    /// Settings → Sounds & Haptics → Haptics.
    static let haptics = AppSetting(key: "soundsAndHaptics.haptics", defaultValue: true)

    /// The Success cue's chime, kept as its ``SuccessCue/Chime`` raw value.
    static let chime = AppSetting(key: "soundsAndHaptics.chime", defaultValue: SuccessCue.Chime.default)

    /// Settings → Currency: the currency a new wallet starts in.
    static let currencyCode = AppSetting(key: "currencyCode", defaultValue: Money.defaultCurrencyCode)

    /// Whether the Month graph compares its period with Last year rather than the Average: the "vs last year" switch,
    /// which Home's Month graph and the Income and Spent details' comparison card share. Off at first.
    static let comparesWithLastYear = AppSetting(key: "home.monthGraph.comparesWithLastYear", defaultValue: false)

    /// Whether Home hides the Total behind dots: its eye button. Shown at first.
    static let isTotalHidden = AppSetting(key: "home.isTotalHidden", defaultValue: false)

    /// Whether the Income and Spent details show their comparison card. Hidden at first.
    static let isComparisonCardShown = AppSetting(key: "report.comparisonCard.isShown", defaultValue: false)

    /// How Debts & Loans lists them: by Loan or Debt, as it did before Show by people existed, or by person.
    static let debtsLoansGrouping = AppSetting(key: "debtsLoans.grouping", defaultValue: DebtsLoansGrouping.loanOrDebt)
}
