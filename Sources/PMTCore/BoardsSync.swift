import Foundation
import FFCore

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
            case "card": fields = ["title", "notes", "due", "priority", "place", "done", "fromColumn"]
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
