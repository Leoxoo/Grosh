/// The app's sounds and haptics, such as the Keypad's ticks and the Success cue: which devices get them, and the
/// preferences in Settings → Sounds & Haptics, whose switches turn them off. The system's own settings, such as the
/// ringer switch, still apply on top.
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

    /// Whether sounds, or haptics, play on `device` while their switch in Settings is `isOn`, whatever the other
    /// switch says. The switches are kept in ``AppSettings``.
    static func plays(on device: Device, isOn: Bool) -> Bool {
        isOffered(on: device) && isOn
    }
}
