/// The app's sounds and haptics, such as the Keypad's ticks: which devices get them, and the switches in Settings →
/// Sounds & Haptics that turn them off. The system's own settings, such as its Haptics switch, still apply on top.
nonisolated enum SoundsAndHaptics {
    /// The sort of device the app runs on, as far as sounds and haptics go.
    nonisolated enum Device: CaseIterable, Sendable {
        case iPhone, iPad, mac
    }

    /// Whether `device` gets sounds and haptics, and with them the Sounds & Haptics section in Settings. This is the one
    /// place that decides it: iPhone only for now, and naming another device here is all it takes to give it the
    /// section and what its switches turn on.
    static func isOffered(on device: Device) -> Bool {
        device == .iPhone
    }

    /// Each switch is on until the user turns it off.
    static let defaultIsOn = true

    /// Where the Haptics switch is remembered.
    static let hapticsKey = "soundsAndHaptics.haptics"

    /// Whether haptics play on `device` while the Haptics switch is `hapticsOn`.
    static func playsHaptics(on device: Device, hapticsOn: Bool) -> Bool {
        isOffered(on: device) && hapticsOn
    }
}
