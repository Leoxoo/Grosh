extension SoundsAndHaptics {
    /// The preferences in Settings → Sounds & Haptics as they stand at one moment.
    nonisolated struct Preferences: Equatable, Sendable {
        var soundsOn: Bool
        var hapticsOn: Bool
        var chime: SuccessCue.Chime
    }
}

extension SuccessCue {
    /// The Income version of the cue, played once as the user changes Settings → Sounds & Haptics, so they can check
    /// how it sounds and feels without adding a transaction. There are no separate rows for trying it.
    nonisolated struct Sample: Equatable, Sendable {
        /// The chime it plays: the one just picked, or the one already picked when a switch is turned on.
        let chime: Chime
        /// Whether it plays the sound.
        let sound: Bool
        /// Whether it plays the haptic.
        let haptic: Bool

        /// A sample always ends the Income way.
        var ending: Ending { .income }

        /// The sample that changing the preferences from `old` to `new` plays on `device`, or `nil` for none. Turning
        /// Sounds on plays only the sound, and turning Haptics on only the haptic. Picking another chime plays that
        /// chime, with the sound and the haptic as the switches allow. Turning a switch off plays nothing, and so does
        /// opening Settings, which changes nothing.
        init?(
            changingFrom old: SoundsAndHaptics.Preferences,
            to new: SoundsAndHaptics.Preferences,
            on device: SoundsAndHaptics.Device
        ) {
            let picksChime = new.chime != old.chime
            let turnsSoundsOn = new.soundsOn && !old.soundsOn
            let turnsHapticsOn = new.hapticsOn && !old.hapticsOn
            let sound = (turnsSoundsOn || picksChime)
                && SoundsAndHaptics.playsSounds(on: device, soundsOn: new.soundsOn)
            let haptic = (turnsHapticsOn || picksChime)
                && SoundsAndHaptics.playsHaptics(on: device, hapticsOn: new.hapticsOn)
            guard sound || haptic else { return nil }
            self.chime = new.chime
            self.sound = sound
            self.haptic = haptic
        }
    }
}
