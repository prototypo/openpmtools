import Testing
import Foundation
@testable import FFCore
@testable import PMTCore

private let p = UUID()
private let dev = Device(id: "A", name: "Mac A")
private let t = Date(timeIntervalSince1970: 1_800_000_000)
private let cardFields = ["title", "notes", "due", "priority", "place", "done", "fromColumn"]

/// A board with columns To Do, Doing, Done and one card in To Do, already stamped.
private func setup() throws -> (BoardsFile, String) {
    var f = BoardsFile()
    try f.createBoard(project: p, columns: ["To Do", "Doing", "Done"])
    let id = try f.addCard(project: p, title: "x", notes: "n", now: t)
    return (f.stamped(from: BoardsFile(), by: dev, now: t), id)
}

/// A card's tombstone key; `setup`'s card was created at `t`.
private func tomb(_ id: String, _ created: Date = t) -> String { "card:\(id)@\(Int(created.timeIntervalSince1970))" }

private func col(_ f: BoardsFile, _ i: Int) -> String { "column:\(p.uuidString)/\(f.boards[0].columns[i].id)" }

@Test func moveStampsPlaceOnly() throws {
    let (before, id) = try setup()
    var f = before
    try f.moveCard(id, to: "Doing")
    let s = f.stamped(from: before, by: dev, now: t + 1).stamps
    #expect(s["card:\(id).place"]?.clock == ["A": 2])
    #expect(s["card:\(id).title"] == before.stamps["card:\(id).title"])
    #expect(s["card:\(id).notes"] == before.stamps["card:\(id).notes"])
    #expect(s[col(f, 0) + ".order"]?.clock == ["A": 2])
    #expect(s[col(f, 1) + ".order"]?.clock == ["A": 2])
    #expect(s[col(f, 2) + ".order"] == before.stamps[col(f, 2) + ".order"])
}

@Test func archiveStampsPlaceAndDone() throws {
    let (before, id) = try setup()
    var f = before
    try f.moveCard(id, to: "Done", now: t)
    let s = f.stamped(from: before, by: dev, now: t + 1).stamps
    for k in ["place", "done", "fromColumn"] { #expect(s["card:\(id).\(k)"]?.clock == ["A": 2]) }
    #expect(s["card:\(id).title"] == before.stamps["card:\(id).title"])
}

@Test func editStampsChangedFields() throws {
    let (before, id) = try setup()
    var f = before
    try f.editCard(id, title: "y")
    let s = f.stamped(from: before, by: dev, now: t + 1).stamps
    for k in cardFields {
        let changed = s["card:\(id).\(k)"] != before.stamps["card:\(id).\(k)"]
        #expect(changed == (k == "title"), "\(k)")
    }
}

@Test func deleteCardLeavesTombstone() throws {
    let (before, id) = try setup()
    var f = before
    try f.deleteCard(id)
    let out = f.stamped(from: before, by: dev, now: t + 1)
    #expect(out.deleted[tomb(id)] == (t + 1).timeIntervalSince1970)
    #expect(!out.stamps.keys.contains { $0.hasPrefix("card:\(id).") })
}

@Test func removeColumnLeavesTombstone() throws {
    let (before, _) = try setup()
    var f = before
    try f.removeColumn("Doing", project: p)
    let key = col(before, 1)
    let out = f.stamped(from: before, by: dev, now: t + 1)
    #expect(out.deleted[key] == (t + 1).timeIntervalSince1970)
    #expect(!out.stamps.keys.contains { $0.hasPrefix(key + ".") })
    #expect(out.stamps["board:\(p.uuidString).columns"]?.clock == ["A": 2])
}

@Test func deleteBoardLeavesTombstones() throws {
    let (before, id) = try setup()
    var f = before
    try f.deleteBoard(project: p, force: true)
    let out = f.stamped(from: before, by: dev, now: t + 1)
    #expect(out.deleted["board:\(p.uuidString)"] != nil)
    #expect(out.deleted[tomb(id)] != nil)
    #expect(out.stamps.isEmpty)
}

@Test func newCardStampsAllFields() throws {
    let (before, _) = try setup()
    var f = before
    let id = try f.addCard(project: p, title: "new", now: t)
    let s = f.stamped(from: before, by: dev, now: t + 1).stamps
    for k in cardFields { #expect(s["card:\(id).\(k)"] == .first(by: dev, now: t + 1), "\(k)") }
    #expect(!s.keys.contains("card:\(id).created"))
}

@Test func oldTombstonesArePruned() throws {
    let (before, id) = try setup()
    var f = before
    try f.deleteCard(id)
    f = f.stamped(from: before, by: dev, now: t)
    let later = f.stamped(from: f, by: dev, now: t + 91 * 86400)
    #expect(later.deleted[tomb(id)] == nil)
}

@Test func storeUpdateStamps() throws {
    let tmp = try tempStore()
    let store = BoardsStore(url: tmp.url, device: dev)
    let a = OwnProject(id: UUID(), name: "A")
    let ff = FFCore.Config()
    try store.update(ff: ff) {
        $0.ownProjects = [a]
        try $0.createBoard(project: a.id, columns: ["To Do", "Done"])
    }
    let saved = try store.load()
    #expect(saved.stamps["own:\(a.id.uuidString).name"]?.by == "Mac A")
    #expect(saved.stamps["file.ownOrder"] != nil)
    #expect(saved.stamps["board:\(a.id.uuidString).columns"] != nil)
    let data = try Data(contentsOf: store.url)
    try store.update(ff: ff) { _ in }
    #expect(try Data(contentsOf: store.url) == data)
}

@Test func emptyStampsAreNotEncoded() throws {
    let s = String(decoding: try BoardsFile().jsonData(), as: UTF8.self)
    #expect(!s.contains("stamps") && !s.contains("deleted"))
}

@Test func placeIncludesProject() throws {
    // Two boards whose columns have the same name-derived id "doing".
    let q = UUID()
    var f = BoardsFile(boards: [
        Board(project: p, columns: [Column(name: "Doing"), Column(name: "Done")]),
        Board(project: q, columns: [Column(name: "Doing"), Column(name: "Done")])])
    let id = try f.addCard(project: p, title: "x", now: t)
    let before = f.stamped(from: BoardsFile(), by: dev, now: t)
    var g = before
    g.boards[1].columns[0].tasks = g.boards[0].columns[0].tasks
    g.boards[0].columns[0].tasks = []
    let s = g.stamped(from: before, by: dev, now: t + 1).stamps
    #expect(s["card:\(id).place"]?.clock == ["A": 2])
    #expect(s["card:\(id).title"] == before.stamps["card:\(id).title"])
}

@Test func attachBoardStampsCardPlaces() throws {
    let (before, id) = try setup()
    var f = before
    try f.moveCard(id, to: "Doing")
    let archived = try f.addCard(project: p, title: "y", now: t)
    try f.moveCard(archived, to: "Done", now: t)
    let base = f.stamped(from: before, by: dev, now: t + 1)
    var g = base
    let q = UUID()
    try g.attachBoard(p, to: q)
    let s = g.stamped(from: base, by: dev, now: t + 2).stamps
    for c in [id, archived] {
        #expect(s["card:\(c).place"] != base.stamps["card:\(c).place"], "\(c)")
        #expect(s["card:\(c).place"]?.at == (t + 2).timeIntervalSince1970)
        #expect(s["card:\(c).title"] == base.stamps["card:\(c).title"])
    }
}

@Test func recreatedBoardClearsTombstone() throws {
    let (before, _) = try setup()
    var f = before
    try f.deleteBoard(project: p, force: true)
    let gone = f.stamped(from: before, by: dev, now: t + 1)
    var g = gone
    try g.createBoard(project: p, columns: ["A", "Done"])
    let back = g.stamped(from: gone, by: dev, now: t + 2)
    #expect(back.deleted["board:\(p.uuidString)"] == nil)
    let later = back.stamped(from: back, by: dev, now: t + 91 * 86400)
    #expect(later.stamps["board:\(p.uuidString).columns"] != nil)
    #expect(later.stamps[col(later, 0) + ".name"] != nil)
}

@Test func removingColumnKeepsDottedSibling() throws {
    var f = BoardsFile(boards: [Board(project: p, columns: [
        Column(name: "v1"), Column(name: "v1.0"), Column(name: "x"), Column(name: "Done")])])
    f = f.stamped(from: BoardsFile(), by: dev, now: t)
    var g = f
    try g.removeColumn("v1", project: p)
    let s = g.stamped(from: f, by: dev, now: t + 1).stamps
    let key = "column:\(p.uuidString)/v1"
    #expect(s[key + ".name"] == nil)
    #expect(s[key + ".0.name"] != nil && s[key + ".0.order"] != nil)
}

// MARK: merge

private let devB = Device(id: "B", name: "Mac B")

private func edit(_ f: BoardsFile, by d: Device, at s: Double,
                  _ change: (inout BoardsFile) throws -> Void) rethrows -> BoardsFile {
    var g = f
    try change(&g)
    return g.stamped(from: f, by: d, now: t + s)
}

/// Merges a with b, checking the result is the same either way round and stable when merged again.
private func merge(_ a: BoardsFile, _ b: BoardsFile, sourceLocation: SourceLocation = #_sourceLocation) -> BoardsFile {
    let m = a.merged(with: b)
    #expect(b.merged(with: a) == m, "symmetric", sourceLocation: sourceLocation)
    #expect(m.merged(with: a) == m, "idempotent with a", sourceLocation: sourceLocation)
    #expect(m.merged(with: b) == m, "idempotent with b", sourceLocation: sourceLocation)
    return m
}

private func titles(_ f: BoardsFile, _ col: Int) -> [String] { f.boards[0].columns[col].tasks.map(\.title) }

@Test func moveAndEditBothSurvive() throws {
    let (base, id) = try setup()
    let a = try edit(base, by: dev, at: 1) { try $0.moveCard(id, to: "Doing") }
    let b = try edit(base, by: devB, at: 2) { try $0.editCard(id, title: "y") }
    let m = merge(a, b)
    #expect(titles(m, 0).isEmpty)
    #expect(titles(m, 1) == ["y"])
}

@Test func bothAddCardsBothKept() throws {
    let (base, _) = try setup()
    let a = try edit(base, by: dev, at: 1) { try $0.addCard(project: p, title: "a", now: t + 1) }
    let b = try edit(base, by: devB, at: 2) { try $0.addCard(project: p, title: "b", now: t + 2) }
    let m = merge(a, b)
    #expect(Set(titles(m, 0).prefix(2)) == ["a", "b"])
    #expect(titles(m, 0).last == "x")
}

@Test func cardIDCollisionKeepsBoth() throws {
    let (base, _) = try setup()
    func add(_ title: String, _ s: Double, _ d: Device) -> BoardsFile {
        edit(base, by: d, at: s) {
            $0.boards[0].columns[0].tasks.insert(Card(id: "abc123", title: title, created: t + s), at: 0)
        }
    }
    let m = merge(add("from A", 1, dev), add("from B", 2, devB))
    let cards = m.boards[0].columns[0].tasks
    let hex = String(String(Int((t + 2).timeIntervalSince1970), radix: 16).suffix(4))
    #expect(cards.count == 3)
    #expect(cards.first { $0.id == "abc123" }?.title == "from A")
    #expect(cards.first { $0.id == "abc123-" + hex }?.title == "from B")
}

@Test func archivedOnOneSideEditedOnOther() throws {
    let (base, id) = try setup()
    let a = try edit(base, by: dev, at: 1) { try $0.moveCard(id, to: "Done", now: t + 1) }
    let b = try edit(base, by: devB, at: 2) { try $0.editCard(id, notes: "B notes") }
    let m = merge(a, b)
    #expect(m.boards[0].columns.allSatisfy { $0.tasks.isEmpty })
    #expect(m.boards[0].archive.map(\.notes) == ["B notes"])
    #expect(m.boards[0].archive.first?.fromColumn == "To Do")
}

@Test func deleteBeatsOlderEdit() throws {
    let (base, id) = try setup()
    let a = try edit(base, by: dev, at: 1) { try $0.editCard(id, title: "y") }
    let b = try edit(base, by: devB, at: 2) { try $0.deleteCard(id) }
    #expect(merge(a, b).locate(id) == nil)
}

@Test func newerEditBeatsDelete() throws {
    let (base, id) = try setup()
    let a = try edit(base, by: dev, at: 2) { try $0.editCard(id, title: "y") }
    let b = try edit(base, by: devB, at: 1) { try $0.deleteCard(id) }
    #expect(titles(merge(a, b), 0) == ["y"])
}

@Test func sameNamedColumnsCollapse() throws {
    let (base, _) = try setup()
    func review(_ d: Device, _ s: Double) throws -> BoardsFile {
        try edit(base, by: d, at: s) {
            try $0.addColumn("Review", project: p)
            try $0.addCard(project: p, title: d.id, column: "Review", now: t + s)
        }
    }
    let m = merge(try review(dev, 1), try review(devB, 2))
    #expect(m.boards[0].columns.map(\.name) == ["To Do", "Doing", "Review", "Done"])
    #expect(Set(titles(m, 2)) == ["A", "B"])
}

@Test func oldFilesMergeWithoutDuplicates() throws {
    let json = """
    {"ownProjects": [], "boards": [{"project": "\(p.uuidString)", "archive": [], "columns": [
      {"name": "To Do", "tasks": [{"id": "c1", "title": "x", "created": 1800000000}]},
      {"name": "Doing", "tasks": []}, {"name": "Done", "tasks": []}]}]}
    """
    let old = try JSONDecoder().decode(BoardsFile.self, from: Data(json.utf8))
    let a = try edit(old, by: dev, at: 1) { try $0.addCard(project: p, title: "a", now: t + 1) }
    let b = try edit(old, by: devB, at: 2) { try $0.moveCard("c1", to: "Doing") }
    let m = merge(a, b)
    #expect(m.boards[0].columns.map(\.name) == ["To Do", "Doing", "Done"])
    #expect(titles(m, 0) == ["a"])
    #expect(titles(m, 1) == ["x"])
}

@Test func removedColumnSendsNewerCardToFirstColumn() throws {
    let (base, id) = try setup()
    let a = try edit(base, by: dev, at: 2) { try $0.removeColumn("Doing", project: p) }
    let b = try edit(base, by: devB, at: 1) { try $0.moveCard(id, to: "Doing") }
    let m = merge(a, b)
    #expect(m.boards[0].columns.map(\.name) == ["To Do", "Done"])
    #expect(titles(m, 0) == ["x"])
}

@Test func deletedBoardComesBackForNewerCard() throws {
    let (base, id) = try setup()
    let a = try edit(base, by: dev, at: 1) { try $0.deleteBoard(project: p, force: true) }
    let b = try edit(base, by: devB, at: 2) { try $0.editCard(id, title: "y") }
    let m = merge(a, b)
    #expect(m.boards.count == 1)
    #expect(m.locate(id)?.card.title == "y")
}

/// Two diverged copies exercising every merge path.
private func diverged() throws -> (BoardsFile, BoardsFile) {
    let (o1, o2, o3) = (OwnProject(name: "O1"), OwnProject(name: "O2"), OwnProject(name: "O3"))
    let (base0, id) = try setup()
    var base = base0
    base.ownProjects = [o1, o2, o3]
    let second = try base.addCard(project: p, title: "second", now: t)
    base = base.stamped(from: base0, by: dev, now: t)
    let a = try edit(base, by: dev, at: 10) {
        $0.ownProjects[1].name = "O2 by A"
        $0.ownProjects.remove(at: 2)
        $0.ownProjects.append(OwnProject(name: "A new"))
        try $0.renameColumn("Doing", to: "Working", project: p)
        try $0.editCard(id, notes: "A notes")
        try $0.moveCard(second, to: "Done", now: t + 10)
        try $0.createBoard(project: o1.id, columns: ["Todo", "Done"])
    }
    let b = try edit(base, by: devB, at: 20) {
        $0.ownProjects.reverse()
        $0.ownProjects.append(OwnProject(name: "B new"))
        try $0.addColumn("Review", project: p)
        try $0.editCard(id, notes: "B notes")
        try $0.moveCard(id, to: "Review")
        try $0.addCard(project: p, title: "B card", now: t + 20)
    }
    return (a, b)
}

@Test func mergeIsIdempotent() throws {
    let (a, b) = try diverged()
    let m = a.merged(with: b)
    #expect(m.merged(with: b) == m)
    #expect(m.merged(with: a) == m)
}

@Test func mergeIsSymmetric() throws {
    let (a, b) = try diverged()
    let m = merge(a, b)
    #expect(m.ownProjects.count == 4)
    #expect(m.boards.count == 2)
    #expect(m.boards[0].columns.map(\.name) == ["To Do", "Working", "Review", "Done"])
    #expect(m.boards[0].archive.map(\.title) == ["second"])
    #expect(m.boards[0].columns[2].tasks.first?.notes?.contains("— Also edited on Mac B") == true)
}

/// `base` with a card "abc123" made at t + s by `d`.
private func withABC(_ base: BoardsFile, _ title: String, _ s: Double, _ d: Device) -> BoardsFile {
    edit(base, by: d, at: s) {
        $0.boards[0].columns[0].tasks.insert(Card(id: "abc123", title: title, created: t + s), at: 0)
    }
}

private func suffix(_ s: Double, plus n: Int = 0) -> String {
    String(format: "-%04lx", (Int((t + s).timeIntervalSince1970) & 0xffff) + n)
}

@Test func collisionThenDeleteKeepsOtherCard() throws {
    let (base, _) = try setup()
    let a = withABC(base, "X", 1, dev), b = withABC(base, "Y", 2, devB)
    let m = merge(a, b)
    #expect(m.locate("abc123" + suffix(2))?.card.title == "Y")
    // B deletes Y under its old id before it sees the merge.
    let b2 = try edit(b, by: devB, at: 3) { try $0.deleteCard("abc123") }
    #expect(b2.deleted[tomb("abc123", t + 2)] != nil)
    // X survives either way round; Y may come back (a delete under the old id does not name the renamed card).
    for x in [merge(m, b2), merge(a, b2)] { #expect(x.locate("abc123")?.card.title == "X") }
}

@Test func inFileDuplicateDeleteKeepsOther() throws {
    let (base0, _) = try setup()
    // Several random ids, so differing hash orders would show up as differing results.
    for _ in 0..<8 {
        let id = String(UUID().uuidString.prefix(6)).lowercased()
        let base = edit(base0, by: dev, at: 1) {
            $0.boards[0].columns[0].tasks += [Card(id: id, title: "P", created: t + 1), Card(id: id, title: "Q", created: t + 1)]
        }
        let renamed = merge(base, base)
        let a = try edit(renamed, by: dev, at: 2) { try $0.deleteCard(id) }
        #expect(a.deleted[tomb(id, t + 1)] != nil)
        for m in [merge(a, base), merge(a, renamed), merge(a, base0)] {
            #expect(titles(m, 0).sorted() == ["Q", "x"])
        }
    }
}

@Test func duplicateIDInOneFileKeepsBoth() throws {
    let (base, _) = try setup()
    var f = base
    f.boards[0].columns[0].tasks += [Card(id: "dup", title: "second", created: t + 2),
                                     Card(id: "dup", title: "first", created: t + 1)]
    for m in [merge(f, base), merge(f, f)] {
        #expect(m.locate("dup")?.card.title == "first")
        #expect(m.locate("dup" + suffix(2))?.card.title == "second")
        #expect(titles(m, 0).count == 3)
    }
}

@Test func tombstoneTieKeepsCard() throws {
    let (base, id) = try setup()
    let a = try edit(base, by: dev, at: 1) { try $0.editCard(id, title: "y") }
    let b = try edit(base, by: devB, at: 1) { try $0.deleteCard(id) }
    #expect(b.deleted[tomb(id)] == a.stamps["card:\(id).title"]?.at)
    #expect(titles(merge(a, b), 0) == ["y"])
}

@Test func collisionSuffixSkipsUsedID() throws {
    let (base, _) = try setup()
    let a = edit(withABC(base, "X", 1, dev), by: dev, at: 5) {
        $0.boards[0].columns[0].tasks.insert(Card(id: "abc123" + suffix(2), title: "Z", created: t + 5), at: 0)
    }
    let m = merge(a, withABC(base, "Y", 2, devB))
    #expect(m.locate("abc123")?.card.title == "X")
    #expect(m.locate("abc123" + suffix(2))?.card.title == "Z")
    #expect(m.locate("abc123" + suffix(2, plus: 1))?.card.title == "Y")
}

@Test func revivedBoardKeepsOwnProject() throws {
    let (base0, _) = try setup()
    let base = edit(base0, by: dev, at: 0) { $0.ownProjects = [OwnProject(id: p, name: "P")] }
    let a = try edit(base, by: dev, at: 1) { try $0.removeOwnProject(p, force: true) }
    #expect(a.deleted["own:\(p.uuidString)"] != nil && a.deleted["board:\(p.uuidString)"] != nil)
    var id = ""
    let b = try edit(base, by: devB, at: 2) { id = try $0.addCard(project: p, title: "late", now: t + 2) }
    for m in [merge(a, b), merge(b, a)] {
        #expect(Catalog(ff: FFCore.Config(), file: m).orphanBoards.isEmpty)
        #expect(m.ownProjects.map(\.name) == ["P"])
        #expect(m.deleted["own:\(p.uuidString)"] == nil)
        #expect(m.stamps["own:\(p.uuidString).name"] == base.stamps["own:\(p.uuidString).name"])
        #expect(m.locate(id)?.card.title == "late")
    }
}

@Test func removingColumnWithAtKeepsOtherColumnStamps() throws {
    var f = BoardsFile(boards: [Board(project: p, columns: [
        Column(name: "a"), Column(name: "a@b"), Column(name: "x"), Column(name: "Done")])])
    f = f.stamped(from: BoardsFile(), by: dev, now: t)
    var g = f
    try g.removeColumn("a@b", project: p)
    let s = g.stamped(from: f, by: dev, now: t + 1).stamps
    let key = "column:\(p.uuidString)/a"
    #expect(s[key + ".name"] != nil && s[key + ".order"] != nil)
    #expect(s[key + "@b.name"] == nil)
}

@Test func subSecondCreatedIsSameCard() throws {
    let (base, _) = try setup()
    func add(_ created: Double, _ s: Double, _ d: Device) -> BoardsFile {
        edit(base, by: d, at: s) {
            $0.boards[0].columns[0].tasks.insert(Card(id: "abc123", title: "s", created: t + created), at: 0)
        }
    }
    let m = merge(add(0.3, 1, dev), add(0.7, 2, devB))
    #expect(titles(m, 0).sorted() == ["s", "x"])
    #expect(m.locate("abc123")?.card.created == t + 0.3)
}

@Test func randomColumnIDSurvivesRoundTrip() throws {
    let (base, _) = try setup()
    var f = base
    try f.addColumn("Review", project: p)
    let id = try #require(f.boards[0].columns.first { $0.name == "Review" }).id
    #expect(id != "review")
    let store = try tempStore()
    try store.save(f)
    #expect(try store.load().boards[0].columns.first { $0.name == "Review" }?.id == id)
}
