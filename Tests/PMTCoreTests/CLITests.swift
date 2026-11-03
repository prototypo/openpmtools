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

    @Test func cliAmbiguousNameCanBeRenamed() throws {
        try store.save(BoardsFile(ownProjects: [OwnProject(name: "Book")], boards: []))
        try ffStore.save(Config(projects: [Project(name: "Book", path: nil)]))
        do { _ = try pmt("board", "Book"); Issue.record("expected ambiguity") }
        catch {
            let m = "\(error)"
            #expect(m.contains("pmt project rename Book <new>") && m.contains("ff rename Book <new>"))
        }
        try pmt("project", "rename", "Book", "Novel")
        #expect(throws: PMTError.noBoard) { try pmt("board", "Novel") }
        #expect(try pmt("projects").contains("Novel\town\tno board"))
        #expect(try pmt("projects").contains("Book\tFrequentFinder"))
    }

    @Test func badConfigMessageHasOnePeriod() {
        #expect("\(PMTError.badConfig("/x/boards.json: bad data."))" == "Cannot read /x/boards.json: bad data. Fix the file; it was not changed.")
        #expect("\(PMTError.badConfig("/x/boards.json: bad data"))" == "Cannot read /x/boards.json: bad data. Fix the file; it was not changed.")
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

    @Test func cliOptionsDoNotSwallowOrAcceptUnknown() throws {
        try pmt("project", "add", "P")
        try pmt("board", "create", "P", "A", "Done")
        #expect(throws: PMTError.self) { try pmt("task", "add", "P", "title", "--notes", "--title", "x") }
        #expect(throws: PMTError.self) { try pmt("task", "add", "P", "title", "--bogus") }
        #expect(try pmt("board", "P") == "A\nDone (done)")
    }

    @Test func cliOwnProjectRemoveAndRename() throws {
        try pmt("project", "add", "P")
        try pmt("project", "rename", "p", "Q")
        #expect(try pmt("projects") == "Q\town\tno board")
        try pmt("project", "remove", "Q")
        #expect(try pmt("projects") == "No projects. Add one with: pmt project add <name>")

        try pmt("project", "add", "R")
        try pmt("board", "create", "R", "A", "Done")
        try pmt("task", "add", "R", "t")
        #expect(throws: PMTError.boardHasTasks) { try pmt("project", "remove", "R") }
        try pmt("project", "remove", "R", "--force")
        #expect(try pmt("projects").hasPrefix("No projects"))
        #expect(try pmt("board", "list") == "")
    }

    @Test func cliFrequentFinderRedirect() throws {
        try ffStore.save(Config(projects: [Project(name: "ffp", path: nil)]))
        for (sub, args) in [("remove", ["project", "remove", "ffp"]), ("rename", ["project", "rename", "ffp", "x"])] {
            do { _ = try PMTCLI.run(args, store: store, ffStore: ffStore); Issue.record("no error") }
            catch let PMTError.usage(text) { #expect(text.contains("ff \(sub)")) }
        }
    }

    @Test func cliColumnRenameRemoveAndTaskColumns() throws {
        try pmt("project", "add", "P")
        try pmt("board", "create", "P", "A", "B", "C", "Done")
        try pmt("column", "rename", "P", "b", "Bee")
        try pmt("column", "remove", "P", "A")
        #expect(try pmt("board", "P") == "Bee\nC\nDone (done)")
        let id = try pmt("task", "add", "P", "t", "--column", "C")
        #expect(try pmt("board", "P") == "Bee\nC\n  \(id)  t\nDone (done)")
        #expect(try pmt("task", "move", id, "Bee") == "")
        #expect(try pmt("board", "P") == "Bee\n  \(id)  t\nC\nDone (done)")
        #expect(throws: PMTError.columnNotEmpty("Bee")) { try pmt("column", "remove", "P", "Bee") }
    }

    @Test func cliInactiveAndBrokenFrequentFinder() throws {
        var off = Project(name: "old", path: nil); off.active = false
        try ffStore.save(Config(projects: [off]))
        #expect(try pmt("projects") == "old\tFrequentFinder\tno board\t(inactive)")
        try Data("{ not json".utf8).write(to: ffStore.url)
        try pmt("project", "add", "Own")
        #expect(try pmt("projects") == "Own\town\tno board")
        #expect(try String(contentsOf: ffStore.url, encoding: .utf8) == "{ not json")
    }
}
