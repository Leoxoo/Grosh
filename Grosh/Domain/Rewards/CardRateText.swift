import Foundation

/// How a Card's rates read.
nonisolated enum CardRateText {
    /// `rate` (in percent) as "3%" or "1.5%".
    static func percent(_ rate: Double) -> String {
        (rate / 100).formatted(.percent.precision(.fractionLength(0...2)))
    }

    /// `value` as "3" or "1.25".
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// The number typed in `text`, in the user's own way of writing one, or `nil` when it isn't one.
    static func parseNumber(_ text: String) -> Double? {
        try? Double(text.trimmingCharacters(in: .whitespaces), format: .number)
    }

    /// A catalog amount in US dollars, as "$2,500".
    static func dollars(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    /// A quarter's months as "Oct–Dec".
    static func months(from: CalendarDay, to: CalendarDay) -> String {
        let month = Date.FormatStyle().month(.abbreviated)
        return "\(from.date().formatted(month))–\(to.date().formatted(month))"
    }

    /// A rate earned only paid a certain way or at certain merchants: "2% with Apple Pay", "5% Online shopping at
    /// Amazon".
    static func condition(of rate: CardRate) -> LocalizedStringResource {
        let percent = self.percent(rate.effectiveRate)
        let on = rate.reward == .everythingElse ? percent : "\(percent) \(rate.reward.name)"
        if let paysWith = rate.rule?.paysWith {
            return Strings.Rewards.paidWith(on, paysWith)
        }
        return Strings.Rewards.atMerchants(on, (rate.rule?.merchants ?? []).formatted(.list(type: .or)))
    }

    /// `day` as the user's calendar writes a date.
    static func day(_ day: CalendarDay) -> String {
        day.date().formatted(date: .abbreviated, time: .omitted)
    }

    /// A rate's dates as "Oct 1, 2026 to Dec 31, 2026", "From …" or "Until …"; `nil` for none.
    static func dates(from: CalendarDay?, to: CalendarDay?) -> String? {
        switch (from.map(day), to.map(day)) {
        case let (from?, to?): String(localized: Strings.Rewards.datesBetween(from, to))
        case let (from?, nil): String(localized: Strings.Rewards.datesFrom(from))
        case let (nil, to?): String(localized: Strings.Rewards.datesUntil(to))
        case (nil, nil): nil
        }
    }

    /// A rate's cap as "Up to $1,500 a quarter", in `currencyCode`.
    static func cap(_ cap: RateCap, currencyCode: String) -> String? {
        guard let amount = cap.amount.map({ money($0, currencyCode: currencyCode) }) else {
            return cap.isUnknown ? String(localized: Strings.Rewards.capUnknown) : nil
        }
        return switch cap.period {
        case .month: String(localized: Strings.Rewards.capPerMonth(amount))
        case .quarter: String(localized: Strings.Rewards.capPerQuarter(amount))
        case .year: String(localized: Strings.Rewards.capPerYear(amount))
        case .statement: String(localized: Strings.Rewards.capPerStatement(amount))
        case nil: String(localized: Strings.Rewards.capTotal(amount))
        }
    }

    /// `amount` in `currencyCode`, as "$2,500".
    static func money(_ amount: Double, currencyCode: String) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0...2)))
    }
}
