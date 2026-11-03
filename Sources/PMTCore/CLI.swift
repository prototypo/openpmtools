import Foundation
import FFCore

public enum PMTCLI {
    public static let usage = """
    Usage:
      pmt projects [--json]
      pmt project add <name>
      pmt project remove <name> [--force]
      pmt project rename <name> <new>
      pmt board <project> [--json]
      pmt board create <project> <column> <column>...   (the last column is Done)
      pmt board delete <project> [--force]
      pmt board list [--json]
      pmt board attach <project-id> <project-name>
      pmt column add <project> <name> [--at N]
      pmt column rename <project> <name> <new>
      pmt column move <project> <name> <N>
      pmt column remove <project> <name>
      pmt task add <project> <title> [--notes "..."] [--column <name>]
      pmt task edit <id> [--title "..."] [--notes "..."]
      pmt task move <id> <column>
      pmt task done <id>
      pmt task delete <id>
      pmt task restore <id>
      pmt task show <id>
      pmt search <text> [--done] [--json]
      pmt help
    Positions (--at, column move) count from 1.
    Data file: ~/.config/openpmtools/boards.json (override with PMT_CONFIG)
    """

    public static func run(_ argv: [String], store: BoardsStore, ffStore: ConfigStore, now: Date = Date()) throws -> String {
        var args = argv
        let json = takeFlag("--json", from: &args)
        let force = takeFlag("--force", from: &args)
        let done = takeFlag("--done", from: &args)
        let notes = try takeOption("--notes", from: &args)
        let title = try takeOption("--title", from: &args)
        let column = try takeOption("--column", from: &args)
        let atText = try takeOption("--at", from: &args)
        let at = try atText.map { (s: String) throws -> Int in
            guard let n = Int(s), n >= 1 else { throw PMTError.usage(usage) }
            return n - 1
        }
        guard let command = args.first else { throw PMTError.usage(usage) }
        if ["help", "--help", "-h"].contains(command) { return usage }
        let a = Array(args.dropFirst())
        let ff = Catalog.loadFrequentFinder(ffStore).config

        func catalog(_ f: BoardsFile) -> Catalog { Catalog(ff: ff, file: f) }
        func need(_ n: Int) throws { if a.count != n { throw PMTError.usage(usage) } }
        /// Read, resolve names, edit, save. `body` returns the output.
        func edit(_ body: (inout BoardsFile, Catalog) throws -> String) throws -> String {
            var out = ""
            try store.update(ff: ff) { f in out = try body(&f, catalog(f)) }
            return out
        }
        func projectName(_ c: Catalog, _ id: UUID) -> String { c.entry(for: id)?.name ?? "(orphaned)" }
        func show(_ id: String, _ f: BoardsFile) throws -> CardLocation {
            guard let l = f.locate(id) else { throw PMTError.noSuchTask(id) }
            return l
        }

        switch command {
        case "projects":
            try need(0)
            let f = try store.load(), c = catalog(f)
            // inactive FF projects are listed too
            let inactive = ff.projects.filter { !$0.active }.map { ProjectEntry(id: $0.id, name: $0.name, ff: $0) }
            let all = (c.ffProjects.map { ($0, f.board(for: $0.id) != nil) } + inactive.map { ($0, f.board(for: $0.id) != nil) }
                + c.ownProjects.map { ($0, f.board(for: $0.id) != nil) })
            if json {
                return try render(all.map { ["name": $0.name, "source": $0.ff == nil ? "own" : "FrequentFinder",
                                              "hasBoard": $1, "active": $0.isActive] as [String: Any] })
            }
            if all.isEmpty { return "No projects. Add one with: pmt project add <name>" }
            return all.map { p, b in
                [p.name, p.ff == nil ? "own" : "FrequentFinder", b ? "board" : "no board"]
                    .joined(separator: "\t") + (p.isActive ? "" : "\t(inactive)")
            }.joined(separator: "\n")

        case "project":
            guard let sub = a.first else { throw PMTError.usage(usage) }
            let r = Array(a.dropFirst())
            switch sub {
            case "add":
                guard r.count == 1 else { throw PMTError.usage(usage) }
                return try edit { f, _ in try f.addOwnProject(r[0], ff: ff); return "" }
            case "remove", "rename":
                guard r.count == (sub == "remove" ? 1 : 2) else { throw PMTError.usage(usage) }
                return try edit { f, c in
                    let p = try c.resolve(r[0])
                    if p.ff != nil { throw PMTError.usage("'\(p.name)' belongs to FrequentFinder; use 'ff \(sub)' instead.") }
                    if sub == "remove" { try f.removeOwnProject(p.id, force: force) }
                    else { try f.renameOwnProject(p.id, to: r[1], ff: ff) }
                    return ""
                }
            default: throw PMTError.usage(usage)
            }

        case "board":
            guard let sub = a.first else { throw PMTError.usage(usage) }
            let r = Array(a.dropFirst())
            switch sub {
            case "create":
                guard r.count >= 3 else { throw PMTError.usage(usage) }
                return try edit { f, c in try f.createBoard(project: try c.resolve(r[0]).id, columns: Array(r.dropFirst())); return "" }
            case "delete":
                guard r.count == 1 else { throw PMTError.usage(usage) }
                return try edit { f, c in try f.deleteBoard(project: try c.resolve(r[0]).id, force: force); return "" }
            case "list":
                guard r.isEmpty else { throw PMTError.usage(usage) }
                let f = try store.load(), c = catalog(f)
                let rows = f.boards.map { b -> (name: String, id: UUID, open: Int, done: Int) in
                    (projectName(c, b.project), b.project, b.columns.dropLast().reduce(0) { $0 + $1.tasks.count }, b.archive.count)
                }
                if json {
                    return try render(rows.map { ["project": $0.name, "id": $0.id.uuidString, "open": $0.open, "done": $0.done] as [String: Any] })
                }
                return rows.map { "\($0.name)\t\($0.id.uuidString)\t\($0.open) open, \($0.done) done" }.joined(separator: "\n")
            case "attach":
                guard r.count == 2, let id = UUID(uuidString: r[0]) else { throw PMTError.usage(usage) }
                return try edit { f, c in try f.attachBoard(id, to: try c.resolve(r[1]).id); return "" }
            default:
                guard a.count == 1 else { throw PMTError.usage(usage) }
                let f = try store.load()
                let p = try catalog(f).resolve(a[0])
                guard let b = f.board(for: p.id) else { throw PMTError.noBoard }
                if json {
                    return try render(["project": p.name, "columns": b.columns.enumerated().map { i, col in
                        ["name": col.name, "done": i == b.columns.count - 1,
                         "tasks": col.tasks.map { ["id": $0.id, "title": $0.title, "notes": $0.notes ?? ""] }] as [String: Any]
                    }] as [String: Any])
                }
                return b.columns.enumerated().map { i, col in
                    ([col.name + (i == b.columns.count - 1 ? " (done)" : "")] + col.tasks.map { "  \($0.id)  \($0.title)" })
                        .joined(separator: "\n")
                }.joined(separator: "\n")
            }

        case "column":
            guard a.count >= 3 else { throw PMTError.usage(usage) }
            let sub = a[0], r = Array(a.dropFirst())
            return try edit { f, c in
                let p = try c.resolve(r[0]).id
                switch (sub, r.count) {
                case ("add", 2): try f.addColumn(r[1], project: p, at: at)
                case ("rename", 3): try f.renameColumn(r[1], to: r[2], project: p)
                case ("move", 3):
                    guard let n = Int(r[2]), n >= 1 else { throw PMTError.usage(usage) }
                    try f.moveColumn(r[1], to: n - 1, project: p)
                case ("remove", 2): try f.removeColumn(r[1], project: p)
                default: throw PMTError.usage(usage)
                }
                return ""
            }

        case "task":
            guard let sub = a.first else { throw PMTError.usage(usage) }
            let r = Array(a.dropFirst())
            switch (sub, r.count) {
            case ("add", 2):
                return try edit { f, c in
                    let p = try c.resolve(r[0]).id
                    return try f.addCard(project: p, title: r[1], notes: notes, column: column, now: now)
                }
            case ("edit", 1):
                return try edit { f, _ in try f.editCard(r[0], title: title, notes: notes); return "" }
            case ("move", 2):
                return try edit { f, _ in try f.moveCard(r[0], to: r[1], at: at, now: now) ? "Archived \(r[0])" : "" }
            case ("done", 1):
                return try edit { f, _ in
                    guard let l = f.locate(r[0]), let b = f.board(for: l.project), let last = b.columns.last?.name
                    else { throw PMTError.noSuchTask(r[0]) }
                    try f.moveCard(r[0], to: last, now: now)
                    return "Archived \(r[0])"
                }
            case ("delete", 1): return try edit { f, _ in try f.deleteCard(r[0]); return "" }
            case ("restore", 1): return try edit { f, _ in try f.restoreCard(r[0]); return "" }
            case ("show", 1):
                let f = try store.load()
                let l = try show(r[0], f)
                let col = l.column ?? "Done " + ISO8601DateFormatter().string(from: l.done ?? now)
                var s = "id: \(l.card.id)\ntitle: \(l.card.title)\nproject: \(projectName(catalog(f), l.project))\ncolumn: \(col)"
                if let n = l.card.notes { s += "\n\n" + n }
                return s
            default: throw PMTError.usage(usage)
            }

        case "search":
            guard a.count == 1 else { throw PMTError.usage(usage) }
            let f = try store.load(), c = catalog(f)
            let hits = f.search(a[0], includeDone: done)
            func col(_ l: CardLocation) -> String { l.column ?? "Done" }
            if json {
                return try render(hits.map { ["id": $0.card.id, "project": projectName(c, $0.project), "column": col($0),
                                              "title": $0.card.title] as [String: Any] })
            }
            if hits.isEmpty { return "No tasks found." }
            return hits.map { "\($0.card.id)\t\(projectName(c, $0.project))\t\(col($0))\t\($0.card.title)" }.joined(separator: "\n")

        default:
            throw PMTError.usage(usage)
        }
    }

    private static func render(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func takeFlag(_ flag: String, from args: inout [String]) -> Bool {
        guard let i = args.firstIndex(of: flag) else { return false }
        args.remove(at: i)
        return true
    }

    private static func takeOption(_ flag: String, from args: inout [String]) throws -> String? {
        guard let i = args.firstIndex(of: flag) else { return nil }
        guard i + 1 < args.count else { throw PMTError.usage(usage) }
        let value = args[i + 1]
        args.removeSubrange(i...i + 1)
        return value
    }
}
