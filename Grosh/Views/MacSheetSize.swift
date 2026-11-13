import SwiftUI

/// The size a sheet opens at on a Mac, where it is a window of its own rather than a card the system sizes: its
/// smallest width and height, and the ones it starts at.
struct MacSheetSize {
    let minWidth: CGFloat
    var idealWidth: CGFloat?
    let minHeight: CGFloat
    var idealHeight: CGFloat?

    /// A sheet that types an amount (``KeypadSheet``).
    static let keypadForm = MacSheetSize(minWidth: 420, idealWidth: 460, minHeight: 560, idealHeight: 640)
    /// A ``KeypadSheet`` with many sections, such as the transaction and Recurring transaction editors.
    static let tallKeypadForm = MacSheetSize(minWidth: 420, idealWidth: 460, minHeight: 640, idealHeight: 720)
    /// A list of parts to go through, such as Split's.
    static let list = MacSheetSize(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 560)
    /// A short form, such as Forgive.
    static let shortForm = MacSheetSize(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 420)
    /// The shortest form, such as forgiving an Owes me.
    static let shorterForm = MacSheetSize(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 380)
    /// The due reminders.
    static let reminders = MacSheetSize(minWidth: 420, idealWidth: 460, minHeight: 360, idealHeight: 480)
    /// A narrow list to pick one from, such as a wallet.
    static let picker = MacSheetSize(minWidth: 360, idealWidth: 400, minHeight: 360, idealHeight: 480)
    /// A message to send, such as Text them.
    static let message = MacSheetSize(minWidth: 380, idealWidth: 420, minHeight: 300, idealHeight: 360)
    /// The people to pick for With.
    static let people = MacSheetSize(minWidth: 340, minHeight: 400)
    /// Two days to pick, for a custom range.
    static let dayRange = MacSheetSize(minWidth: 320, minHeight: 160)
}

extension View {
    /// Opens the sheet at `size` on a Mac. Elsewhere a sheet takes the size the system gives it.
    func macSheetSize(_ size: MacSheetSize) -> some View {
        #if os(macOS)
        frame(
            minWidth: size.minWidth, idealWidth: size.idealWidth, minHeight: size.minHeight, idealHeight: size.idealHeight
        )
        #else
        self
        #endif
    }
}
