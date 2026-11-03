import PMTCore
import SwiftUI

/// Shown for a project with no board: edit the column names, then Create Board.
struct BoardSetupView: View {
    @Environment(AppModel.self) private var model
    let project: ProjectEntry

    private struct Column: Identifiable {
        let id = UUID()
        var name: String
    }

    @State private var columns = ["To Do", "Doing", "Done"].map { Column(name: $0) }

    private var names: [String] {
        columns.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(project.name) has no board").font(.title2)
            List {
                ForEach($columns) { $column in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("Column name", text: $column.name)
                        Button { columns.removeAll { $0.id == column.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove column \(column.name)")
                        .help("Remove column")
                    }
                }
                .onMove { columns.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(maxWidth: 420, maxHeight: 260)
            Button { columns.append(Column(name: "")) } label: { Label("Add Column", systemImage: "plus") }
            Text("The last column is Done. Tasks moved there are archived.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Create Board") {
                model.update { try $0.createBoard(project: project.id, columns: names) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(names.count < 2 || model.loadError != nil)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
