import Foundation
import FFCore

public struct ProjectEntry: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// nil means an own project.
    public var ff: FFCore.Project?
    public var isActive: Bool { ff?.active ?? true }
    public init(id: UUID, name: String, ff: FFCore.Project?) { self.id = id; self.name = name; self.ff = ff }
}

public struct Catalog: Sendable {
    /// Active FrequentFinder projects, in FrequentFinder order.
    public let ffProjects: [ProjectEntry]
    /// Own projects whose id is not in FrequentFinder, in file order.
    public let ownProjects: [ProjectEntry]
    /// Boards whose project is in neither FrequentFinder (active or not) nor the own list.
    public let orphanBoards: [UUID]
    private let all: [ProjectEntry]

    public init(ff: FFCore.Config, file: BoardsFile) {
        let allFF = ff.projects.map { ProjectEntry(id: $0.id, name: $0.name, ff: $0) }
        let ffIDs = Set(allFF.map(\.id))
        ffProjects = allFF.filter(\.isActive)
        ownProjects = file.ownProjects.filter { !ffIDs.contains($0.id) }.map { ProjectEntry(id: $0.id, name: $0.name, ff: nil) }
        all = allFF + ownProjects
        let known = Set(all.map(\.id))
        orphanBoards = file.boards.map(\.project).filter { !known.contains($0) }
    }

    public func entry(for id: UUID) -> ProjectEntry? { all.first { $0.id == id } }

    public func resolve(_ name: String) throws -> ProjectEntry {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hits = all.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(n) == .orderedSame }
        guard let first = hits.first else { throw PMTError.noSuchProject(n) }
        if hits.count > 1 { throw PMTError.ambiguousName(n) }
        return first
    }

    /// Never writes: a missing file is empty with no error; a broken one is empty plus the error text.
    public static func loadFrequentFinder(_ store: ConfigStore = ConfigStore()) -> (config: FFCore.Config, error: String?) {
        do { return (try store.load(), nil) }
        catch { return (FFCore.Config(), "\(error)") }
    }
}

extension BoardsFile {
    private func nameTaken(_ name: String, ff: FFCore.Config, except id: UUID? = nil) -> Bool {
        func eq(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame }
        return ff.projects.contains { eq($0.name) } || ownProjects.contains { $0.id != id && eq($0.name) }
    }

    @discardableResult
    public mutating func addOwnProject(_ name: String, ff: FFCore.Config) throws -> UUID {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { throw PMTError.emptyName }
        if nameTaken(n, ff: ff) { throw PMTError.duplicateName(name) }
        let p = OwnProject(name: n)
        ownProjects.append(p)
        return p.id
    }

    public mutating func renameOwnProject(_ id: UUID, to name: String, ff: FFCore.Config) throws {
        guard let i = ownProjects.firstIndex(where: { $0.id == id }) else { throw PMTError.noSuchProject(id.uuidString) }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { throw PMTError.emptyName }
        if nameTaken(n, ff: ff, except: id) { throw PMTError.duplicateName(name) }
        ownProjects[i].name = n
    }

    public mutating func removeOwnProject(_ id: UUID, force: Bool) throws {
        if board(for: id) != nil { try deleteBoard(project: id, force: force) }
        ownProjects.removeAll { $0.id == id }
    }

    public mutating func pruneOwnProjects(ff: FFCore.Config) {
        let ids = Set(ff.projects.map(\.id))
        ownProjects.removeAll { ids.contains($0.id) }
    }

    public mutating func attachBoard(_ boardProject: UUID, to project: UUID) throws {
        guard let i = boards.firstIndex(where: { $0.project == boardProject }) else {
            throw PMTError.noSuchBoard(boardProject.uuidString)
        }
        if boardProject != project && board(for: project) != nil { throw PMTError.boardExists }
        boards[i].project = project
    }

    /// Open cards in board/column order, then (if asked) archived cards, newest `done` first.
    public func search(_ text: String, includeDone: Bool) -> [CardLocation] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return [] }
        func hit(_ c: Card) -> Bool {
            c.title.localizedCaseInsensitiveContains(q) || (c.notes?.localizedCaseInsensitiveContains(q) ?? false)
        }
        var open: [CardLocation] = []
        var done: [CardLocation] = []
        for b in boards {
            for col in b.columns {
                open += col.tasks.filter(hit).map { CardLocation(project: b.project, column: col.name, card: $0, done: nil) }
            }
            if includeDone {
                done += b.archive.filter { hit($0.card) }.map { CardLocation(project: b.project, column: nil, card: $0.card, done: $0.done) }
            }
        }
        return open + done.sorted { ($0.done ?? .distantPast) > ($1.done ?? .distantPast) }
    }
}
