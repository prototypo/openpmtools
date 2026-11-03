import PMTCore
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
            // SwiftUI's toolbar search field does not take ⌘F by itself.
            CommandGroup(after: .textEditing) {
                Menu("Find") {
                    Button("Find…") { model.focusSearch = true }.keyboardShortcut("f")
                }
            }
        }
    }
}

/// Projects on the left; the selected project's board (or its board setup) on the right.
/// While searching, the results replace the right side.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("selection") private var storedSelection: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
        } detail: {
            if let message = model.loadError {
                ContentUnavailableView {
                    Label("Cannot read boards.json", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("\(message)\n\nThe file was not changed. Edits are paused until it is fixed.")
                }
            } else if !model.search.isEmpty {
                SearchView().navigationTitle("Search")
            } else if let id = model.selection ?? model.offSidebar,
                      let entry = model.catalog.entry(for: id)
                          ?? model.file.board(for: id).map({ _ in ProjectEntry(id: id, name: "(orphaned board)", ff: nil) }) {
                Group {
                    if model.file.board(for: id) == nil {
                        BoardSetupView(project: entry)
                    } else {
                        BoardView(project: entry, highlight: model.highlight?.project == id ? model.highlight?.card : nil)
                    }
                }
                .id(id)
                .navigationTitle(entry.name)
            } else {
                Text("Select a project").foregroundStyle(.secondary)
                    .navigationTitle("OpenPMTools")
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search Tasks")
        .searchFocused($searchFocused)
        .onChange(of: model.focusSearch) {
            if model.focusSearch { searchFocused = true; model.focusSearch = false }
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $model.includeDone) { Label("Include Done", systemImage: "archivebox") }
                    .help("Include Done")
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { model.selection = storedSelection.flatMap(UUID.init(uuidString:)) }
        .onChange(of: model.selection) {
            storedSelection = model.selection?.uuidString
            // Picking a sidebar row leaves any off-sidebar board and drops another project's highlight.
            if let s = model.selection {
                model.offSidebar = nil
                if model.highlight?.project != s { model.highlight = nil }
            }
        }
    }
}
