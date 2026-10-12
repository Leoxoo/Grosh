import SwiftUI

/// Account → Settings: the app's preferences, one section each. It is shown on every device and Currency is always its
/// first section, so it is never empty; a section only some devices offer, such as Sounds & Haptics, sits below it.
struct SettingsView: View {
    @AppStorage(CurrencyPickerView.currencyCodeKey) private var currencyCode = Money.defaultCurrencyCode
    @AppStorage(SoundsAndHaptics.hapticsKey) private var hapticsOn = SoundsAndHaptics.defaultIsOn

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
                Section("Sounds & Haptics") {
                    Toggle(isOn: $hapticsOn) {
                        Label("Haptics", systemImage: "hand.tap")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
