/// The named colors wallets, categories and Cards can use. Stored by name so the palette can follow the system's colors.
nonisolated enum PaletteColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray
}

extension PaletteColor {
    /// The palette entry a model stored by name, or gray for a name the palette no longer has.
    init(storedName name: String) {
        self = PaletteColor(rawValue: name) ?? .gray
    }
}
