import Foundation
import FFCore

private let cardFields = ["title", "notes", "due", "priority", "place", "done", "fromColumn"]

extension BoardsFile {
    /// Every stamped field as key to value, and every item key (the tombstone key).
    /// Card ids are unique across the file, so card keys use the id alone.
    /// A card's place is "<project>/<column id>" or "<project>/archive": old column ids repeat across boards.
    /// Optionals are wrapped in `AnyHashable` so a nil value is still a field.
    private var syncFields: (values: [String: AnyHashable], items: Set<String>) {
        var v: [String: AnyHashable] = [:], items = Set<String>()
        func card(_ c: Card, place: String, done: Date?, from: String?) {
            let k = "card:\(c.id)"
            items.insert(k)
            v[k + ".title"] = c.title
            v[k + ".notes"] = AnyHashable(c.notes)
            v[k + ".due"] = AnyHashable(c.due)
            v[k + ".priority"] = AnyHashable(c.priority)
            v[k + ".place"] = place
            v[k + ".done"] = AnyHashable(done)
            v[k + ".fromColumn"] = AnyHashable(from)
        }
        for o in ownProjects {
            let k = "own:\(o.id.uuidString)"
            items.insert(k)
            v[k + ".name"] = o.name
        }
        v["file.ownOrder"] = ownProjects.map(\.id)
        for b in boards {
            let bk = "board:\(b.project.uuidString)"
            items.insert(bk)
            v[bk + ".columns"] = b.columns.map(\.id)
            for col in b.columns {
                let k = "column:\(b.project.uuidString)/\(col.id)"
                items.insert(k)
                v[k + ".name"] = col.name
                v[k + ".order"] = col.tasks.map(\.id)
                for c in col.tasks { card(c, place: "\(b.project.uuidString)/\(col.id)", done: nil, from: nil) }
            }
            for a in b.archive { card(a.card, place: "\(b.project.uuidString)/archive", done: a.done, from: a.fromColumn) }
        }
        return (v, items)
    }

    /// Returns self with stamps and tombstones brought up to date for the edit from `before`.
    /// Same rules as `Config.stamped`. `created` never changes and is not stamped.
    public func stamped(from before: BoardsFile, by device: Device, now: Date) -> BoardsFile {
        var out = self
        let (new, old) = (syncFields, before.syncFields)
        for (k, value) in new.values where old.values[k] != value {
            out.stamps[k] = out.stamps[k]?.bumped(by: device, now: now) ?? .first(by: device, now: now)
        }
        // Exact keys, not a prefix: old column ids come from names and can contain dots.
        func unstamp(_ item: String) {
            let fields: [String]
            switch item.prefix(while: { $0 != ":" }) {
            case "card": fields = cardFields
            case "column": fields = ["name", "order"]
            case "board": fields = ["columns"]
            default: fields = ["name"]  // own
            }
            for f in fields { out.stamps[item + "." + f] = nil }
        }
        for k in old.items.subtracting(new.items) {
            out.deleted[k] = now.timeIntervalSince1970
            unstamp(k)
        }
        // A re-created item must not keep its old tombstone, or pruning would strip its live stamps.
        for k in new.items { out.deleted[k] = nil }
        let cutoff = now.timeIntervalSince1970 - 90 * 86400
        for (k, t) in out.deleted where t < cutoff {
            out.deleted[k] = nil
            unstamp(k)
        }
        return out
    }
}

/// A card as the merge sees it: where it is (`column` nil means archived) and its archive fields.
private struct Placed {
    var card: Card, board: UUID, column: String?, done: Date? = nil, from: String? = nil
    /// The stamped `.place` value, as `syncFields` writes it.
    var place: String { "\(board.uuidString)/\(column ?? "archive")" }
}

extension BoardsFile {
    private var placed: [String: Placed] {
        var out: [String: Placed] = [:]
        for b in boards {
            for col in b.columns {
                for c in col.tasks { out[c.id] = out[c.id] ?? Placed(card: c, board: b.project, column: col.id) }
            }
            for a in b.archive {
                out[a.id] = out[a.id] ?? Placed(card: a.card, board: b.project, column: nil, done: a.done, from: a.fromColumn)
            }
        }
        return out
    }

    private var columnLists: [String: [String]] {
        Dictionary(boards.map { ($0.project.uuidString, $0.columns.map(\.id)) }, uniquingKeysWith: { a, _ in a })
    }

    /// Columns keyed "<project>/<column id>".
    private var columnFields: [String: (name: String, order: [String])] {
        Dictionary(boards.flatMap { b in b.columns.map { ("\(b.project.uuidString)/\($0.id)", ($0.name, $0.tasks.map(\.id))) } },
                   uniquingKeysWith: { a, _ in a })
    }

    /// Merges another device's copy into this one, item by item. The result does not depend on which is `self`.
    /// An item on one side only is kept unless the merged tombstone is later than all its stamps.
    public func merged(with other: BoardsFile) -> BoardsFile {
        var out = BoardsFile()
        out.deleted = deleted.merging(other.deleted, uniquingKeysWith: max)
        var (ca, cb, sa, sb) = (placed, other.placed, stamps, other.stamps)

        // Same id, different `created`: two cards. The later one moves to "<id>-<last 4 hex of created>", or the next
        // free number. A card already there with the same `created` is that card renamed by an earlier merge.
        for id in Set(ca.keys).intersection(cb.keys).sorted() where ca[id]!.card.created != cb[id]!.card.created {
            func rename(_ cards: inout [String: Placed], _ st: inout Stamps, beside others: [String: Placed]) {
                var c = cards.removeValue(forKey: id)!
                var n = Int(c.card.created.timeIntervalSince1970) & 0xffff
                func taken(_ k: String) -> Bool {
                    cards[k] != nil || others[k].map { $0.card.created != c.card.created } ?? false
                }
                while taken(id + String(format: "-%04x", n)) { n += 1 }
                c.card.id = id + String(format: "-%04x", n)
                cards[c.card.id] = c
                for f in cardFields { st["card:\(c.card.id).\(f)"] = st.removeValue(forKey: "card:\(id).\(f)") }
            }
            if ca[id]!.card.created > cb[id]!.card.created { rename(&ca, &sa, beside: cb) } else { rename(&cb, &sb, beside: ca) }
        }

        func restore(_ item: String, _ fields: [String], _ st: Stamps) {
            for f in fields { out.stamps[item + "." + f] = st[item + "." + f] }
            out.deleted[item] = nil
        }
        func keep(_ item: String, _ fields: [String], _ st: Stamps) -> Bool {
            let latest = fields.compactMap { st[item + "." + $0]?.at }.max() ?? -.infinity
            if let d = out.deleted[item], d > latest { return false }
            restore(item, fields, st)
            return true
        }
        func pick<T: Equatable>(_ key: String, _ x: T, _ y: T) -> T {
            let (v, s) = mergeValue(x, sa[key], y, sb[key])
            out.stamps[key] = s
            return v
        }
        /// Items on both sides merge with `both` (given the key prefix "<kind>:<id>."); one-sided ones pass `keep`.
        func items<T>(_ kind: String, _ fields: [String], _ x: [String: T], _ y: [String: T],
                      both: (String, T, T) -> T) -> [String: T] {
            var kept: [String: T] = [:]
            for id in Set(x.keys).union(y.keys) {
                let k = kind + ":" + id
                switch (x[id], y[id]) {
                case let (v?, w?): kept[id] = both(k + ".", v, w); out.deleted[k] = nil
                case let (v?, nil) where keep(k, fields, sa): kept[id] = v
                case let (nil, w?) where keep(k, fields, sb): kept[id] = w
                default: break
                }
            }
            return kept
        }

        func owns(_ f: BoardsFile) -> [String: OwnProject] {
            Dictionary(f.ownProjects.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        }
        let own = items("own", ["name"], owns(self), owns(other)) { k, x, y in
            OwnProject(id: x.id, name: pick(k + "name", x.name, y.name))
        }
        let mine = ownProjects.map(\.id)
        let (first, second) = pick("file.ownOrder", mine, other.ownProjects.map(\.id)) == mine
            ? (ownProjects, other.ownProjects) : (other.ownProjects, ownProjects)
        var seen = Set<UUID>()
        out.ownProjects = (first + second).compactMap { seen.insert($0.id).inserted ? own[$0.id.uuidString] : nil }

        let cards = items("card", cardFields, ca, cb) { k, x, y in
            func text(_ f: String, _ a: String?, _ b: String?, _ j: TextJoin) -> String? {
                let (v, s) = mergeText(a, sa[k + f], b, sb[k + f], join: j)
                out.stamps[k + f] = s
                return v
            }
            var c = x
            c.card.title = text("title", x.card.title, y.card.title, .title) ?? x.card.title
            c.card.notes = text("notes", x.card.notes, y.card.notes, .notes)
            c.card.due = pick(k + "due", x.card.due, y.card.due)
            c.card.priority = pick(k + "priority", x.card.priority, y.card.priority)
            c.done = pick(k + "done", x.done, y.done)
            c.from = pick(k + "fromColumn", x.from, y.from)
            let w = pick(k + "place", x.place, y.place) == x.place ? x : y
            (c.board, c.column) = (w.board, w.column)
            return c
        }

        let (la, lb, fa, fb) = (columnLists, other.columnLists, columnFields, other.columnFields)
        var lists = items("board", ["columns"], la, lb) { k, x, y in pick(k + "columns", x, y) }
        var columns = items("column", ["name", "order"], fa, fb) { k, x, y in
            (pick(k + "name", x.name, y.name), pick(k + "order", x.order, y.order))
        }

        // A deleted board comes back, with its columns, when a card or column on it survives.
        let needed = Set(cards.values.map(\.board.uuidString) + columns.keys.map { String($0.prefix(36)) })
        for p in needed where lists[p] == nil || !columns.keys.contains(where: { $0.hasPrefix(p + "/") }) {
            if lists[p] == nil { restore("board:" + p, ["columns"], la[p] != nil ? sa : sb) }
            let list = lists[p] ?? la[p] ?? lb[p] ?? []
            lists[p] = list
            for c in list where columns[p + "/" + c] == nil {
                let k = p + "/" + c
                guard let col = fa[k] ?? fb[k] else { continue }
                restore("column:" + k, ["name", "order"], fa[k] != nil ? sa : sb)
                columns[k] = col
            }
        }

        // Column order: the winning list; columns only the other side has go just before the last column.
        var built: [String: Board] = [:]
        for (p, w) in lists {
            let other = (w == la[p] ? lb[p] : la[p]) ?? []
            var ids = w.filter { columns[p + "/" + $0] != nil }
            ids.insert(contentsOf: other.filter { columns[p + "/" + $0] != nil && !w.contains($0) }, at: max(ids.count - 1, 0))
            built[p] = Board(project: UUID(uuidString: p)!, columns: ids.map { Column(name: columns[p + "/" + $0]!.name, id: $0) })
        }

        // Each card to its place; a gone column sends it to the board's first column.
        var into: [String: [Card]] = [:]
        for c in cards.values {
            let p = c.board.uuidString
            guard let column = c.column, let firstColumn = built[p]!.columns.first else {
                built[p]!.archive.append(ArchivedCard(c.card, fromColumn: c.from ?? "", done: c.done ?? c.card.created))
                continue
            }
            into[p + "/" + (columns[p + "/" + column] != nil ? column : firstColumn.id), default: []].append(c.card)
        }

        for p in built.keys {
            for i in built[p]!.columns.indices {
                let k = p + "/" + built[p]!.columns[i].id
                let here = into[k] ?? [], order = columns[k]!.order
                // Cards not in the winning order are new here: newest first, at the top.
                let extra = here.filter { !order.contains($0.id) }
                    .sorted { $0.created != $1.created ? $0.created > $1.created : $0.id < $1.id }
                built[p]!.columns[i].tasks = extra + order.compactMap { id in here.first { $0.id == id } }
            }
            built[p]!.archive.sort { ($0.done, $0.id) < ($1.done, $1.id) }
            // Same name twice: the column whose id sorts first takes the other's cards at its top.
            let cs = built[p]!.columns
            built[p]!.columns = cs.compactMap { c in
                let twins = cs.filter { $0.name.caseInsensitiveCompare(c.name) == .orderedSame }
                guard c.id == twins.map(\.id).min() else {
                    for f in ["name", "order"] { out.stamps["column:\(p)/\(c.id).\(f)"] = nil }
                    return nil
                }
                var kept = c
                kept.tasks = twins.filter { $0.id != c.id }.flatMap(\.tasks) + c.tasks
                return kept
            }
        }

        // Boards have no order stamp: the side whose own order wins, then by project id.
        let win = mergeValue(boards.map(\.project), stamps["file.ownOrder"],
                             other.boards.map(\.project), other.stamps["file.ownOrder"]).0
        let rank = Dictionary(win.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        out.boards = built.values.sorted {
            (rank[$0.project] ?? .max, $0.project.uuidString) < (rank[$1.project] ?? .max, $1.project.uuidString)
        }
        return out
    }
}
