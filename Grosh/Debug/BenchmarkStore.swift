#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// The 16k store: about 16,000 transactions over six years, as a long-time user (or a Money Lover import) has, on disk,
/// made once a day and reused. The benchmarks (`GroshTests/PerformanceBenchmarks.swift`) time the app on it, and a UI
/// test opens the app on it (``UITestStore``). It is compiled into Debug builds only, so the app as shipped never
/// carries it.
enum BenchmarkStore {
    static func open(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: GroshStore.schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: GroshStore.schema, configurations: configuration)
    }

    /// Makes the store at `url` unless it is there already, made today.
    static func prepare(at url: URL, years: Int) throws {
        let stamp = url.appendingPathExtension("made")
        let today = String(CalendarDay.today.rawValue)
        if (try? String(contentsOf: stamp, encoding: .utf8)) == today { return }
        remove(at: url)
        let start = ContinuousClock.now
        let container = try open(at: url)
        try fill(container.mainContext, years: years)
        try today.write(to: stamp, atomically: true, encoding: .utf8)
        print("BENCH made the store in \(ContinuousClock.now - start)")
    }

    /// Removes the store at `url` with what SwiftData keeps beside it, its journal and the folder of Card photos and
    /// Subscription icons kept outside the database, and the stamp saying which day it was made.
    static func remove(at url: URL) {
        for suffix in ["", "-shm", "-wal", ".made"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path + suffix))
        }
        let support = ".\(url.deletingPathExtension().lastPathComponent)_SUPPORT"
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appending(path: support))
    }

    private static func fill(_ context: ModelContext, years: Int) throws {
        try CategorySeeder.seedIfNeeded(in: context)
        var random = SplitMix(seed: 42)
        let categories = try context.fetch(FetchDescriptor<Category>())
        let expenses = categories.filter { $0.type == .expense && !$0.isLocked }
        let incomes = categories.filter { $0.type == .income && !$0.isLocked }
        func role(_ role: LockedRole) -> Category { categories.first { $0.lockedRole == role }! }

        let wallets = ["Checking", "Savings", "Cash", "Travel"].enumerated().map { index, name in
            let wallet = Wallet(name: name, sortOrder: index)
            context.insert(wallet)
            return wallet
        }
        let archived = Wallet(name: "Old bank", sortOrder: 9)
        archived.isArchived = true
        context.insert(archived)
        let people = try ["Sam", "Alex", "Jo"].map { try Person.add(named: $0, in: context) }

        let photoCard = Card(name: "Sapphire", kind: .credit, payingWallet: wallets[0])
        photoCard.imageData = cardPhoto()
        let plainCard = Card(name: "Debit", kind: .debit, payingWallet: wallets[0], color: .green)
        context.insert(photoCard)
        context.insert(plainCard)

        let today = CalendarDay.today
        let first = CalendarMonth(today).adding(months: -12 * years).firstDay
        let notes = ["", "", "", "Lunch", "Groceries for the week", "Coffee", "Taxi home", "Gift", "Dinner with Sam"]
        var day = first
        var count = 0
        let lastDay = today.adding(days: 20)
        while day <= lastDay {
            for _ in 0..<random.next(in: 4...10) {
                let wallet = wallets[random.next(in: 0...9) < 7 ? 0 : random.next(in: 1...3)]
                let transaction = Transaction(
                    amount: Money(cents: -random.next(in: 150...15_000)), day: day, wallet: wallet,
                    category: expenses[random.next(in: 0...(expenses.count - 1))],
                    note: notes[random.next(in: 0...(notes.count - 1))]
                )
                switch random.next(in: 0...9) {
                case 0...2: transaction.card = photoCard
                case 3: transaction.card = plainCard
                default: break
                }
                transaction.isExcludedFromReport = random.next(in: 0...49) == 0
                context.insert(transaction)
                count += 1
            }
            if day.day == 1 || day.day == 15 {
                context.insert(Transaction(
                    amount: Money(cents: random.next(in: 250_000...400_000)), day: day, wallet: wallets[0],
                    category: incomes[0]
                ))
                let link = UUID()
                let out = Transaction(amount: Money(cents: -50_000), day: day, wallet: wallets[0], category: role(.outgoingTransfer))
                let into = Transaction(amount: Money(cents: 50_000), day: day, wallet: wallets[1], category: role(.incomingTransfer))
                out.linkID = link
                into.linkID = link
                context.insert(out)
                context.insert(into)
                count += 3
            }
            if day.day == 10, random.next(in: 0...2) == 0 {
                let loan = Transaction(amount: Money(cents: -random.next(in: 2_000...50_000)), day: day, wallet: wallets[2], category: role(.loan))
                loan.isExcludedFromReport = true
                loan.linkID = UUID()
                loan.reminderDay = day.adding(days: 30)
                context.insert(loan)
                loan.setPeople([people[random.next(in: 0...2)]])
                count += 1
            }
            if count % 2_000 < 12 { try context.save() }
            day = day.adding(days: 1)
        }

        // Some waiting in Recently Deleted, not yet due to be removed.
        let recent = try context.fetch(Transaction.recent(limit: 150, asOf: today))
        for transaction in recent.suffix(100) { transaction.deletedAt = .now.addingTimeInterval(-5 * 86_400) }

        // Recurring transactions, dealt with through today so opening the app has nothing to make.
        for index in 0..<12 {
            let schedule = RecurringTransaction()
            schedule.name = "Schedule \(index)"
            schedule.amountCents = random.next(in: 500...150_000)
            schedule.wallet = wallets[0]
            schedule.category = expenses[index * 3 % expenses.count]
            schedule.kind = [.bill, .subscription, .regular, .purchase][index % 4]
            schedule.amountVaries = index % 4 == 0
            if schedule.kind == .subscription { schedule.iconData = cardPhoto(width: 256, height: 256) }
            schedule.schedule = RepeatSchedule(
                start: first.adding(days: index), rule: RepeatRule(unit: .month, every: 1),
                end: .forever, monthlyDay: .sameDay
            )
            schedule.handledThrough = today
            context.insert(schedule)
        }
        try context.save()
        print("BENCH store holds \(try context.fetchCount(FetchDescriptor<Transaction>())) transactions")
    }

    /// A photographic-looking Card image: JPEG of a noisy gradient, as ``CroppedPhoto`` stores it.
    private static func cardPhoto(width: Int = 960, height: Int = 605) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        var random = SplitMix(seed: 7)
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let noise = Double(random.next(in: 0...40)) / 255
                context.setFillColor(CGColor(
                    red: Double(x) / Double(width) * 0.6 + noise, green: 0.3 + noise, blue: Double(y) / Double(height), alpha: 1
                ))
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return output as Data
    }
}

/// A seeded random number generator, so every store made has the same history.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return range.lowerBound + Int(z % UInt64(range.count))
    }
}

#endif
