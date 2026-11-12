import Foundation
import FFCore

public struct BoardsStore: Sendable {
    public let url: URL
    /// Nil means read the device file at save time.
    public let device: Device?

    public init(url: URL = BoardsStore.defaultURL, device: Device? = nil) {
        self.url = url
        self.device = device
    }

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

    /// Stamps what changed from `before`, then saves. Returns the file as saved.
    @discardableResult
    public func save(_ file: BoardsFile, changedFrom before: BoardsFile) throws -> BoardsFile {
        let d = try device ?? Device.load()
        let out = file.stamped(from: before, by: d, now: Date())
        try save(out)
        return out
    }

    /// Re-reads, applies `change`, prunes own projects, and saves only if something changed.
    @discardableResult
    public func update(ff: FFCore.Config, _ change: (inout BoardsFile) throws -> Void) throws -> BoardsFile {
        var file = try load()
        let before = file
        try change(&file)
        file.pruneOwnProjects(ff: ff)
        if file != before { file = try save(file, changedFrom: before) }
        return file
    }
}
