import SwiftUI

/// A read-only wallet row: the wallet's icon and name, or a dash when there is none (such as the deleted half of a
/// transfer).
struct WalletLabel: View {
    let title: LocalizedStringKey
    let wallet: Wallet?

    var body: some View {
        LabeledContent(title) {
            if let wallet {
                HStack(spacing: 6) {
                    Image(systemName: wallet.symbolName)
                        .foregroundStyle(wallet.color.color)
                    Text(wallet.name)
                }
            } else {
                Text("—")
            }
        }
    }
}
