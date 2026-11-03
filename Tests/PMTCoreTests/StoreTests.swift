import Testing
import Foundation
import FFCore
@testable import PMTCore

@Test func missingFileIsEmpty() throws {
    #expect(try tempStore().load() == BoardsFile())
}

@Test func roundTrip() throws {
    let store = try tempStore()
    let p = OwnProject(id: UUID(), name: "Own")
    let card = Card(id: "a1", title: "T", notes: "n", created: Date(timeIntervalSince1970: 1_700_000_000))
    let arch = ArchivedCard(card, fromColumn: "Done", done: Date(timeIntervalSince1970: 1_700_000_100))
    let file = BoardsFile(ownProjects: [p], boards: [
        Board(project: p.id, columns: [Column(name: "Todo", tasks: [card]), Column(name: "Done")], archive: [arch])])
    try store.save(file)
    #expect(try store.load() == file)
    #expect(arch.card == card)
}

@Test func brokenFileThrowsBadConfig() throws {
    let store = try tempStore()
    try "not json".write(to: store.url, atomically: true, encoding: .utf8)
    #expect(throws: PMTError.self) { try store.load() }
    #expect(try String(contentsOf: store.url, encoding: .utf8) == "not json")
}

@Test func updateKeepsOutsideChanges() throws {
    let store = try tempStore()
    let a = OwnProject(id: UUID(), name: "A"), b = OwnProject(id: UUID(), name: "B")
    try store.save(BoardsFile(ownProjects: [a], boards: []))
    var other = try store.load(); other.ownProjects.append(b); try store.save(other)
    let result = try store.update(ff: FFCore.Config()) { $0.boards.append(Board(project: a.id, columns: [], archive: [])) }
    #expect(result.ownProjects == [a, b] && result.boards.count == 1)
}

@Test func defaultURLHonoursPMTConfig() {
    setenv("PMT_CONFIG", "~/x/boards.json", 1)
    defer { unsetenv("PMT_CONFIG") }
    #expect(BoardsStore.defaultURL.path == NSHomeDirectory() + "/x/boards.json")
}
