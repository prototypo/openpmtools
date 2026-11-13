import Foundation
import FFCore

public struct OwnProject: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct Card: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var notes: String?
    public var created: Date
    public var due: Day?
    public var priority: Priority?
    public init(id: String, title: String, notes: String? = nil, created: Date, due: Day? = nil, priority: Priority? = nil) {
        self.id = id; self.title = title; self.notes = notes; self.created = created
        self.due = due; self.priority = priority
    }
}

public struct ArchivedCard: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var notes: String?
    public var created: Date
    public var done: Date
    public var fromColumn: String
    public var due: Day?
    public var priority: Priority?

    public init(_ card: Card, fromColumn: String, done: Date) {
        id = card.id; title = card.title; notes = card.notes; created = card.created
        due = card.due; priority = card.priority
        self.done = done; self.fromColumn = fromColumn
    }

    public var card: Card { Card(id: id, title: title, notes: notes, created: created, due: due, priority: priority) }
}

public struct Column: Codable, Hashable, Sendable {
    /// Stable across renames. Files written before ids existed get the name, so every device derives the same one.
    public var id: String
    public var name: String
    public var tasks: [Card]
    public init(name: String, tasks: [Card] = [], id: String? = nil) {
        self.name = name; self.tasks = tasks
        self.id = id ?? name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name), tasks: try c.decode([Card].self, forKey: .tasks),
                  id: try c.decodeIfPresent(String.self, forKey: .id))
    }
}

public struct Board: Codable, Hashable, Sendable {
    public var project: UUID
    public var columns: [Column]
    public var archive: [ArchivedCard]
    public init(project: UUID, columns: [Column], archive: [ArchivedCard] = []) {
        self.project = project; self.columns = columns; self.archive = archive
    }
}

public struct BoardsFile: Codable, Equatable, Sendable {
    public var ownProjects: [OwnProject]
    public var boards: [Board]
    /// Per-field edit stamps for sync. See `BoardsFile.stamped`.
    public var stamps: Stamps = [:]
    /// Deleted item keys to deletion time, so a sync does not bring them back.
    public var deleted: Tombstones = [:]

    public init(ownProjects: [OwnProject] = [], boards: [Board] = []) {
        self.ownProjects = ownProjects; self.boards = boards
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ownProjects = try c.decodeIfPresent([OwnProject].self, forKey: .ownProjects) ?? []
        boards = try c.decodeIfPresent([Board].self, forKey: .boards) ?? []
        stamps = try c.decodeIfPresent(Stamps.self, forKey: .stamps) ?? [:]
        deleted = try c.decodeIfPresent(Tombstones.self, forKey: .deleted) ?? [:]
    }

    enum CodingKeys: String, CodingKey { case ownProjects, boards, stamps, deleted }

    /// Empty `stamps` and `deleted` are left out, so an old file saves as it was.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ownProjects, forKey: .ownProjects)
        try c.encode(boards, forKey: .boards)
        if !stamps.isEmpty { try c.encode(stamps, forKey: .stamps) }
        if !deleted.isEmpty { try c.encode(deleted, forKey: .deleted) }
    }

    /// The file as pretty-printed JSON, exactly as saved to disk.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
