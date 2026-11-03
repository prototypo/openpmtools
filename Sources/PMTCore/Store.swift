import Foundation
import FFCore

public struct BoardsStore: Sendable {
    public let url: URL

    public init(url: URL = BoardsStore.defaultURL) { self.url = url }

    /// `$PMT_CONFIG` if set, else `~/.config/openpmtools/boards.json`.
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["PMT_CONFIG"] {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/openpmtools/boards.json")
    }

    /// A missing file is empty. A file that cannot be parsed throws `PMTError.badConfig`.
    public func load() throws -> BoardsFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return BoardsFile() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(BoardsFile.self, from: try Data(contentsOf: url))
        } catch {
            throw PMTError.badConfig("\(url.path): \(error.localizedDescription)")
        }
    }

    /// Writes atomically.
    public func save(_ file: BoardsFile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.jsonData().write(to: url, options: .atomic)
    }

    /// Re-reads, applies `change`, prunes own projects, and saves only if something changed.
    @discardableResult
    public func update(ff: FFCore.Config, _ change: (inout BoardsFile) throws -> Void) throws -> BoardsFile {
        var file = try load()
        let before = file
        try change(&file)
        file.pruneOwnProjects(ff: ff)
        if file != before { try save(file) }
        return file
    }
}
