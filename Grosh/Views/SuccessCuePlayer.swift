import Foundation
import AVFoundation
import CoreHaptics

/// Plays the Success cue: a chime's sound for one ending and the haptic made from its note list, started together.
/// The sound mixes with whatever else is playing and never pauses it, is silent while the ringer is off, and plays at a
/// modest fixed level that the volume buttons scale. The haptic plays through Core Haptics, which Apple doesn't
/// document as following the system's Haptics switch, so the Haptics switch in Settings is the way to turn it off.
///
/// Nothing here holds up the caller or shows an error: the work happens off the main thread, and a sound or haptic that
/// can't start is skipped, as is the haptic on hardware that can't play one. It plays whatever it's asked on any
/// device: which devices get the cue is ``SoundsAndHaptics/isOffered(on:)``'s to decide.
actor SuccessCuePlayer {
    /// The app's one player, so a cue that starts cuts off the one before rather than playing over it.
    static let shared = SuccessCuePlayer()

    /// Plays `chime`'s `ending`: its sound if `sound`, its haptic if `haptic`, and nothing if neither. It returns at
    /// once. Whether each plays is the caller's to decide, with ``SoundsAndHaptics/playsSounds(on:soundsOn:)`` and
    /// ``SoundsAndHaptics/playsHaptics(on:hapticsOn:)``.
    nonisolated func play(_ chime: SuccessCue.Chime, ending: SuccessCue.Ending, sound: Bool, haptic: Bool) {
        guard sound || haptic else { return }
        Task {
            await self.start(chime, ending: ending, sound: sound, haptic: haptic)
        }
    }

    /// The sound's level before the volume buttons scale it: well below full, so the cue never startles.
    private let soundVolume: Float = 0.5

    #if !os(macOS)
    private var isSessionAmbient = false
    #endif
    private var hapticEngine: CHHapticEngine?
    /// Held until the next cue, so the cue isn't cut off when ``start(_:ending:sound:haptic:)`` returns.
    private var soundPlayer: AVAudioPlayer?
    private var hapticPlayer: (any CHHapticPatternPlayer)?

    private func start(_ chime: SuccessCue.Chime, ending: SuccessCue.Ending, sound: Bool, haptic: Bool) {
        // Both are made ready before either starts, so they start together.
        let newSoundPlayer = sound ? preparedSound(chime, ending) : nil
        let newHapticPlayer = haptic ? preparedHaptic(chime, ending) : nil
        soundPlayer?.stop()
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        try? newHapticPlayer?.start(atTime: CHHapticTimeImmediate)
        newSoundPlayer?.play()
        soundPlayer = newSoundPlayer
        hapticPlayer = newHapticPlayer
    }

    /// The chime's sound for `ending`, ready to play, or `nil` if it can't play without pausing other audio.
    private func preparedSound(_ chime: SuccessCue.Chime, _ ending: SuccessCue.Ending) -> AVAudioPlayer? {
        guard makeSessionAmbient(),
              let url = Bundle.main.url(forResource: chime.soundName(for: ending), withExtension: "caf"),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return nil }
        player.volume = soundVolume
        player.prepareToPlay()
        return player
    }

    /// Puts the app's audio in the ambient category, once: it mixes with other apps' audio instead of pausing it, and
    /// the ringer switch silences it. Returns whether it is, since a sound played in the default category would pause
    /// other audio. A Mac has no audio session, and its apps' audio always mixes, so there it always is.
    private func makeSessionAmbient() -> Bool {
        #if os(macOS)
        return true
        #else
        if !isSessionAmbient {
            isSessionAmbient = (try? AVAudioSession.sharedInstance().setCategory(.ambient)) != nil
        }
        return isSessionAmbient
        #endif
    }

    /// The chime's haptic for `ending`, ready to start, or `nil` if this device's hardware can't play it.
    private func preparedHaptic(
        _ chime: SuccessCue.Chime,
        _ ending: SuccessCue.Ending
    ) -> (any CHHapticPatternPlayer)? {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let url = Bundle.main.url(forResource: chime.noteListName, withExtension: "json")
        else { return nil }
        do {
            let haptic = try SuccessCue.NoteList(json: Data(contentsOf: url)).haptic(for: ending)
            return try startedEngine().makePlayer(with: pattern(of: haptic))
        } catch {
            return nil
        }
    }

    /// The haptic engine, started. It is made once and started again for every cue, since the system stops it while
    /// the app is in the background or after a failure. One that won't start is let go, so the next cue makes another.
    private func startedEngine() throws -> CHHapticEngine {
        let engine = try hapticEngine ?? makeEngine()
        hapticEngine = nil
        try engine.start()
        hapticEngine = engine
        return engine
    }

    private func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        // Ignoring audio events lets it start sooner, and shutting down while idle saves power between cues.
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        return engine
    }

    /// `haptic` as Core Haptics plays it: a transient event for each tap, and for each buzz a continuous event that an
    /// intensity curve fades to nothing.
    private func pattern(of haptic: SuccessCue.Haptic) throws -> CHHapticPattern {
        let taps = haptic.taps.map { tap in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(tap.intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(tap.sharpness)),
                ],
                relativeTime: tap.time
            )
        }
        let buzzes = haptic.buzzes.map { buzz in
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(buzz.intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(buzz.sharpness)),
                ],
                relativeTime: buzz.time,
                duration: buzz.duration
            )
        }
        // A curve scales every event playing while it runs. It starts at full, so the tap a buzz starts with keeps its
        // strength; a buzz rings under its chime's last note, so no later tap is softened.
        let fades = haptic.buzzes.map { buzz in
            CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1),
                    CHHapticParameterCurve.ControlPoint(relativeTime: buzz.duration, value: 0),
                ],
                relativeTime: buzz.time
            )
        }
        return try CHHapticPattern(events: taps + buzzes, parameterCurves: fades)
    }
}
