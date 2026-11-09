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
}
