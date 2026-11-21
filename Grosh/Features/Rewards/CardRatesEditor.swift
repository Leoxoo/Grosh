import SwiftData
import SwiftUI

/// The rate editor a Card's Rewards pencil opens. A Custom card's rates are the user's own, and whether it earns cash
/// back or points or miles is set here. On a linked Card, changing, adding or removing a rate makes an Edited rate,
/// which Reset to catalog takes back (ADR-0014).
struct CardRatesEditor: View {
    let card: Card

    @Environment(\.dismiss) private var dismiss
    @Environment(\.rewardsCatalog) private var catalog
    @Environment(\.today) private var today
    @Query(RewardCategories.ownInOrder) private var ownRewardCategories: [OwnRewardCategory]
    @State private var editing: Editing?
    @State private var errorMessage: String?

    /// The rate the form is open for: a new one, or one the Card has.
    private enum Editing: Identifiable {
        case add
        case edit(EditableRate)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let row): row.id
            }
        }
    }

    var body: some View {
        let rewards = CardRewards(of: card, in: catalog)
        let own = ownRewardCategories.map(RewardCategory.init)
        let rows = rewards.editable(on: today, own: own)
        NavigationStack {
            Form {
                if rewards.entry == nil {
                    Section {
                        Picker(Strings.Rewards.earns, selection: rewardKind(rewards.rewardKind)) {
                            Text(Strings.Rewards.cashBack).tag(RewardKind.cashback)
                            Text(Strings.Rewards.pointsOrMiles).tag(RewardKind.points)
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(Strings.Rewards.earnsFooter)
                    }
                }

                Section {
                    ForEach(rows) { row in
                        if let shown = row.shown {
                            Button {
                                editing = .edit(row)
                            } label: {
                                CardRateRow(rate: shown)
                            }
                            .tint(.primary)
                            .swipeActions {
                                Button(Strings.Common.remove, role: .destructive) { remove(row) }
                                if row.canReset {
                                    Button(Strings.Rewards.resetToCatalog) { reset(row) }
                                }
                            }
                            .contextMenu {
                                if row.canReset {
                                    Button(Strings.Rewards.resetToCatalog, systemImage: "arrow.uturn.backward") { reset(row) }
                                }
                                Button(Strings.Common.remove, systemImage: "trash", role: .destructive) { remove(row) }
                            }
                        }
                    }
                    Button(Strings.Rewards.addRate, systemImage: "plus") { editing = .add }
                } header: {
                    Text(Strings.Rewards.rates)
                } footer: {
                    if rewards.entry != nil {
                        Text(Strings.Rewards.editedRatesFooter)
                    }
                }

                let removed = rows.filter { $0.shown == nil }
                if !removed.isEmpty {
                    Section(Strings.Rewards.removed) {
                        ForEach(removed) { row in
                            HStack {
                                Text(row.reward.name)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(Strings.Rewards.resetToCatalog) { reset(row) }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Strings.Rewards.rates)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.done) { dismiss() }
                }
            }
            .sheet(item: $editing) { target in
                EnteredRateForm(
                    card: card, start: start(for: target, rewards), replacing: replacing(target),
                    isCatalogRate: isCatalogRate(target), rewards: RewardCategory.listed(own: own),
                    earnsPoints: rewards.rewardKind.earnsPoints, today: today
                )
            }
            .errorAlert(Strings.Cards.couldntChange, message: $errorMessage)
        }
    }

    private func rewardKind(_ current: RewardKind) -> Binding<RewardKind> {
        Binding(
            get: { current.earnsPoints ? .points : .cashback },
            set: { kind in
                Log.store.perform("Setting what a Card earns", errorMessage: &errorMessage) { try card.setRewardKind(kind) }
            }
        )
    }

    /// What the form starts as: the rate to change (``EnteredRate/init(editing:earnsPoints:pointValueCents:)``), or a
    /// new rate on Everything else.
    private func start(for target: Editing, _ rewards: CardRewards) -> EnteredRate {
        switch target {
        case .edit(let row):
            EnteredRate(editing: row, earnsPoints: rewards.rewardKind.earnsPoints, pointValueCents: rewards.pointValueCents)
        case .add:
            EnteredRate(reward: RewardCategory.everythingElse.id, rate: nil)
        }
    }

    /// Whether the form opens on the catalog's own rate, which saving unchanged leaves as it is.
    private func isCatalogRate(_ target: Editing) -> Bool {
        if case .edit(let row) = target { row.entered == nil } else { false }
    }

    private func replacing(_ target: Editing) -> String? {
        if case .edit(let row) = target { row.reward.id } else { nil }
    }

    private func remove(_ row: EditableRate) {
        Log.store.perform("Removing a Card's rate", errorMessage: &errorMessage) {
            try card.removeRate(for: row.reward.id, in: catalog)
        }
    }

    private func reset(_ row: EditableRate) {
        Log.store.perform("Resetting a Card's rate to the catalog's", errorMessage: &errorMessage) {
            try card.resetRate(for: row.reward.id)
        }
    }
}

/// Adds a rate to a Card or changes one: its Reward category, the rate (% for cash back, × for points or miles), and
/// optionally a cap and dates.
private struct EnteredRateForm: View {
    let card: Card
    let start: EnteredRate
    /// The Reward category the rate had when the form opened, which a changed category replaces.
    let replacing: String?
    /// Whether it opened on the catalog's own rate: saved unchanged, it stays the catalog's rather than becoming an
    /// Edited rate, so it keeps following the catalog.
    let isCatalogRate: Bool
    let rewards: [RewardCategory]
    let earnsPoints: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.rewardsCatalog) private var catalog
    @State private var reward: String
    @State private var rateText: String
    @State private var hasCap: Bool
    @State private var capText: String
    @State private var capPeriod: RateCapPeriod
    @State private var hasFrom: Bool
    @State private var from: CalendarDay
    @State private var hasTo: Bool
    @State private var to: CalendarDay
    private let saver = SheetSaver(Strings.Cards.couldntSave)

    init(
        card: Card, start: EnteredRate, replacing: String?, isCatalogRate: Bool, rewards: [RewardCategory],
        earnsPoints: Bool, today: CalendarDay
    ) {
        self.card = card
        self.start = start
        self.replacing = replacing
        self.isCatalogRate = isCatalogRate
        self.rewards = rewards
        self.earnsPoints = earnsPoints
        _reward = State(initialValue: start.reward)
        _rateText = State(initialValue: start.rate.map(CardRateText.number) ?? "")
        _hasCap = State(initialValue: start.capAmount != nil)
        _capText = State(initialValue: start.capAmount.map(CardRateText.number) ?? "")
        _capPeriod = State(initialValue: start.capPeriod ?? .month)
        _hasFrom = State(initialValue: start.from != nil)
        _from = State(initialValue: start.from ?? today)
        _hasTo = State(initialValue: start.to != nil)
        _to = State(initialValue: start.to ?? today)
    }

    /// The rate as the form holds it. Text that isn't a number makes it none, which the rules refuse.
    private var rate: EnteredRate {
        var rate = EnteredRate(reward: reward, rate: CardRateText.parseNumber(rateText))
        if hasCap {
            rate.capAmount = CardRateText.parseNumber(capText) ?? 0
            rate.capPeriod = capPeriod
        }
        rate.from = hasFrom ? from : nil
        rate.to = hasTo ? to : nil
        return rate
    }

    /// Why the rate can't be saved as it is, if it can't.
    private var problem: Error? {
        do {
            try rate.validate()
            return nil
        } catch {
            return error
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(Strings.Rewards.rewardCategory, selection: $reward) {
                        ForEach(rewards) { reward in
                            Text(reward.name).tag(reward.id)
                        }
                    }
                    LabeledContent(Strings.Rewards.rate) {
                        HStack(spacing: 2) {
                            TextField(Strings.Rewards.rate, text: $rateText)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text(verbatim: earnsPoints ? "×" : "%")
                        }
                    }
                } footer: {
                    if !rateText.isEmpty, let problem {
                        Text(problem.localizedDescription)
                            .foregroundStyle(.invalid)
                    }
                }

                Section {
                    Toggle(Strings.Rewards.cap, isOn: $hasCap)
                    if hasCap {
                        TextField(Strings.Common.amount, text: $capText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Picker(Strings.Rewards.capEach, selection: $capPeriod) {
                            ForEach(RateCapPeriod.allCases, id: \.self) { period in
                                Text(period.title).tag(period)
                            }
                        }
                    }
                } footer: {
                    Text(Strings.Rewards.capFooter)
                }

                Section {
                    Toggle(Strings.Rewards.startsOn, isOn: $hasFrom)
                    if hasFrom {
                        DayPicker(title: Strings.Rewards.startsOn, day: $from)
                    }
                    Toggle(Strings.Rewards.endsOn, isOn: $hasTo)
                    if hasTo {
                        DayPicker(title: Strings.Rewards.endsOn, day: $to)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(replacing == nil ? Strings.Rewards.addRate : Strings.Rewards.editRate)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.Common.save) {
                        saver.save("Saving a Card's rate") {
                            guard !(isCatalogRate && rate == start) else { return }
                            try card.saveRate(in: catalog, rate, replacing: replacing)
                        }
                    }
                    .disabled(problem != nil)
                }
            }
            .failureAlert(saver)
        }
    }
}

extension RateCapPeriod {
    /// The period as the cap's Each picker names it.
    var title: String {
        switch self {
        case .month: String(localized: Strings.Rewards.capMonth)
        case .quarter: String(localized: Strings.Rewards.capQuarter)
        case .year: String(localized: Strings.Rewards.capYear)
        case .statement: String(localized: Strings.Rewards.capStatement)
        }
    }
}
