import Foundation

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
    public init(id: String, title: String, notes: String? = nil, created: Date) {
        self.id = id; self.title = title; self.notes = notes; self.created = created
    }
}

public struct ArchivedCard: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var notes: String?
    public var created: Date
    public var done: Date
    public var fromColumn: String

    public init(_ card: Card, fromColumn: String, done: Date) {
        id = card.id; title = card.title; notes = card.notes; created = card.created
        self.done = done; self.fromColumn = fromColumn
    }

    public var card: Card { Card(id: id, title: title, notes: notes, created: created) }
}

public struct Column: Codable, Hashable, Sendable {
    public var name: String
    public var tasks: [Card]
    public init(name: String, tasks: [Card] = []) { self.name = name; self.tasks = tasks }
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

    public init(ownProjects: [OwnProject] = [], boards: [Board] = []) {
        self.ownProjects = ownProjects; self.boards = boards
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ownProjects = try c.decodeIfPresent([OwnProject].self, forKey: .ownProjects) ?? []
        boards = try c.decodeIfPresent([Board].self, forKey: .boards) ?? []
    }

    /// The file as pretty-printed JSON, exactly as saved to disk.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
