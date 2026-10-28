import SwiftData
import SwiftUI

/// The Select Wallet sheet the Wallet selector opens: the Total on its own card, then the wallets included in it and
/// those left out, each with its balance today. Tapping a row selects it and closes the sheet; Close leaves the
/// selection as it was. Wallets are added, reordered and archived in Account → Wallets, not here.
struct SelectWalletSheet: View {
    @Binding var selection: WalletSelection
    let today: CalendarDay

    @Query(Wallet.unarchived) private var wallets: [Wallet]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let choices = WalletSelectorChoices(wallets: wallets, asOf: today)
        NavigationStack {
            List {
                Section {
                    row(choices.total)
                        .groupedRow(.only)
                }
                if !choices.includedInTotal.isEmpty {
                    Section(Strings.Transactions.includedInTotal) {
                        GroupedForEach(choices.includedInTotal) { row($0) }
                    }
                }
                if !choices.notInTotal.isEmpty {
                    Section(Strings.Transactions.notInTotal) {
                        GroupedForEach(choices.notInTotal) { row($0) }
                    }
                }
            }
            .roundedSectionsListStyle()
            .navigationTitle(Strings.Transactions.selectWallet)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.close) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 360, idealHeight: 480)
        #endif
    }

    /// One row: the choice's icon, its name with its balance underneath, and a checkmark when it is the selection.
    private func row(_ choice: WalletSelectorChoices.Choice) -> some View {
        let isSelected = choice.selection == selection
        return Button {
            selection = choice.selection
            dismiss()
        } label: {
            HStack(spacing: 12) {
                icon(of: choice)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.selection.name)
                    Text(choice.balance.formatted())
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The Total's plain globe, or the wallet's colored symbol circle as Home draws it.
    @ViewBuilder
    private func icon(of choice: WalletSelectorChoices.Choice) -> some View {
        switch choice.selection {
        case .total:
            Image(systemName: WalletSelection.total.symbolName)
                .font(.title2)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        case .wallet(let wallet):
            SymbolCircle(symbolName: wallet.symbolName, color: wallet.color)
        }
    }
}
