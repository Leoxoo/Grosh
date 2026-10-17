import SwiftUI

/// The Time Range choices the Transactions tab's "…" menu and the Report's calendar button both offer: each preset by
/// name, then Custom…, which asks the owner to open its custom range editor (see ``View/customRangeEditor(_:isPresented:latest:)``).
struct TimeRangeChoices: View {
    @Binding var timeRange: TimeRange
    /// Opens the custom range editor.
    let pickCustom: () -> Void

    var body: some View {
        Picker("Time Range", selection: presetSelection) {
            ForEach(TimeRange.presets, id: \.self) { range in
                Text(range.title).tag(Optional(range))
            }
        }
        .pickerStyle(.inline)

        Button(action: pickCustom) {
            if case .custom = timeRange {
                Label("Custom…", systemImage: "checkmark")
            } else {
                Text("Custom…")
            }
        }
    }

    /// The preset the time range is, or `nil` for a custom range, so the picker checks none of them.
    private var presetSelection: Binding<TimeRange?> {
        Binding(
            get: { TimeRange.presets.contains(timeRange) ? timeRange : nil },
            set: { if let range = $0 { timeRange = range } }
        )
    }
}

extension View {
    /// Presents the custom range editor while `isPresented`, starting from the current custom range or this month, and
    /// sets `timeRange` to the days it picks. `latest` is the last day that can be picked, or `nil` for no limit.
    func customRangeEditor(
        _ timeRange: Binding<TimeRange>, isPresented: Binding<Bool>, latest: CalendarDay? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            CustomRangeEditor(days: timeRange.wrappedValue.customRangeStart(today: .today), latest: latest) {
                timeRange.wrappedValue = .custom($0)
            }
        }
    }
}
