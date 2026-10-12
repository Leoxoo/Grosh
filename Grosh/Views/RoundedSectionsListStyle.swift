import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    /// rounded group, where `position` is its place among the section's rows, and `isSelected` highlights it. The
    /// group's background takes the place of the list's own highlight, which ``HidesListHighlight`` switches off.
    /// iPhone and iPad group the rows themselves.
    func groupedRow(_ position: GroupPosition, isSelected: Bool = false) -> some View {
        #if os(macOS)
        padding(.bottom, position.gapBelow)
            .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
            .listRowSeparator(.hidden)
            .listRowBackground(GroupedRowBackground(position: position, isSelected: isSelected))
            .background(HidesListHighlight())
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

    /// Whether the group is rounded at the bottom, which is the section's last row.
    fileprivate var roundsBottom: Bool { self == .only || self == .last }

    /// The gap below the section's last row, before the next section's header. It is padding in the row's content
    /// rather than a bigger bottom inset, and the group's background stops short of it, so the group ends at the row's
    /// content.
    fileprivate var gapBelow: CGFloat { roundsBottom ? 12 : 0 }

    /// Whether a divider separates the row from the next one in its section.
    fileprivate var hasDivider: Bool { self == .first || self == .middle }
}

/// A `ForEach` over rows of one section, each placed in the section's rounded group on Mac, as
/// ``View/groupedRow(_:isSelected:)`` does. The section's other rows sit before or after these: `rowsBefore` counts the
/// ones before, and `rowsInSection` is the section's row count in all when some sit after these too.
struct GroupedForEach<Element: Identifiable, Content: View>: View {
    let elements: [Element]
    let rowsBefore: Int
    let rowsInSection: Int?
    let isSelected: (Element) -> Bool
    let content: (Element) -> Content

    init(
        _ elements: [Element],
        rowsBefore: Int = 0,
        rowsInSection: Int? = nil,
        isSelected: @escaping (Element) -> Bool = { _ in false },
        @ViewBuilder content: @escaping (Element) -> Content
    ) {
        self.elements = elements
        self.rowsBefore = rowsBefore
        self.rowsInSection = rowsInSection
        self.isSelected = isSelected
        self.content = content
    }

    var body: some View {
        let count = rowsInSection ?? rowsBefore + elements.count
        ForEach(Array(elements.enumerated()), id: \.element.id) { index, element in
            content(element)
                .groupedRow(GroupPosition(index: rowsBefore + index, count: count), isSelected: isSelected(element))
        }
    }
}

/// A row's piece of its section's rounded group on Mac: the group's rounded corners at its first and last rows, a
/// divider under every row but the last and the selected one, and the highlight of a selected row.
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
        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
        .overlay(alignment: .bottom) {
            if position.hasDivider && !isSelected {
                Divider()
                    .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, position.gapBelow)
    }
}

#if os(macOS)
/// Switches off the list's own highlight, the full-width one a selected row gets on Mac, so the row's group draws its
/// selection inside its shape. The table keeps its selection and arrow-key moves. Each row holds one of these, which
/// finds the table the row sits in.
private struct HidesListHighlight: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HighlightSwitch()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// An empty view that turns off the selection highlight of the table it sits in. It takes no clicks.
private final class HighlightSwitch: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        var view = superview
        while let current = view, !(current is NSTableView) {
            view = current.superview
        }
        (view as? NSTableView)?.selectionHighlightStyle = .none
    }
}
#endif
