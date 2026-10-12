import Foundation

/// The sound and haptic that play together when a new Expense or Income is saved from the Add Transaction sheet: the
/// chime picked in Settings → Sounds & Haptics, ending the Income way or the Expense way. Each chime ships as a note
/// list beside the two sounds rendered from it (ADR 0006), and its haptic is made from the very same notes
/// (``SuccessCue/Haptic``), so the two match by construction.
nonisolated enum SuccessCue {
    /// One of the chimes the user can pick for the cue. All three ship for now.
    nonisolated enum Chime: String, CaseIterable, Sendable {
        // The raw value names the chime's files and is what Settings remembers, so it never changes.
        case marimba
        case glassBells = "glassbells"
        case bubblePops = "bubblepops"

        /// The chime until the user picks another.
        static let `default` = Chime.marimba

        /// Its note list in the app bundle, as `<name>.json`.
        var noteListName: String {
            "SuccessCue-\(rawValue)"
        }

        /// Its sound for `ending` in the app bundle, as `<name>.caf`.
        func soundName(for ending: Ending) -> String {
            "\(noteListName)-\(ending.rawValue)"
        }
    }

    /// How the cue ends: one way for a new Income, another for a new Expense.
    nonisolated enum Ending: String, CaseIterable, Sendable {
        case income, expense

        /// The ending a new transaction of `type` plays, or `nil` for a type that plays no cue, such as a Loan or Debt.
        init?(newTransactionOf type: CategoryType) {
            switch type {
            case .income: self = .income
            case .expense: self = .expense
            case .debtLoan, .system: return nil
            }
        }
    }

    /// One note of an ending, as the note list gives it.
    nonisolated struct Note: Decodable, Hashable, Sendable {
        /// The MIDI note number: 69 is A4 at 440 Hz, 84 is C6.
        let pitch: Double
        /// Seconds from the start of the cue to the note's strike.
        let start: Double
        /// The note's level, 0...1.
        let loudness: Double
        /// Seconds the note takes to fade out, to −60 dB.
        let ring: Double
        /// How much shimmer rings above the note, 0...1, or `nil` for none. Only Income's last note has any.
        var sparkle: Double?
    }

    /// A chime's notes for each ending. The note list also gives the chime's name and says how its instrument sounds,
    /// which only the script that renders the sounds reads.
    nonisolated struct NoteList: Decodable, Sendable {
        let endings: Endings

        nonisolated struct Endings: Decodable, Sendable {
            let income: [Note]
            let expense: [Note]
        }

        /// The notes of `ending`, in the order they start.
        func notes(for ending: Ending) -> [Note] {
            switch ending {
            case .income: endings.income
            case .expense: endings.expense
            }
        }
    }
}

extension SuccessCue.NoteList {
    /// Reads a note list from its JSON file's contents.
    nonisolated init(json: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: json)
    }
}
