import Foundation
@testable import PMTCore

func makeTempDir() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}

func tempStore() throws -> BoardsStore {
    BoardsStore(url: URL(fileURLWithPath: try makeTempDir()).appendingPathComponent("boards.json"))
}
