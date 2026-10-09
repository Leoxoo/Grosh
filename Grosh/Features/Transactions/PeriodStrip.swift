import SwiftUI

/// The row of periods above the transaction list: `… 08/2026 · Last month · This month · Future`.
/// It starts scrolled to the selected period.
struct PeriodStrip: View {
    let periods: [Period]
    @Binding var selection: Period
    let today: CalendarDay

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    ForEach(periods, id: \.self) { period in
                        tab(for: period)
                            .id(period)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) {
                withAnimation { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }

    private func tab(for period: Period) -> some View {
        let isSelected = period == selection
        return Button {
            selection = period
        } label: {
            Text(period.title(today: today))
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Capsule()
                            .fill(.green)
                            .frame(height: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
