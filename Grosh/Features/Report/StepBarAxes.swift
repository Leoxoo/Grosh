import Charts
import SwiftUI

extension View {
    /// The axes and size of a details screen's bar chart of Steps: each Step named under its bars, amounts on the leading
    /// edge in `currencyCode`, 260 points tall. The rows below the chart list the Steps with their totals, so VoiceOver
    /// reads those instead.
    func stepBarAxes(currencyCode: String) -> some View {
        chartXAxis {
            // Anchored, as the default label of a bar's category isn't one Charts accepts.
            AxisMarks { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(anchor: .top)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel(anchor: .trailing) {
                    if let cents = value.as(Int.self) {
                        Text(Money(cents: cents, currencyCode: currencyCode).formatted())
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 260)
        .accessibilityHidden(true)
    }
}
