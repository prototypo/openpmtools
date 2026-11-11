import AppKit
import FFCore
import PMTCore
import SwiftUI

/// Our URL scheme: `openpmtools://project/<UUID>` shows that project's board. Declared in scripts/make-app.sh.
let linkScheme = "openpmtools"

@main
struct OpenPMToolsApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("OpenPMTools", id: "main") {
            ContentView().environment(model)
        }
        .defaultSize(width: 1000, height: 640)
        // Project links open here (ContentView.onOpenURL), never in Big Board.
        .handlesExternalEvents(matching: ["project"])
        .commands {
            NewItemCommands(model: model)
            // SwiftUI's toolbar search field does not take ⌘F by itself.
            CommandGroup(after: .textEditing) {
                Menu("Find") {
                    Button("Find…") { model.focusSearch = true }.keyboardShortcut("f")
                }
            }
        }

        Window("Big Board", id: "big-board") {
            BigBoardView().environment(model)
                .frame(minWidth: 520, minHeight: 360)
                .background(WindowReader { $0.setFrameAutosaveName("BigBoard") })
        }
        .defaultSize(width: 1200, height: 700)
        .handlesExternalEvents(matching: [])

        Settings {
            SettingsView().environment(model)
        }
    }
}

/// Projects on the left; the selected project's board (or its board setup) on the right.
/// While searching, the results replace the right side.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("selection") private var storedSelection: String?
    @FocusState private var searchFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var addingTask = false

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
        .toolbar {
            if let id = model.selection ?? model.offSidebar {
                ToolbarItemGroup { OpenInButtons(project: id) }
            }
            ToolbarItem {
                Button { openWindow(id: "big-board") } label: { Label("Big Board", systemImage: "square.grid.3x3.topleft.filled") }
                    .help("Show all tasks from all projects")
            }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search Tasks")
        .searchFocused($searchFocused)
        .onChange(of: model.focusSearch) {
            if model.focusSearch { searchFocused = true; model.focusSearch = false }
        }
        // A scope bar (HIG: search scopes) shows the choice as labelled segments under the toolbar while searching.
        .searchScopes($model.includeDone) {
            Text("Open Tasks").tag(false)
            Text("Include Done").tag(true)
        }
        .frame(minWidth: 760, minHeight: 480)
        .focusedSceneValue(\.newTask, newTaskProject.map { _ in NewTaskAction { addingTask = true } })
        .sheet(isPresented: $addingTask) {
            if let id = newTaskProject, let first = model.file.board(for: id)?.columns.first?.name {
                CardEditor(heading: "New Task in \(first)", button: "Add", draft: CardDraft()) { d in
                    model.update { try $0.addCard(project: id, title: d.title, notes: d.notes, due: d.due, priority: d.priority) }
                }
            }
        }
        // Saves and restores the window's size and place across runs.
        .background(WindowReader { $0.setFrameAutosaveName("Main") })
        // A link that opened this window has already chosen a project; keep it.
        .onAppear {
            if model.selection == nil && model.offSidebar == nil {
                model.selection = storedSelection.flatMap(UUID.init(uuidString:))
            }
        }
        .onOpenURL { url in
            let found = LinkedApp.projectID(in: url, scheme: linkScheme).map { model.openLink(project: $0) } ?? false
            if !found { model.flash("No project with this link.") }
        }
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

extension ContentView {
    /// The shown project, when it has a board: where ⌘N puts a new task.
    private var newTaskProject: UUID? {
        guard let id = model.selection ?? model.offSidebar, model.file.board(for: id) != nil else { return nil }
        return id
    }
}

/// Calls `onWindow` once with the NSWindow that hosts this view. Copied from FrequentFinder.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { ReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ReaderView: NSView {
        let onWindow: (NSWindow) -> Void
        private weak var seen: NSWindow?

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== seen else { return }
            seen = window
            onWindow(window)
        }
    }
}
