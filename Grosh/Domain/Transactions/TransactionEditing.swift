extension Transaction {
    /// Whether the Add Transaction sheet can edit or duplicate this transaction. A transaction the app records
    /// under a category of its own, such as a Starting balance, can't: the sheet never offers those categories,
    /// and it would re-sign the amount by type.
    var isEditableInAddSheet: Bool {
        category?.type != .system
    }
}
