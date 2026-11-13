import os
import SwiftUI

/// How a sheet saves: it makes the change and closes once the change is made. When the change is refused or fails, the
/// failure is logged (``os/Logger/perform(_:errorMessage:expected:_:)``), the sheet stays open, and an alert titled
/// `failureTitle` says why (``SwiftUI/View/failureAlert(_:)``). ``KeypadSheet`` saves this way; any other sheet that
/// saves holds one.
struct SheetSaver: DynamicProperty {
    let failureTitle: LocalizedStringResource
    let log: Logger

    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?

    init(_ failureTitle: LocalizedStringResource, log: Logger = Log.store) {
        self.failureTitle = failureTitle
        self.log = log
    }

    /// Makes `change`, logged as `what` when it fails, and closes the sheet once it is made.
    func save(_ what: String, _ change: () throws -> Void) {
        saveOrStay(what, {
            try change()
            return .close
        })
    }

    /// Makes `change` as ``save(_:_:)`` does, and closes the sheet once it is made unless `change` says it
    /// stays open: for a sheet that asks something more before or after it saves.
    func saveOrStay(_ what: String, _ change: () throws -> AfterSaving) {
        var after = AfterSaving.close
        if keepingOpen(what, { after = try change() }), after == .close {
            dismiss()
        }
    }

    /// Makes `change` as ``save(_:_:)`` does, with the sheet left open, and says whether it was made.
    @discardableResult
    func keepingOpen(_ what: String, _ change: () throws -> Void) -> Bool {
        log.perform(what, errorMessage: &failure, change)
    }

    /// Why the last change wasn't made, while the alert says so.
    var failureMessage: Binding<String?> { $failure }
}

/// What a sheet does once Save has made its change.
enum AfterSaving {
    case close
    /// It stays open to ask something more, such as which halves of a transfer to change.
    case stayOpen
}

extension View {
    /// The alert that says why `saver` couldn't make a change.
    func failureAlert(_ saver: SheetSaver) -> some View {
        errorAlert(saver.failureTitle, message: saver.failureMessage)
    }
}
