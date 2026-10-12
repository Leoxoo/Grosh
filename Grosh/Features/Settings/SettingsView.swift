import SwiftUI

/// Account → Settings: the app's preferences, one section each. It is shown on every device and Currency is always its
/// first section, so it is never empty; a section only some devices offer, such as Sounds & Haptics, sits below it.
struct SettingsView: View {
    @AppStorage(CurrencyPickerView.currencyCodeKey) private var currencyCode = Money.defaultCurrencyCode
    @AppStorage(SoundsAndHaptics.soundsKey) private var soundsOn = SoundsAndHaptics.defaultIsOn
    @AppStorage(SoundsAndHaptics.hapticsKey) private var hapticsOn = SoundsAndHaptics.defaultIsOn
    @AppStorage(SoundsAndHaptics.chimeKey) private var chime = SuccessCue.Chime.default

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    CurrencyPickerView()
                } label: {
                    LabeledContent {
                        Text(currencyCode)
                    } label: {
                        Label("Currency", systemImage: "dollarsign.circle")
                    }
                }
            }

            if SoundsAndHaptics.isOffered(on: .current) {
                Section {
                    Toggle(isOn: $soundsOn) {
                        Label("Sounds", systemImage: "speaker.wave.2")
                    }
                    Toggle(isOn: $hapticsOn) {
                        Label("Haptics", systemImage: "hand.tap")
                    }
                    Picker(selection: $chime) {
                        ForEach(SuccessCue.Chime.allCases, id: \.self) { chime in
                            Text(chime.title).tag(chime)
                        }
                    } label: {
                        Label("Chime", systemImage: "music.note")
                    }
                } header: {
                    Text("Sounds & Haptics")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: preferences) { old, new in
            playSample(changingFrom: old, to: new)
        }
    }

    /// The Sounds & Haptics preferences as they stand, watched so that changing one can play a sample of the Success
    /// cue. Opening Settings changes none of them, so it plays nothing.
    private var preferences: SoundsAndHaptics.Preferences {
        SoundsAndHaptics.Preferences(soundsOn: soundsOn, hapticsOn: hapticsOn, chime: chime)
    }

    /// Plays the sample of the Success cue that changing the preferences from `old` to `new` calls for, if any. It
    /// returns at once, and a sample that can't play is skipped without a word.
    private func playSample(changingFrom old: SoundsAndHaptics.Preferences, to new: SoundsAndHaptics.Preferences) {
        guard let sample = SuccessCue.Sample(changingFrom: old, to: new, on: .current) else { return }
        SuccessCuePlayer.shared.play(sample.chime, ending: sample.ending, sound: sample.sound, haptic: sample.haptic)
    }
}

private extension SuccessCue.Chime {
    /// The chime's name, as its note list gives it.
    var title: String {
        switch self {
        case .marimba: String(localized: "Marimba")
        case .glassBells: String(localized: "Glass bells")
        case .bubblePops: String(localized: "Bubble pops")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
