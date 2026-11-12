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
    #expect(out.deleted["card:\(id)"] == (t + 1).timeIntervalSince1970)
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
    #expect(out.deleted["card:\(id)"] != nil)
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
    #expect(later.deleted["card:\(id)"] == nil)
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
