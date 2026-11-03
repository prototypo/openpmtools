import Foundation
import Testing
import FFCore
@testable import PMTCore

struct CLITests {
    let store: BoardsStore
    let ffStore: ConfigStore

    init() throws {
        store = try tempStore()
        ffStore = ConfigStore(url: URL(fileURLWithPath: try makeTempDir()).appendingPathComponent("ff.json"))
    }

    @discardableResult
    func pmt(_ args: String...) throws -> String { try PMTCLI.run(args, store: store, ffStore: ffStore) }

    @Test func cliEndToEnd() throws {
        try pmt("project", "add", "Breakthrough")
        try pmt("board", "create", "breakthrough", "To Do", "Doing", "Done")
        let id = try pmt("task", "add", "Breakthrough", "Launch email", "--notes", "Draft by Friday")
        #expect(try pmt("board", "Breakthrough") == "To Do\n  \(id)  Launch email\nDoing\nDone (done)")
        #expect(try pmt("task", "move", id, "Done") == "Archived \(id)")
        #expect(try pmt("search", "friday") == "No tasks found.")
        #expect(try pmt("search", "friday", "--done") == "\(id)\tBreakthrough\tDone\tLaunch email")
        try pmt("task", "restore", id)
        #expect(try pmt("board", "Breakthrough").contains("To Do\n  \(id)"))
    }

    @Test func cliSeesFrequentFinderProjects() throws {
        try ffStore.save(Config(projects: [Project(name: "openpmtools", path: nil)]))
        #expect(try pmt("projects") == "openpmtools\tFrequentFinder\tno board")
        #expect(throws: PMTError.duplicateName("OpenPMTools")) { try pmt("project", "add", "OpenPMTools") }
        #expect(throws: PMTError.self) { try pmt("project", "remove", "openpmtools") }
    }

    @Test func cliBoardAttach() throws {
        let gone = UUID()
        var f = BoardsFile(); try f.createBoard(project: gone, columns: ["A", "Done"]); try store.save(f)
        #expect(try pmt("board", "list") == "(orphaned)\t\(gone.uuidString)\t0 open, 0 done")
        try pmt("project", "add", "Book")
        try pmt("board", "attach", gone.uuidString.lowercased(), "book")
        #expect(try pmt("board", "list").hasPrefix("Book\t"))
    }

    @Test func cliUsageErrors() throws {
        #expect(throws: PMTError.self) { try pmt() }
        #expect(throws: PMTError.self) { try pmt("frobnicate") }
        try pmt("project", "add", "P")
        try pmt("board", "create", "P", "A", "Done")
        #expect(throws: PMTError.self) { try pmt("task", "add", "P", "t", "--notes") }
        #expect(try pmt("help").contains("Data file: ~/.config/openpmtools/boards.json (override with PMT_CONFIG)"))
    }

    @Test func cliColumnMoveIsOneBased() throws {
        try pmt("project", "add", "P")
        try pmt("board", "create", "P", "A", "B", "C", "Done")
        try pmt("column", "move", "P", "C", "1")
        #expect(try pmt("board", "P") == "C\nA\nB\nDone (done)")
        try pmt("column", "add", "P", "X", "--at", "2")
        #expect(try pmt("board", "P") == "C\nX\nA\nB\nDone (done)")
    }

    @Test func cliDeleteBoardNeedsForce() throws {
        try pmt("project", "add", "P")
        try pmt("board", "create", "P", "A", "Done")
        try pmt("task", "add", "P", "t")
        #expect(throws: PMTError.boardHasTasks) { try pmt("board", "delete", "P") }
        try pmt("board", "delete", "P", "--force")
        #expect(try pmt("projects") == "P\town\tno board")
    }

    @Test func cliJSONParses() throws {
        try pmt("project", "add", "P")
        try pmt("board", "create", "P", "A", "Done")
        try pmt("task", "add", "P", "hello")
        for args in [["projects"], ["board", "P"], ["board", "list"], ["search", "hello"]] {
            let out = try PMTCLI.run(args + ["--json"], store: store, ffStore: ffStore)
            _ = try JSONSerialization.jsonObject(with: Data(out.utf8))
        }
    }

    @Test func cliShowEditDelete() throws {
        try pmt("project", "add", "P")
        try pmt("board", "create", "P", "A", "Done")
        let id = try pmt("task", "add", "P", "t", "--notes", "n")
        #expect(try pmt("task", "show", id) == "id: \(id)\ntitle: t\nproject: P\ncolumn: A\n\nn")
        try pmt("task", "edit", id, "--title", "u")
        #expect(try pmt("task", "done", id) == "Archived \(id)")
        try pmt("task", "delete", id)
        #expect(throws: PMTError.self) { try pmt("task", "show", id) }
    }
}
