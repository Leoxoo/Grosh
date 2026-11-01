import SwiftUI

/// Every color the app chooses, in one place. Change one here and every screen that shows it follows. The greens and
/// reds follow Fidelity's: a deep green and red in light mode, a soft green and coral red in dark mode, set in the
/// asset catalog (AccentColor, AmountGreen, AmountRed, OnAccent). Plain system styles (`.primary`, `.secondary`,
/// `.tertiary`, the fills) and white text on a colored shape aren't listed: they already follow light and dark mode and
/// carry no meaning of their own.

// MARK: - Amounts

extension ShapeStyle where Self == Color {
    /// Money coming in: green, from the asset catalog.
    static var moneyIn: Color { Color("AmountGreen") }

    /// Money going out: red, from the asset catalog.
    static var moneyOut: Color { Color("AmountRed") }
}

extension Money {
    /// Green for money coming in, red for money going out; zero stays plain text.
    var tint: Color {
        cents > 0 ? .moneyIn : cents < 0 ? .moneyOut : .primary
    }
}

extension SpentOrIncome {
    /// The color amounts going out (Spent) or coming in (Income) have everywhere in the app.
    var color: Color {
        self == .spent ? .moneyOut : .moneyIn
    }
}

extension LoanOrDebtKind {
    /// What is outstanding: green for money coming back, red for money owed.
    var outstandingColor: Color {
        switch self {
        case .loan: .moneyIn
        case .debt: .moneyOut
        }
    }
}

// MARK: - States

extension ShapeStyle where Self == Color {
    /// Something to look at before relying on it: an estimated amount, a transaction left out of reports, an item
    /// that can't be restored yet.
    static var attention: Color { .orange }

    /// Done with: a settled or forgiven Loan or Debt.
    static var settled: Color { .moneyIn }

    /// What was typed can't be saved yet.
    static var invalid: Color { .red }

    /// Running out of time: a reminder that's due, an item about to leave Recently Deleted.
    static var urgent: Color { .red }

    /// A button that deletes. Its role alone doesn't color it in every form style, so it says so too.
    static var destructive: Color { .red }
}

// MARK: - Actions

extension ShapeStyle where Self == Color {
    /// The app's own green, its accent color: the + that adds a transaction, the Keypad's action key, the
    /// selected period.
    static var brand: Color { .accentColor }

    /// Text and symbols drawn on the brand green: white on the deep green of light mode, near-black on the soft green
    /// of dark mode, as Fidelity's buttons are.
    static var onBrand: Color { Color("OnAccent") }

    /// The tint of the Keypad's operator keys: a light wash of the brand green over their glass, so the action key, in
    /// the brand green itself, stands out from them.
    static var keypadOperator: Color { .brand.opacity(0.35) }

    /// The swipe action that archives a wallet or Card.
    static var archiveAction: Color { .orange }

    /// The swipe action that brings an archived wallet or Card back.
    static var unarchiveAction: Color { .brand }

    /// The swipe action that restores an item from Recently Deleted.
    static var restoreAction: Color { .blue }

    /// The swipe action that merges a category into another.
    static var mergeAction: Color { .indigo }

    /// The swipe action that hides or unhides a category.
    static var hideAction: Color { .gray }
}

// MARK: - Charts

extension ShapeStyle where Self == Color {
    /// The line the month is compared with, the Average or Last year, and its legend entry.
    static var comparison: Color { .gray }
}

// MARK: - Palette

extension PaletteColor {
    /// The system color this palette entry stands for, so it follows light and dark mode.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}
