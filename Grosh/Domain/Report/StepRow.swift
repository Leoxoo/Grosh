import Foundation

/// One Step of a Net income or Trend screen: its span, its name, and what counts toward Income and Spent in it.
struct StepRow: Identifiable {
    let step: Step
    let title: String
    let totals: PeriodTotals

    var id: Step { step }

    /// The Step's Income or Spent, as the side's bar and row show it.
    func total(of side: SpentOrIncome) -> Money {
        switch side {
        case .income: totals.income
        case .spent: totals.spent
        }
    }

    /// One row per Step of `days` on a screen showing `timeRange`, oldest first, each with what `counted` adds up to in its
    /// days. The Steps cover `days` once each, so the rows' totals add up to the period's.
    static func rows(
        of counted: [CountedAmount], for timeRange: TimeRange, over days: DayRange, today: CalendarDay,
        firstWeekday: Int = Calendar.current.firstWeekday
    ) -> [StepRow] {
        Step.steps(for: timeRange, over: days, today: today, firstWeekday: firstWeekday).map { step in
            StepRow(
                step: step, title: step.title(),
                totals: PeriodTotals(of: counted.filter { step.contains($0.day) })
            )
        }
    }
}
