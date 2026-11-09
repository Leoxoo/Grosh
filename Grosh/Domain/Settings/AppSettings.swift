/// The preferences the app remembers in `UserDefaults`: where each is kept, and what it is until the user changes it.
/// Every screen that reads or writes one uses these, so a key and its default are written once.
nonisolated enum AppSettings {
    /// Settings → Sounds & Haptics → Sounds.
    static let soundsKey = "soundsAndHaptics.sounds"
    static let soundsDefault = true

    /// Settings → Sounds & Haptics → Haptics.
    static let hapticsKey = "soundsAndHaptics.haptics"
    static let hapticsDefault = true

    /// The Success cue's chime, as its ``SuccessCue/Chime`` raw value.
    static let chimeKey = "soundsAndHaptics.chime"
    static let chimeDefault = SuccessCue.Chime.default

    /// Settings → Currency: the currency a new wallet starts in.
    static let currencyCodeKey = "currencyCode"
    static let currencyCodeDefault = Money.defaultCurrencyCode

    /// Whether the Month graph compares its period with Last year rather than the Average: the "vs last year" switch,
    /// which Home's Month graph and the Income and Spent details' comparison card share. Off at first.
    static let comparesWithLastYearKey = "home.monthGraph.comparesWithLastYear"
    static let comparesWithLastYearDefault = false

    /// Whether Home hides the Total behind dots: its eye button. Shown at first.
    static let isTotalHiddenKey = "home.isTotalHidden"
    static let isTotalHiddenDefault = false

    /// Whether the Income and Spent details show their comparison card. Hidden at first.
    static let isComparisonCardShownKey = "report.comparisonCard.isShown"
    static let isComparisonCardShownDefault = false

    /// How Debts & Loans lists them: by Loan or Debt, as it did before Show by people existed, or by person.
    static let debtsLoansGroupingKey = "debtsLoans.grouping"
    static let debtsLoansGroupingDefault = DebtsLoansGrouping.loanOrDebt
}
