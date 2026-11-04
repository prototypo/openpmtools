import Testing
import Foundation
@testable import PMTCore

private let p = UUID()
private let t = Date(timeIntervalSince1970: 1_800_000_000)

@Test func createBoardValidatesColumns() throws {
    var f = BoardsFile()
    #expect(throws: PMTError.tooFewColumns) { try f.createBoard(project: p, columns: ["Done"]) }
    #expect(throws: PMTError.duplicateColumn("to do")) { try f.createBoard(project: p, columns: [" To Do", "to do", "Done"]) }
    #expect(throws: PMTError.emptyName) { try f.createBoard(project: p, columns: ["  ", "Done"]) }
    try f.createBoard(project: p, columns: [" To Do ", "Doing", "Done"])
    #expect(f.board(for: p)?.columns.map(\.name) == ["To Do", "Doing", "Done"])
    #expect(throws: PMTError.boardExists) { try f.createBoard(project: p, columns: ["A", "B"]) }
}

@Test func moveToLastColumnArchives() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["To Do", "Doing", "Done"])
    let id = try f.addCard(project: p, title: "Press kit", notes: "Need photo", now: t)
    #expect(try f.moveCard(id, to: "Doing") == false)
    #expect(try f.moveCard(id.uppercased(), to: "done", now: t) == true)
    let b = f.board(for: p)!
    #expect(b.columns.allSatisfy { $0.tasks.isEmpty })
    #expect(b.archive == [ArchivedCard(Card(id: id, title: "Press kit", notes: "Need photo", created: t), fromColumn: "Doing", done: t)])
    try f.restoreCard(id)
    #expect(f.board(for: p)!.columns[0].tasks.map(\.id) == [id] && f.board(for: p)!.archive.isEmpty)
}

@Test func moveUnknownCardThrows() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "Done"])
    #expect(throws: PMTError.noSuchTask("abc123")) { try f.moveCard("abc123", to: "A") }
}

@Test func moveToSamePlaceIsNoChange() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "Done"])
    let x = try f.addCard(project: p, title: "x"), y = try f.addCard(project: p, title: "y")
    let before = f
    _ = try f.moveCard(y, to: "A")
    #expect(f == before)
    _ = try f.moveCard(y, to: "A", at: 0)
    #expect(f.board(for: p)!.columns[0].tasks.map(\.id) == [y, x])
}

@Test func cardIDsGrowOnClash() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "Done"])
    let fixed = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
    let first = f.newCardID(using: { fixed })
    #expect(first == "abcdef")
    f.boards[0].columns[0].tasks.append(Card(id: first, title: "x", notes: nil, created: t))
    #expect(f.newCardID(using: { fixed }) == "abcdef1")
}

@Test func addCardRules() throws {
    var f = BoardsFile()
    #expect(throws: PMTError.noBoard) { try f.addCard(project: p, title: "x") }
    try f.createBoard(project: p, columns: ["A", "B", "Done"])
    #expect(throws: PMTError.doneColumn) { try f.addCard(project: p, title: "x", column: "done") }
    #expect(throws: PMTError.emptyTitle) { try f.addCard(project: p, title: "  ") }
    #expect(throws: PMTError.noSuchColumn("Z")) { try f.addCard(project: p, title: "x", column: "Z") }
    let id = try f.addCard(project: p, title: " x ", notes: "  ", now: t)
    let c = f.board(for: p)!.columns[0].tasks[0]
    #expect(c == Card(id: id, title: "x", notes: nil, created: t))
    try f.editCard(id, title: "y", notes: "n")
    #expect(f.locate(id)?.card.notes == "n" && f.locate(id)?.card.title == "y")
    try f.editCard(id.uppercased(), notes: "")
    #expect(f.locate(id)?.card.notes == nil)
    #expect(throws: PMTError.emptyTitle) { try f.editCard(id, title: " ") }
}

@Test func columnRules() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "B", "Done"])
    try f.addColumn("C", project: p)
    #expect(f.board(for: p)!.columns.map(\.name) == ["A", "B", "C", "Done"])
    try f.addColumn("Z", project: p, at: 0)
    try f.addColumn("Y", project: p, at: 99)
    #expect(f.board(for: p)!.columns.map(\.name) == ["Z", "A", "B", "C", "Y", "Done"])
    #expect(throws: PMTError.duplicateColumn("a")) { try f.addColumn("a", project: p) }
    #expect(throws: PMTError.duplicateColumn("b")) { try f.renameColumn("Y", to: "b", project: p) }
    try f.renameColumn("y", to: "W", project: p)
    try f.moveColumn("W", to: 0, project: p)
    #expect(f.board(for: p)!.columns.map(\.name) == ["W", "Z", "A", "B", "C", "Done"])
    #expect(throws: PMTError.doneColumn) { try f.moveColumn("Done", to: 0, project: p) }
    #expect(throws: PMTError.doneColumn) { try f.moveColumn("W", to: 5, project: p) }
    #expect(throws: PMTError.doneColumn) { try f.removeColumn("Done", project: p) }
    let id = try f.addCard(project: p, title: "x", column: "A")
    #expect(throws: PMTError.columnNotEmpty("A")) { try f.removeColumn("a", project: p) }
    _ = id
    var g = BoardsFile(); try g.createBoard(project: p, columns: ["A", "Done"])
    #expect(throws: PMTError.tooFewColumns) { try g.removeColumn("A", project: p) }
    #expect(throws: PMTError.noSuchColumn("Q")) { try g.removeColumn("Q", project: p) }
}

@Test func deleteBoardNeedsForce() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "Done"])
    let id = try f.addCard(project: p, title: "x")
    #expect(throws: PMTError.boardHasTasks) { try f.deleteBoard(project: p, force: false) }
    try f.deleteBoard(project: p, force: true)
    #expect(f.board(for: p) == nil)
    #expect(throws: PMTError.noBoard) { try f.deleteBoard(project: p, force: true) }
    _ = id
}

@Test func deleteArchivedCard() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "Done"])
    let id = try f.addCard(project: p, title: "x")
    _ = try f.moveCard(id, to: "Done", now: t)
    #expect(f.locate(id)?.column == nil && f.locate(id)?.done == t)
    #expect(throws: PMTError.noSuchTask(id)) { try f.editCard(id, title: "q") }
    try f.deleteCard(id)
    #expect(f.locate(id) == nil)
    #expect(throws: PMTError.noSuchTask(id)) { try f.deleteCard(id) }
}

@Test func bigBoardMergesColumnsInOrder() throws {
    let q = UUID()
    var f = BoardsFile()
    try f.createBoard(project: p, columns: ["To Do", "Doing", "Done"])
    try f.createBoard(project: q, columns: ["Backlog", "to do", "Review", "Shipped"])
    let a = try f.addCard(project: p, title: "a"), b = try f.addCard(project: q, title: "b", column: "To Do")
    _ = try f.moveCard(try f.addCard(project: q, title: "c"), to: "Shipped")
    let big = f.bigBoard()
    #expect(big.map(\.name) == ["Backlog", "To Do", "Review", "Doing", "Shipped", "Done"])
    #expect(big[1].cards.map(\.card.id) == [a, b] && big[1].cards.map(\.project) == [p, q])
    #expect(big.filter(\.isDone).map(\.name) == ["Shipped", "Done"])
    #expect(big[4].archived == 1 && big[5].archived == 0)
}
