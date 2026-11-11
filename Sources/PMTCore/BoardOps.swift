import Foundation

public struct CardLocation: Hashable, Sendable {
    public var project: UUID
    /// nil means the card is archived.
    public var column: String?
    public var card: Card
    public var done: Date?
}

private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
private func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

extension BoardsFile {
    public func board(for project: UUID) -> Board? { boards.first { $0.project == project } }

    // MARK: lookup helpers

    private func boardIndex(_ project: UUID) throws -> Int {
        guard let i = boards.firstIndex(where: { $0.project == project }) else { throw PMTError.noBoard }
        return i
    }

    private func columnIndex(_ name: String, in b: Int) throws -> Int {
        let n = trimmed(name)
        guard let i = boards[b].columns.firstIndex(where: { same($0.name, n) }) else { throw PMTError.noSuchColumn(n) }
        return i
    }

    /// Where a card lives: board, column (nil = archive) and position.
    private func find(_ id: String) throws -> (board: Int, column: Int?, index: Int) {
        let id = trimmed(id)
        for (b, board) in boards.enumerated() {
            for (c, col) in board.columns.enumerated() {
                if let i = col.tasks.firstIndex(where: { same($0.id, id) }) { return (b, c, i) }
            }
            if let i = board.archive.firstIndex(where: { same($0.id, id) }) { return (b, nil, i) }
        }
        throw PMTError.noSuchTask(id)
    }

    /// Like `find`, but open cards only.
    private func findOpen(_ id: String) throws -> (board: Int, column: Int, index: Int) {
        let r = try find(id)
        guard let c = r.column else { throw PMTError.noSuchTask(trimmed(id)) }
        return (r.board, c, r.index)
    }

    public func locate(_ id: String) -> CardLocation? {
        guard let r = try? find(id) else { return nil }
        let b = boards[r.board]
        if let c = r.column { return CardLocation(project: b.project, column: b.columns[c].name, card: b.columns[c].tasks[r.index], done: nil) }
        let a = b.archive[r.index]
        return CardLocation(project: b.project, column: nil, card: a.card, done: a.done)
    }

    // MARK: boards

    public mutating func createBoard(project: UUID, columns names: [String]) throws {
        let names = names.map(trimmed)
        if names.contains("") { throw PMTError.emptyName }
        for (i, n) in names.enumerated() where names[..<i].contains(where: { same($0, n) }) {
            throw PMTError.duplicateColumn(n)
        }
        if names.count < 2 { throw PMTError.tooFewColumns }
        if board(for: project) != nil { throw PMTError.boardExists }
        boards.append(Board(project: project, columns: names.map { Column(name: $0) }))
    }

    public mutating func deleteBoard(project: UUID, force: Bool) throws {
        let b = try boardIndex(project)
        let has = !boards[b].archive.isEmpty || boards[b].columns.contains { !$0.tasks.isEmpty }
        if has && !force { throw PMTError.boardHasTasks }
        boards.remove(at: b)
    }

    // MARK: columns

    public mutating func addColumn(_ name: String, project: UUID, at index: Int? = nil) throws {
        let b = try boardIndex(project)
        let n = trimmed(name)
        if n.isEmpty { throw PMTError.emptyName }
        if boards[b].columns.contains(where: { same($0.name, n) }) { throw PMTError.duplicateColumn(n) }
        let working = boards[b].columns.count - 1
        boards[b].columns.insert(Column(name: n), at: min(max(index ?? working, 0), working))
    }

    public mutating func renameColumn(_ name: String, to new: String, project: UUID) throws {
        let b = try boardIndex(project)
        let c = try columnIndex(name, in: b)
        let n = trimmed(new)
        if n.isEmpty { throw PMTError.emptyName }
        if boards[b].columns.enumerated().contains(where: { $0.offset != c && same($0.element.name, n) }) {
            throw PMTError.duplicateColumn(n)
        }
        boards[b].columns[c].name = n
    }

    public mutating func moveColumn(_ name: String, to index: Int, project: UUID) throws {
        let b = try boardIndex(project)
        let c = try columnIndex(name, in: b)
        let working = boards[b].columns.count - 1
        if c == working || index >= working { throw PMTError.doneColumn }
        let col = boards[b].columns.remove(at: c)
        boards[b].columns.insert(col, at: max(index, 0))
    }

    public mutating func removeColumn(_ name: String, project: UUID) throws {
        let b = try boardIndex(project)
        let c = try columnIndex(name, in: b)
        if c == boards[b].columns.count - 1 { throw PMTError.doneColumn }
        if !boards[b].columns[c].tasks.isEmpty { throw PMTError.columnNotEmpty(boards[b].columns[c].name) }
        if boards[b].columns.count < 3 { throw PMTError.tooFewColumns }
        boards[b].columns.remove(at: c)
    }

    // MARK: cards

    public func newCardID(using make: () -> UUID = UUID.init) -> String {
        let hex = make().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let used = Set(boards.flatMap { $0.columns.flatMap { $0.tasks.map(\.id) } + $0.archive.map(\.id) })
        var n = 6
        while n < hex.count && used.contains(String(hex.prefix(n))) { n += 1 }
        return String(hex.prefix(n))
    }

    @discardableResult
    public mutating func addCard(project: UUID, title: String, notes: String? = nil, column: String? = nil,
                                 due: Day? = nil, priority: Priority? = nil, now: Date = Date()) throws -> String {
        let b = try boardIndex(project)
        let c = try column.map { try columnIndex($0, in: b) } ?? 0
        if c == boards[b].columns.count - 1 { throw PMTError.doneColumn }
        let t = trimmed(title)
        if t.isEmpty { throw PMTError.emptyTitle }
        let n = notes.map(trimmed).flatMap { $0.isEmpty ? nil : $0 }
        let id = newCardID()
        // First in saved order, so it shows at the top of its priority group.
        boards[b].columns[c].tasks.insert(Card(id: id, title: t, notes: n, created: now, due: due, priority: priority), at: 0)
        return id
    }

    public mutating func editCard(_ id: String, title: String? = nil, notes: String? = nil) throws {
        let r = try findOpen(id)
        let t = try title.map { (s: String) throws -> String in
            let s = trimmed(s)
            if s.isEmpty { throw PMTError.emptyTitle }
            return s
        }
        if let t { boards[r.board].columns[r.column].tasks[r.index].title = t }
        if let notes {
            let n = trimmed(notes)
            boards[r.board].columns[r.column].tasks[r.index].notes = n.isEmpty ? nil : n
        }
    }

    public mutating func setDue(_ id: String, _ due: Day?) throws {
        let r = try findOpen(id)
        boards[r.board].columns[r.column].tasks[r.index].due = due
    }

    public mutating func setPriority(_ id: String, _ priority: Priority?) throws {
        let r = try findOpen(id)
        boards[r.board].columns[r.column].tasks[r.index].priority = priority
    }

    /// A dragged card dropped in `column` (on its own board). Dropped on card `target`, it takes that card's
    /// effective priority and goes just before it (after it when `below`) if they share the column; otherwise last.
    /// Dropped on empty space (`target` nil), its priority is kept and it goes last. The last column archives.
    @discardableResult
    public mutating func dropCard(_ id: String, to column: String, onto target: String?, below: Bool,
                                  today: Day, now: Date = Date()) throws -> DropResult {
        let r = try findOpen(id)
        let dest = try columnIndex(column, in: r.board)
        let card = boards[r.board].columns[r.column].tasks[r.index]
        var priority = card.priority
        var at: Int?
        if let target, let t = locate(target), let tc = t.column {
            if t.card.id == boards[r.board].columns[r.column].tasks[r.index].id { return DropResult(archived: false, priorityChanged: false) }
            priority = t.card.effectivePriority(today: today)
            if t.project == boards[r.board].project, same(tc, boards[r.board].columns[dest].name),
               var i = boards[r.board].columns[dest].tasks.firstIndex(where: { $0.id == t.card.id }) {
                if below { i += 1 }
                if r.column == dest && r.index < i { i -= 1 }
                at = i
            }
        }
        boards[r.board].columns[r.column].tasks[r.index].priority = priority
        let archived = try moveCard(id, to: column, at: at, now: now)
        // Changed as the card shows it (a due date can already raise it), not as saved.
        var after = card; after.priority = priority
        return DropResult(archived: archived,
                          priorityChanged: after.effectivePriority(today: today) != card.effectivePriority(today: today))
    }

    /// Returns true when the card was archived (moved to the last column).
    @discardableResult
    public mutating func moveCard(_ id: String, to column: String, at index: Int? = nil,
                                  now: Date = Date()) throws -> Bool {
        let r = try findOpen(id)
        let dest = try columnIndex(column, in: r.board)
        let card = boards[r.board].columns[r.column].tasks.remove(at: r.index)
        if dest == boards[r.board].columns.count - 1 {
            let from = boards[r.board].columns[r.column].name
            boards[r.board].archive.append(ArchivedCard(card, fromColumn: from, done: now))
            return true
        }
        let count = boards[r.board].columns[dest].tasks.count
        boards[r.board].columns[dest].tasks.insert(card, at: min(max(index ?? count, 0), count))
        return false
    }

    public mutating func deleteCard(_ id: String) throws {
        let r = try find(id)
        if let c = r.column { boards[r.board].columns[c].tasks.remove(at: r.index) }
        else { boards[r.board].archive.remove(at: r.index) }
    }

    public mutating func restoreCard(_ id: String) throws {
        let r = try find(id)
        guard r.column == nil else { throw PMTError.noSuchTask(trimmed(id)) }
        let a = boards[r.board].archive.remove(at: r.index)
        boards[r.board].columns[0].tasks.append(a.card)
    }
}

public struct DropResult: Equatable, Sendable {
    public var archived: Bool
    public var priorityChanged: Bool
    public init(archived: Bool, priorityChanged: Bool) { self.archived = archived; self.priorityChanged = priorityChanged }
}

/// One column of the Big Board: every board's column with this name (case-insensitive).
public struct BigColumn: Hashable, Sendable {
    public var name: String
    /// Open cards in display order (priority, due date), then board by board, each in its board's order.
    public var cards: [CardLocation]
    /// True when this is some board's last (Done) column.
    public var isDone: Bool
    /// Done cards of the boards whose Done column has this name.
    public var archived: Int
}

extension BoardsFile {
    /// All boards' columns merged by name. Each board's column order is kept:
    /// a name not seen yet goes just after that board's previous column. Done columns go last.
    public func bigBoard(today: Day) -> [BigColumn] {
        var cols: [BigColumn] = []
        for b in boards {
            var at = 0
            for (n, c) in b.columns.enumerated() {
                let i: Int
                if let found = cols.firstIndex(where: { same($0.name, c.name) }) {
                    i = found
                } else {
                    i = at
                    cols.insert(BigColumn(name: c.name, cards: [], isDone: false, archived: 0), at: i)
                }
                cols[i].cards += c.tasks.map { CardLocation(project: b.project, column: c.name, card: $0, done: nil) }
                if n == b.columns.count - 1 { cols[i].isDone = true; cols[i].archived += b.archive.count }
                at = i + 1
            }
        }
        for i in cols.indices { cols[i].cards = displayOrder(cols[i].cards, today: today) { $0.card } }
        return cols.filter { !$0.isDone } + cols.filter(\.isDone)
    }
}
