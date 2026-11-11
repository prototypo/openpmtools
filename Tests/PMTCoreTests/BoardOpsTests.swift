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
    _ = try f.moveCard(x, to: "A")  // new cards go first, so x is last
    #expect(f == before)
    _ = try f.moveCard(x, to: "A", at: 0)
    #expect(f.board(for: p)!.columns[0].tasks.map(\.id) == [x, y])
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
    let big = f.bigBoard(today: today)
    #expect(big.map(\.name) == ["Backlog", "To Do", "Review", "Doing", "Shipped", "Done"])
    #expect(big[1].cards.map(\.card.id) == [a, b] && big[1].cards.map(\.project) == [p, q])
    #expect(big.filter(\.isDone).map(\.name) == ["Shipped", "Done"])
    #expect(big[4].archived == 1 && big[5].archived == 0)
}

// MARK: due dates, priorities, drops

private let today = Day("2026-11-14")!

private func board3() throws -> BoardsFile {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["To Do", "Doing", "Done"]); return f
}

private func ids(_ f: BoardsFile, _ col: Int, board: UUID = p) -> [String] { f.board(for: board)!.columns[col].tasks.map(\.title) }

@Test func newCardsGoFirst() throws {
    var f = try board3()
    try f.addCard(project: p, title: "A"); try f.addCard(project: p, title: "B")
    #expect(ids(f, 0) == ["B", "A"])
}

@Test func setDueAndPriority() throws {
    var f = try board3()
    let id = try f.addCard(project: p, title: "A", due: Day("2026-11-20"), priority: .low)
    try f.setDue(id, Day("2026-11-21")); try f.setPriority(id, .high)
    #expect(f.locate(id)?.card.due == Day("2026-11-21") && f.locate(id)?.card.priority == .high)
    try f.setDue(id, nil); try f.setPriority(id, nil)
    #expect(f.locate(id)?.card.due == nil && f.locate(id)?.card.priority == nil)
    try f.moveCard(id, to: "Done")
    #expect(throws: PMTError.noSuchTask(id)) { try f.setDue(id, today) }
    #expect(throws: PMTError.noSuchTask(id)) { try f.setPriority(id, .low) }
}

@Test func dropTakesTargetsEffectivePriority() throws {
    var f = try board3()
    let target = try f.addCard(project: p, title: "T", due: today)
    let a = try f.addCard(project: p, title: "A")
    #expect(try f.dropCard(a, to: "To Do", onto: target, below: false, today: today) == DropResult(archived: false, priorityChanged: true))
    #expect(f.locate(a)?.card.priority == .high && f.locate(a)?.card.due == nil)
}

@Test func dropOnEmptySpaceKeepsPriority() throws {
    var f = try board3()
    try f.addCard(project: p, title: "X", column: "Doing")
    let a = try f.addCard(project: p, title: "A", priority: .low)
    #expect(try f.dropCard(a, to: "doing", onto: nil, below: false, today: today) == DropResult(archived: false, priorityChanged: false))
    #expect(ids(f, 1) == ["X", "A"] && f.locate(a)?.card.priority == .low)
}

@Test func dropOnSelfIsNoChange() throws {
    var f = try board3()
    try f.addCard(project: p, title: "B")
    let a = try f.addCard(project: p, title: "A")
    let before = f
    #expect(try f.dropCard(a, to: "To Do", onto: a, below: true, today: today) == DropResult(archived: false, priorityChanged: false))
    #expect(f == before)
}

@Test func dropBelowNextCard() throws {
    var f = try board3()
    let c = try f.addCard(project: p, title: "C"), b = try f.addCard(project: p, title: "B"), a = try f.addCard(project: p, title: "A")
    #expect(ids(f, 0) == ["A", "B", "C"])
    try f.dropCard(a, to: "To Do", onto: b, below: true, today: today)
    #expect(ids(f, 0) == ["B", "A", "C"])
    try f.dropCard(c, to: "To Do", onto: b, below: false, today: today)
    #expect(ids(f, 0) == ["C", "B", "A"])
    try f.dropCard(b, to: "To Do", onto: a, below: true, today: today)
    #expect(ids(f, 0) == ["C", "A", "B"])
}

@Test func dropOntoOtherBoardsCard() throws {
    var f = try board3()
    let q = UUID(); try f.createBoard(project: q, columns: ["To Do", "Doing", "Done"])
    try f.addCard(project: p, title: "X", column: "Doing")
    let a = try f.addCard(project: p, title: "A")
    let h = try f.addCard(project: q, title: "H", column: "Doing", priority: .high)
    try f.dropCard(a, to: "Doing", onto: h, below: false, today: today)
    #expect(ids(f, 1) == ["X", "A"] && ids(f, 1, board: q) == ["H"] && f.locate(a)?.card.priority == .high)
}

@Test func dropIntoDoneArchives() throws {
    var f = try board3()
    let a = try f.addCard(project: p, title: "A", due: today, priority: .low)
    #expect(try f.dropCard(a, to: "Done", onto: nil, below: false, today: today).archived)
    #expect(f.board(for: p)!.archive.first?.due == today && f.board(for: p)!.archive.first?.priority == .low)
    try f.restoreCard(a)
    #expect(f.locate(a)?.card.due == today && f.locate(a)?.card.priority == .low)
}

@Test func bigBoardSortsByPriority() throws {
    var f = try board3()
    let q = UUID(); try f.createBoard(project: q, columns: ["To Do", "Done"])
    try f.addCard(project: p, title: "N1"); try f.addCard(project: p, title: "N2")
    try f.addCard(project: q, title: "H", priority: .high)
    #expect(f.bigBoard(today: today)[0].cards.map(\.card.title) == ["H", "N2", "N1"])
}
