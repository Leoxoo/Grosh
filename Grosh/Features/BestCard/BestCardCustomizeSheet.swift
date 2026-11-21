import SwiftUI

/// Best Card's Customize: every Reward category in the user's order, checked when its tile shows. Tapping one shows or
/// hides its tile, and dragging reorders them.
struct BestCardCustomizeSheet: View {
    /// The layout as the app keeps it (``BestCardLayout/stored``).
    @Binding var stored: String
    /// Every Reward category in list order, the user's own included.
    let listed: [RewardCategory]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let layout = BestCardLayout.read(stored, listed: listed)
        NavigationStack {
            List {
                Section {
                    ForEach(layout.arranged(listed), id: \.reward.id) { entry in
                        Button {
                            stored = layout.toggled(entry.reward.id, in: listed).stored
                        } label: {
                            HStack(spacing: 12) {
                                SymbolCircle(symbolName: entry.reward.symbolName, color: entry.reward.color, size: 28)
                                Text(entry.reward.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if entry.isShown {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(entry.isShown ? .isSelected : [])
                        .accessibilityIdentifier("BestCard.customize.\(entry.reward.id)")
                    }
                    .onMove { source, destination in
                        stored = layout.moved(from: source, to: destination, in: listed).stored
                    }
                } footer: {
                    Text(Strings.BestCard.customizeFooter)
                }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle(Strings.BestCard.customize)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.done) { dismiss() }
                }
            }
        }
    }
}
