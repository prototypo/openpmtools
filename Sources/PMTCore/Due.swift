import Foundation

/// A calendar day with no time, saved as "YYYY-MM-DD".
public struct Day: Codable, Hashable, Comparable, Sendable {
    public let year: Int, month: Int, day: Int

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private init(_ c: DateComponents) { year = c.year!; month = c.month!; day = c.day! }

    /// Strict: "2026-11-14" only, and a real date.
    public init?(_ text: String) {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let n = text.split(separator: "-").map { Int($0)! }
        let c = DateComponents(year: n[0], month: n[1], day: n[2])
        guard let date = Day.utc.date(from: c),
              Day.utc.dateComponents([.year, .month, .day], from: date) == c else { return nil }
        self.init(c)
    }

    public var text: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// The local calendar day at `now`.
    public static func today(now: Date = Date(), calendar: Calendar = .current) -> Day {
        Day(calendar.dateComponents([.year, .month, .day], from: now))
    }

    private var date: Date { Day.utc.date(from: DateComponents(year: year, month: month, day: day))! }

    public func adding(days: Int) -> Day {
        Day(Day.utc.dateComponents([.year, .month, .day], from: Day.utc.date(byAdding: .day, value: days, to: date)!))
    }

    public static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = Day(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad due date '\(s)'"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(text)
    }
}

public enum Priority: String, Codable, CaseIterable, Comparable, Sendable {
    case low, medium, high

    public init?(argument: String) { self.init(rawValue: argument.lowercased()) }
    public var label: String { rawValue.capitalized }
    public var symbol: String { switch self { case .low: "↓"; case .medium: "!"; case .high: "!!" } }
    private var rank: Int { Priority.allCases.firstIndex(of: self)! }
    public static func < (a: Priority, b: Priority) -> Bool { a.rank < b.rank }
}

/// How close a due date is: green, yellow, red.
public enum Urgency: Sendable { case later, soon, now }

extension Card {
    /// nil when there is no due date. Due today or before: now; within 2 days: soon.
    public func urgency(today: Day) -> Urgency? {
        guard let due else { return nil }
        if due <= today { return .now }
        return due <= today.adding(days: 2) ? .soon : .later
    }

    public func isOverdue(today: Day) -> Bool { due.map { $0 < today } ?? false }

    /// The set priority, raised (never lowered) by a near due date. Never saved.
    public func effectivePriority(today: Day) -> Priority? {
        let floor: Priority? = switch urgency(today: today) {
        case .now: .high
        case .soon: .medium
        default: nil
        }
        return [priority, floor].compactMap { $0 }.max()
    }

    public func isRaised(today: Day) -> Bool { effectivePriority(today: today) != priority }
}

/// Words for a due date: "Overdue · 12 Nov", "Today", "Tomorrow", "In 2 days", "20 Nov".
public func dueText(_ due: Day, today: Day) -> String {
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    let plain = "\(due.day) \(months[due.month - 1])"
    if due < today { return "Overdue · " + plain }
    if due == today { return "Today" }
    if due == today.adding(days: 1) { return "Tomorrow" }
    if due == today.adding(days: 2) { return "In 2 days" }
    return plain
}

/// Display order: effective priority (High first), then due date (earliest first, none last), then input order.
public func displayOrder<T>(_ items: [T], today: Day, card: (T) -> Card) -> [T] {
    func rank(_ p: Priority?) -> Int { p.map { Priority.allCases.firstIndex(of: $0)! + 1 } ?? 0 }
    return items.enumerated().sorted { a, b in
        let x = card(a.element), y = card(b.element)
        let px = rank(x.effectivePriority(today: today)), py = rank(y.effectivePriority(today: today))
        if px != py { return px > py }
        if x.due != y.due {
            guard let dx = x.due else { return false }
            guard let dy = y.due else { return true }
            return dx < dy
        }
        return a.offset < b.offset
    }.map(\.element)
}
