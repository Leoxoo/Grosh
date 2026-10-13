extension SuccessCue {
    /// An ending's haptic, made from the same notes as its sound (ADR 0006): a tap the moment each note starts, as
    /// strong as the note is loud and as sharp as it is high. Under a note that rings with sparkle, as Income's last
    /// note does, a soft buzz starts with it and fades out as it rings.
    nonisolated struct Haptic: Equatable, Sendable {
        /// A tap at a note's start.
        nonisolated struct Tap: Equatable, Sendable {
            /// Seconds from the start of the cue.
            let time: Double
            /// How strong it is, 0...1.
            let intensity: Double
            /// How crisp it is, 0...1: the higher the note, the sharper the tap.
            let sharpness: Double
        }

        /// A soft buzz under a ringing note, fading from `intensity` to nothing over `duration`.
        nonisolated struct Buzz: Equatable, Sendable {
            /// Seconds from the start of the cue.
            let time: Double
            /// Seconds it lasts: as long as its note rings.
            let duration: Double
            /// How strong it starts, 0...1.
            let intensity: Double
            /// How crisp it is, 0...1, from its note's pitch as a tap's is.
            let sharpness: Double
        }

        let taps: [Tap]
        let buzzes: [Buzz]

        /// How strong a buzz starts under a note at full loudness and full sparkle: well below the note's tap.
        static let buzzLevel = 0.4

        /// The pitches a tap's sharpness spans: C4 (MIDI 60) and below are the dullest, C8 (108) and above the
        /// sharpest. It is the same for every chime, so a note feels as sharp whichever chime plays it.
        static let sharpnessPitches = 60.0...108.0

        init(notes: [Note]) {
            taps = notes.map { note in
                Tap(
                    time: note.start,
                    intensity: Self.clampedToUnitInterval(note.loudness),
                    sharpness: Self.sharpness(ofPitch: note.pitch)
                )
            }
            buzzes = notes.compactMap { note in
                guard let sparkle = note.sparkle, sparkle > 0, note.ring > 0 else { return nil }
                return Buzz(
                    time: note.start,
                    duration: note.ring,
                    intensity: Self.clampedToUnitInterval(Self.buzzLevel * note.loudness * sparkle),
                    sharpness: Self.sharpness(ofPitch: note.pitch)
                )
            }
        }

        /// A pitch as a sharpness, evenly across ``sharpnessPitches``: each semitone higher is a step sharper.
        static func sharpness(ofPitch pitch: Double) -> Double {
            clampedToUnitInterval(
                (pitch - sharpnessPitches.lowerBound) / (sharpnessPitches.upperBound - sharpnessPitches.lowerBound)
            )
        }

        private static func clampedToUnitInterval(_ value: Double) -> Double {
            min(max(value, 0), 1)
        }
    }
}

extension SuccessCue.NoteList {
    /// The haptic of `ending`.
    nonisolated func haptic(for ending: SuccessCue.Ending) -> SuccessCue.Haptic {
        SuccessCue.Haptic(notes: notes(for: ending))
    }
}
