import Testing
@testable import Grosh

/// The preferences in Settings: kept under the keys earlier versions wrote, so an update keeps what the user chose.
@Suite(.namedInTheLog)
struct AppSettingsTests {
    @Test func eachPreferenceKeepsTheKeyEarlierVersionsWrote() {
        #expect(AppSettings.soundsKey == "soundsAndHaptics.sounds")
        #expect(AppSettings.hapticsKey == "soundsAndHaptics.haptics")
        #expect(AppSettings.chimeKey == "soundsAndHaptics.chime")
        #expect(AppSettings.currencyCodeKey == "currencyCode")
    }

    @Test func aSwitchPlaysOnlyWhereSoundsAndHapticsAreOfferedAndWhileItIsOn() {
        #expect(SoundsAndHaptics.plays(on: .iPhone, isOn: true))
        #expect(!SoundsAndHaptics.plays(on: .iPhone, isOn: false))
        #expect(!SoundsAndHaptics.plays(on: .iPad, isOn: true))
        #expect(!SoundsAndHaptics.plays(on: .mac, isOn: true))
    }
}
