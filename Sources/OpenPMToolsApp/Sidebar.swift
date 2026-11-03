import FFCore
import PMTCore
import SwiftUI

/// The project list: FrequentFinder's active projects, then own projects.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var renaming: ProjectEntry?
    @State private var deleting: ProjectEntry?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("FrequentFinder") {
                if let ffError = model.ffError {
                    Text(ffError).foregroundStyle(.secondary)
                }
                ForEach(model.catalog.ffProjects) { entry in
                    let status = model.combinedGit(entry)
                    Label {
                        Text(entry.name)
                    } icon: {
                        Image(systemName: GitSymbol.name(for: status)).foregroundStyle(GitSymbol.color(for: status))
                    }
                    .accessibilityLabel("\(entry.name), \(GitSymbol.description(for: status))")
                    .tag(entry.id)
                }
            }
            Section("My Projects") {
                ForEach(model.catalog.ownProjects) { entry in
                    Label(entry.name, systemImage: "rectangle.split.3x1")
                        .tag(entry.id)
                        .draggable(ProjectDrag(id: entry.id, name: entry.name))
                        .contextMenu {
                            Button("Rename…") { renaming = entry }
                            Button("Delete…", role: .destructive) { deleting = entry }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = model.loadError ?? model.error {
                Text(message).foregroundStyle(.red).padding(8)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .toolbar {
            ToolbarItem {
                Button { model.addingProject = true } label: { Label("New Project", systemImage: "plus") }
                    .help("New Project")
                    .disabled(model.loadError != nil)
            }
        }
        .sheet(isPresented: $model.addingProject) {
            NameSheet(title: "New Project", button: "Create", name: "") { name in
                model.update { try $0.addOwnProject(name, ff: model.ff) }
            }
        }
        .sheet(item: $renaming) { entry in
            NameSheet(title: "Rename Project", button: "Rename", name: entry.name) { name in
                model.update { try $0.renameOwnProject(entry.id, to: name, ff: model.ff) }
            }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { entry in
            Button("Delete", role: .destructive) {
                model.update { try $0.removeOwnProject(entry.id, force: true) }
            }
        } message: { entry in
            if hasTasks(entry) {
                Text("Its board and all its tasks, including done tasks, will be deleted.")
            } else {
                Text("This cannot be undone.")
            }
        }
    }

    private func hasTasks(_ entry: ProjectEntry) -> Bool {
        guard let b = model.file.board(for: entry.id) else { return false }
        return !b.archive.isEmpty || b.columns.contains { !$0.tasks.isEmpty }
    }
}

/// Asks for a project name. `save` returns false on failure; the error then shows here.
private struct NameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    let button: String
    @State var name: String
    let save: (String) -> Bool
    @State private var failure: String?

    init(title: String, button: String, name: String, save: @escaping (String) -> Bool) {
        self.title = title
        self.button = button
        _name = State(initialValue: name)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $name).frame(width: 280)
            if let failure {
                Text(failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(button) {
                    if save(name) {
                        dismiss()
                    } else {
                        failure = model.loadError ?? model.error
                        model.error = nil  // shown here, not also in the sidebar
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}
