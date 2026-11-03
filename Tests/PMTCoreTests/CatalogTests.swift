import Foundation
import Testing
import FFCore
@testable import PMTCore

@Test func catalogMergesAndPrunes() throws {
    let shared = UUID()
    let ff = Config(projects: [Project(id: shared, name: "Breakthrough", path: nil),
                               Project(name: "Old", path: nil, active: false)])
    var f = BoardsFile(ownProjects: [OwnProject(id: shared, name: "Breakthrough"), OwnProject(id: UUID(), name: "Garden")], boards: [])
    let c = Catalog(ff: ff, file: f)
    #expect(c.ffProjects.map(\.name) == ["Breakthrough"])
    #expect(c.ownProjects.map(\.name) == ["Garden"])
    #expect(try c.resolve(" old ").name == "Old")
    f.pruneOwnProjects(ff: ff)
    #expect(f.ownProjects.map(\.name) == ["Garden"])
}

@Test func ownProjectNamesAreUniqueAcrossBothApps() throws {
    let ff = Config(projects: [Project(name: "Breakthrough", path: nil)])
    var f = BoardsFile()
    #expect(throws: PMTError.duplicateName("breakthrough ")) { try f.addOwnProject("breakthrough ", ff: ff) }
    _ = try f.addOwnProject(" Garden ", ff: ff)
    #expect(throws: PMTError.duplicateName("GARDEN")) { try f.addOwnProject("GARDEN", ff: ff) }
    #expect(f.ownProjects.map(\.name) == ["Garden"])
}

@Test func orphanBoardsAreListedAndSearchable() throws {
    let gone = UUID()
    var f = BoardsFile(); try f.createBoard(project: gone, columns: ["A", "Done"])
    _ = try f.addCard(project: gone, title: "Launch email")
    #expect(Catalog(ff: Config(), file: f).orphanBoards == [gone])
    #expect(f.search("EMAIL", includeDone: false).map(\.card.title) == ["Launch email"])
    let newID = try f.addOwnProject("Breakthrough", ff: Config())
    try f.attachBoard(gone, to: newID)
    #expect(Catalog(ff: Config(), file: f).orphanBoards.isEmpty)
}

@Test func brokenFrequentFinderFileGivesEmptyCatalog() throws {
    let dir = try makeTempDir()
    let url = URL(fileURLWithPath: dir + "/projects.json")
    try Data("{ broken".utf8).write(to: url)
    let (config, error) = Catalog.loadFrequentFinder(ConfigStore(url: url))
    #expect(config.projects.isEmpty && error != nil)
    #expect(try String(contentsOf: url, encoding: .utf8) == "{ broken")
    #expect(Catalog.loadFrequentFinder(ConfigStore(url: URL(fileURLWithPath: dir + "/none.json"))).error == nil)
}

@Test func searchIncludesDoneOnlyWhenAsked() throws {
    let p = UUID()
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "Done"])
    let old = try f.addCard(project: p, title: "ship old")
    let new = try f.addCard(project: p, title: "ship new")
    _ = try f.addCard(project: p, title: "other", notes: "will SHIP later")
    try f.moveCard(old, to: "Done", now: Date(timeIntervalSince1970: 100))
    try f.moveCard(new, to: "Done", now: Date(timeIntervalSince1970: 200))
    #expect(f.search("ship", includeDone: false).map(\.card.title) == ["other"])
    #expect(f.search("ship", includeDone: true).map(\.card.title) == ["other", "ship new", "ship old"])
    #expect(f.search("  ", includeDone: true).isEmpty)
}

@Test func ambiguousNameThrows() throws {
    let ff = Config(projects: [Project(name: "Garden", path: nil)])
    let f = BoardsFile(ownProjects: [OwnProject(name: "garden")])
    #expect(throws: PMTError.ambiguousName("garden")) { try Catalog(ff: ff, file: f).resolve("garden") }
    #expect(throws: PMTError.noSuchProject("zzz")) { try Catalog(ff: ff, file: f).resolve("zzz") }
}

@Test func removeOwnProjectNeedsForceWhenBoardHasTasks() throws {
    var f = BoardsFile()
    let id = try f.addOwnProject("Garden", ff: Config())
    try f.createBoard(project: id, columns: ["A", "Done"])
    _ = try f.addCard(project: id, title: "x")
    #expect(throws: PMTError.boardHasTasks) { try f.removeOwnProject(id, force: false) }
    try f.removeOwnProject(id, force: true)
    #expect(f.ownProjects.isEmpty && f.boards.isEmpty)
}

@Test func renameOwnProjectChecksNames() throws {
    var f = BoardsFile()
    let a = try f.addOwnProject("A", ff: Config())
    _ = try f.addOwnProject("B", ff: Config())
    #expect(throws: PMTError.duplicateName("b")) { try f.renameOwnProject(a, to: "b", ff: Config()) }
    #expect(throws: PMTError.emptyName) { try f.renameOwnProject(a, to: " ", ff: Config()) }
    try f.renameOwnProject(a, to: " a ", ff: Config())
    #expect(f.ownProjects.map(\.name) == ["a", "B"])
}
