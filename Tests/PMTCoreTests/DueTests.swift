import Foundation
import Testing
@testable import PMTCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let today = Day("2026-11-14")!

private func card(_ id: String, _ p: Priority? = nil, due: String? = nil) -> Card {
    Card(id: id, title: id, created: t0, due: due.flatMap(Day.init), priority: p)
}

@Test func dayParsesAndPrints() {
    #expect(Day("2026-11-14")?.text == "2026-11-14")
    #expect(Day("2026-12-31")!.adding(days: 1).text == "2027-01-01")
    #expect(Day("2026-11-14")! < Day("2026-11-15")!)
}

@Test func dayRejectsBadText() {
    for s in ["2026-02-30", "14/11/2026", "2026-1-5", "", "2026-11-14x"] { #expect(Day(s) == nil, "\(s)") }
}

@Test func todayUsesCalendarTimeZone() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Pacific/Auckland")!
    let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!
    #expect(Day.today(now: now, calendar: cal).text == "2026-11-15")
}

@Test func urgencyAndRaise() {
    let overdue = card("a", due: "2026-11-13")
    #expect(overdue.urgency(today: today) == .now && overdue.isOverdue(today: today))
    #expect(overdue.effectivePriority(today: today) == .high && overdue.isRaised(today: today))
    let dueToday = card("b", due: "2026-11-14")
    #expect(dueToday.urgency(today: today) == .now && !dueToday.isOverdue(today: today))
    #expect(dueToday.effectivePriority(today: today) == .high)
    let soon = card("c", due: "2026-11-16")
    #expect(soon.urgency(today: today) == .soon && soon.effectivePriority(today: today) == .medium)
    let later = card("d", .low, due: "2026-11-17")
    #expect(later.urgency(today: today) == .later && later.effectivePriority(today: today) == .low)
    let high = card("e", .high, due: "2026-11-16")
    #expect(high.effectivePriority(today: today) == .high && !high.isRaised(today: today))
    let none = card("f", .medium)
    #expect(none.urgency(today: today) == nil && none.effectivePriority(today: today) == .medium && !none.isRaised(today: today))
}

@Test func displayOrderSorts() {
    let cards = [card("none"), card("low", .low), card("h20", .high, due: "2026-11-20"),
                 card("n15", due: "2026-11-15"), card("h18", .high, due: "2026-11-18"), card("none2")]
    #expect(displayOrder(cards, today: today) { $0 }.map(\.id) == ["h18", "h20", "n15", "low", "none", "none2"])
}

@Test func oldCardsDecodeWithoutNewKeys() throws {
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let old = try dec.decode(Card.self, from: Data(#"{"id":"a","title":"T","created":"2026-11-01T00:00:00Z"}"#.utf8))
    #expect(old.due == nil && old.priority == nil)
    let out = String(decoding: try enc.encode(old), as: UTF8.self)
    #expect(!out.contains("due") && !out.contains("priority"))
    let full = card("b", .high, due: "2026-11-14")
    let text = String(decoding: try enc.encode(full), as: UTF8.self)
    #expect(text.contains(#""due" : "2026-11-14""#) && text.contains(#""priority" : "high""#))
    #expect(try dec.decode(Card.self, from: Data(text.utf8)) == full)
}

@Test func dueWordsAndSymbols() {
    #expect(dueText(Day("2026-11-12")!, today: today) == "Overdue · 12 Nov")
    #expect(dueText(today, today: today) == "Today")
    #expect(dueText(Day("2026-11-15")!, today: today) == "Tomorrow")
    #expect(dueText(Day("2026-11-16")!, today: today) == "In 2 days")
    #expect(dueText(Day("2026-11-20")!, today: today) == "20 Nov")
}

@Test func archivedKeepsDueAndPriority() {
    let c = card("a", .low, due: "2026-11-20")
    #expect(ArchivedCard(c, fromColumn: "To Do", done: t0).card == c)
}

@Test func priorityArguments() {
    #expect(Priority(argument: "HIGH") == .high && Priority(argument: "urgent") == nil)
    #expect(Priority.medium.symbol == "!" && Priority.high.label == "High")
}

@Test func dayRejectsNonASCIIDigits() {
    #expect(Day("٢٠٢٦-١١-١٤") == nil)
}

@Test func todayIsAlwaysGregorian() {
    var cal = Calendar(identifier: .japanese)
    cal.timeZone = TimeZone(identifier: "Pacific/Auckland")!
    let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!
    #expect(Day.today(now: now, calendar: cal).text == "2026-11-15")
    let d = Day("2026-03-29")!
    #expect(Day.today(now: d.localDate) == d)
}

@Test func dueSpokenIsPlainEnglish() {
    #expect(dueSpoken(Day("2026-11-12")!, today: today) == "overdue, was due 12 November")
    #expect(dueSpoken(today, today: today) == "due today")
    #expect(dueSpoken(Day("2026-11-15")!, today: today) == "due tomorrow")
    #expect(dueSpoken(Day("2026-11-16")!, today: today) == "due in 2 days")
    #expect(dueSpoken(Day("2026-11-20")!, today: today) == "due 20 November")
    #expect(dueSpoken(Day("2026-11-12")!, today: nil) == "due 12 November")
}
