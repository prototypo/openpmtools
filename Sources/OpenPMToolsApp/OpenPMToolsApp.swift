import SwiftUI

@main
struct OpenPMToolsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("OpenPMTools", id: "main") {
            ContentView().environment(model)
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project…") { model.addingProject = true }
                    .keyboardShortcut("n")
                    .disabled(model.loadError != nil)
            }
        }
    }
}

/// Projects on the left; the selected project's board (or its board setup) on the right.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("selection") private var storedSelection: String?

    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            if let id = model.selection, let entry = model.catalog.entry(for: id) {
                Group {
                    if model.file.board(for: id) == nil {
                        BoardSetupView(project: entry)
                    } else {
                        BoardView(project: entry)
                    }
                }
                .id(id)
                .navigationTitle(entry.name)
            } else {
                Text("Select a project").foregroundStyle(.secondary)
                    .navigationTitle("OpenPMTools")
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { model.selection = storedSelection.flatMap(UUID.init(uuidString:)) }
        .onChange(of: model.selection) { storedSelection = model.selection?.uuidString }
    }
}
