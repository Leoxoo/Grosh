import SwiftUI

extension View {
    /// The list style of the lists that group their rows by section, as iPhone does: each section a rounded group. Mac
    /// has no grouped list style, so there the list is plain and each row takes its place in its section's group with
    /// ``groupedRow(_:isSelected:)``. Without this, a list in a split view's sidebar column floats its rows outside any
    /// group.
    func roundedSectionsListStyle() -> some View {
        #if os(macOS)
        listStyle(.plain)
            .scrollContentBackground(.hidden)
        #else
        listStyle(.insetGrouped)
        #endif
    }

    /// A row of a section styled by ``roundedSectionsListStyle()``. On Mac the row is drawn as part of its section's
    /// rounded group, where `position` is its place among the section's rows, and `isSelected` highlights it, since the
    /// group's background takes the place of the list's own highlight. iPhone and iPad group the rows themselves.
    func groupedRow(_ position: GroupPosition, isSelected: Bool = false) -> some View {
        #if os(macOS)
        listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: position.roundsBottom ? 18 : 6, trailing: 24))
            .listRowSeparator(.hidden)
            .listRowBackground(GroupedRowBackground(position: position, isSelected: isSelected))
        #else
        self
        #endif
    }
}

/// Where a row sits among the rows of its section, first to last.
enum GroupPosition {
    case only, first, middle, last

    init(index: Int, count: Int) {
        let isFirst = index == 0
        let isLast = index == count - 1
        self = isFirst ? (isLast ? .only : .first) : (isLast ? .last : .middle)
    }

    /// Whether the group is rounded at the top, which is the section's first row.
    fileprivate var roundsTop: Bool { self == .only || self == .first }

    /// Whether the group is rounded at the bottom, which is the section's last row. The group then leaves a gap below
    /// it, so the next section's header has room.
    fileprivate var roundsBottom: Bool { self == .only || self == .last }

    /// Whether a divider separates the row from the next one in its section.
    fileprivate var hasDivider: Bool { self == .first || self == .middle }
}

/// A row's piece of its section's rounded group on Mac: the group's rounded corners at its first and last rows, a
/// divider under every row but the last, and the highlight of a selected row.
private struct GroupedRowBackground: View {
    let position: GroupPosition
    let isSelected: Bool

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: position.roundsTop ? 10 : 0,
            bottomLeadingRadius: position.roundsBottom ? 10 : 0,
            bottomTrailingRadius: position.roundsBottom ? 10 : 0,
            topTrailingRadius: position.roundsTop ? 10 : 0
        )
        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
        .overlay(alignment: .bottom) {
            if position.hasDivider {
                Divider()
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, position.roundsBottom ? 12 : 0)
    }
}
