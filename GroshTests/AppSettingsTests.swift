import Testing
@testable import Grosh

/// The preferences in Settings: kept under the keys earlier versions wrote, so an update keeps what the user chose.
@Suite(.namedInTheLog)
struct AppSettingsTests {
    @Test func eachPreferenceKeepsTheKeyEarlierVersionsWrote() {
        #expect(AppSettings.sounds.key == "soundsAndHaptics.sounds")
        #expect(AppSettings.haptics.key == "soundsAndHaptics.haptics")
        #expect(AppSettings.chime.key == "soundsAndHaptics.chime")
        #expect(AppSettings.currencyCode.key == "currencyCode")
    }

    @Test func aSwitchPlaysOnlyWhereSoundsAndHapticsAreOfferedAndWhileItIsOn() {
        #expect(SoundsAndHaptics.plays(on: .iPhone, isOn: true))
        #expect(!SoundsAndHaptics.plays(on: .iPhone, isOn: false))
        #expect(!SoundsAndHaptics.plays(on: .iPad, isOn: true))
        #expect(!SoundsAndHaptics.plays(on: .mac, isOn: true))
    }
}
