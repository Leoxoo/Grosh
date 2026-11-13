import Testing
@testable import Grosh

/// The preferences the app remembers: kept under the keys earlier versions wrote, and a chosen value under the raw value
/// they wrote, so an update keeps what the user chose.
@Suite(.namedInTheLog)
struct AppSettingsTests {
    @Test func eachPreferenceKeepsTheKeyEarlierVersionsWrote() {
        #expect(AppSettings.sounds.key == "soundsAndHaptics.sounds")
        #expect(AppSettings.haptics.key == "soundsAndHaptics.haptics")
        #expect(AppSettings.chime.key == "soundsAndHaptics.chime")
        #expect(AppSettings.currencyCode.key == "currencyCode")
        #expect(AppSettings.comparesWithLastYear.key == "home.monthGraph.comparesWithLastYear")
        #expect(AppSettings.isTotalHidden.key == "home.isTotalHidden")
        #expect(AppSettings.isComparisonCardShown.key == "report.comparisonCard.isShown")
        #expect(AppSettings.debtsLoansGrouping.key == "debtsLoans.grouping")
    }

    /// A renamed raw value would read back as nothing, and the user's choice would start over at the default.
    @Test func aChosenChimeOrGroupingKeepsTheValueEarlierVersionsWrote() {
        #expect(SuccessCue.Chime.allCases.map(\.rawValue) == ["marimba", "glassbells", "bubblepops"])
        #expect(DebtsLoansGrouping.people.rawValue == "people")
        #expect(DebtsLoansGrouping.loanOrDebt.rawValue == "loanOrDebt")
    }
}

/// Where the Sounds and Haptics switches take effect.
@Suite(.namedInTheLog)
struct SoundsAndHapticsTests {
    @Test func aSwitchPlaysOnlyWhereSoundsAndHapticsAreOfferedAndWhileItIsOn() {
        #expect(SoundsAndHaptics.plays(on: .iPhone, isOn: true))
        #expect(!SoundsAndHaptics.plays(on: .iPhone, isOn: false))
        #expect(!SoundsAndHaptics.plays(on: .iPad, isOn: true))
        #expect(!SoundsAndHaptics.plays(on: .mac, isOn: true))
    }
}
