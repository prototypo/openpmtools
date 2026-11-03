import Foundation
import FFCore
import PMTCore

do {
    let output = try PMTCLI.run(Array(CommandLine.arguments.dropFirst()), store: BoardsStore(), ffStore: ConfigStore())
    if !output.isEmpty { print(output) }
} catch PMTError.usage(let text) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("pmt: \(error)\n".utf8))
    exit(1)
}
