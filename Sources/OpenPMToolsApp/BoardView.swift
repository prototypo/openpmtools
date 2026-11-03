import PMTCore
import SwiftUI

/// Placeholder until Task 8 builds the board.
struct BoardView: View {
    let project: ProjectEntry
    var highlight: String? = nil

    var body: some View {
        Text("\(project.name) board").foregroundStyle(.secondary)
    }
}
