import AppKit
import PMTCore
import SwiftUI

/// The selected project's columns side by side. The last column is Done: dropping a card there archives it.
struct BoardView: View {
    @Environment(AppModel.self) private var model
    let project: ProjectEntry
    /// A card id to scroll to and flash briefly.
    var highlight: String? = nil
    @State private var flashing: String?

    var body: some View {
        if let board = model.file.board(for: project.id) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(board.columns.enumerated()), id: \.element.name) { i, column in
                            ColumnView(board: board, index: i, project: project.id, flashing: flashing, move: move)
                        }
                    }
                    .padding(12)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .onAppear { flash(highlight, proxy) }
                .onChange(of: highlight) { flash(highlight, proxy) }
            }
        }
    }

    private func flash(_ id: String?, _ proxy: ScrollViewProxy) {
        guard let id else { return }
        DispatchQueue.main.async { withAnimation { proxy.scrollTo(id, anchor: .center) } }
        flashing = id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if flashing == id { withAnimation { flashing = nil } }
        }
    }

    private func move(_ id: String, to column: String, at index: Int?, poofAt point: NSPoint) {
        model.move(id, to: column, at: index, poofAt: point)
    }
}

extension AppModel {
    /// Moves a card on its board. When it lands in Done, the poof plays at `point` (screen coordinates).
    func move(_ id: String, to column: String, at index: Int?, poofAt point: NSPoint) {
        var archived = false
        guard update({ archived = try $0.moveCard(id, to: column, at: index) }), archived else { return }
        (Poof() as PoofShowing).show(at: point)
    }

    /// A dragged card dropped in `column`, on card `target` (nil = empty space). It takes the target's
    /// priority (see BoardsFile.dropCard). VoiceOver hears when that changes its priority.
    @discardableResult
    func drop(_ id: String, to column: String, onto target: String?, below: Bool, poofAt point: NSPoint) -> Bool {
        var result: DropResult?
        guard update({ result = try $0.dropCard(id, to: column, onto: target, below: below, today: today) }),
              let result else { return false }
        if result.archived { (Poof() as PoofShowing).show(at: point) }
        if result.priorityChanged {
            let label = file.locate(id)?.card.priority?.label ?? "None"
            AccessibilityNotification.Announcement("Priority changed to \(label)").post()
        }
        return true
    }
}

/// The Dock's puff of smoke. NSAnimationEffect is deprecated (macOS 14) but still works and has no
/// replacement that animates at a point; calling it through a protocol keeps the build free of warnings.
/// Its length is fixed by the system. It waits a moment so the drag image is gone first, and plays
/// larger than the default so it is easy to see.
// ponytail: if Apple removes NSAnimationEffect, drop the poof and keep the archive.
private protocol PoofShowing { func show(at point: NSPoint) }
private struct Poof: PoofShowing {
    @available(macOS, deprecated: 14)
    func show(at point: NSPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSAnimationEffect.disappearingItemDefault.show(centeredAt: point, size: NSSize(width: 96, height: 96))
        }
    }
}

private struct ColumnView: View {
    @Environment(AppModel.self) private var model
    let board: Board
    let index: Int
    let project: UUID
    let flashing: String?
    let move: (String, String, Int?, NSPoint) -> Void
    @State private var targeted = false
    @State private var addingCard = false
    @State private var renaming = false
    @State private var addingColumn = false

    private var column: PMTCore.Column { board.columns[index] }
    private var isDone: Bool { index == board.columns.count - 1 }
    private var names: [String] { board.columns.map(\.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isDone {
                doneArea
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 8) {
                        ForEach(displayOrder(column.tasks, today: model.today) { $0 }, id: \.id) { card in
                            CardView(card: card, column: column.name, columns: names, flashing: flashing == card.id) {
                                move(card.id, $0, nil, $1)
                            } drop: { id, below in
                                drop(id, onto: card.id, below: below)
                            }
                            .id(card.id)
                        }
                    }
                    .padding(2)
                }
                // The space below the cards takes drops at the end of the column.
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(8)
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(targeted ? AnyShapeStyle(.selection.opacity(0.3)) : AnyShapeStyle(.quinary),
                    in: RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            return drop(id, onto: nil, below: false)
        } isTargeted: { targeted = $0 }
        .sheet(isPresented: $addingCard) {
            CardEditor(heading: "New Task in \(column.name)", button: "Add", draft: CardDraft()) { d in
                model.update {
                    try $0.addCard(project: project, title: d.title, notes: d.notes, column: column.name, due: d.due, priority: d.priority)
                }
            }
        }
        .sheet(isPresented: $renaming) {
            NameSheet(title: "Rename Column", button: "Rename", name: column.name) { name in
                model.update { try $0.renameColumn(column.name, to: name, project: project) }
            }
        }
        .sheet(isPresented: $addingColumn) {
            NameSheet(title: "Add Column", button: "Add", name: "") { name in
                // addColumn keeps Done last, so index + 1 on Done lands just before it.
                model.update { try $0.addColumn(name, project: project, at: index + 1) }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(column.name).font(.headline)
            let count = isDone ? board.archive.count : column.tasks.count
            Text("\(count)")
                .foregroundStyle(.secondary)
                .accessibilityLabel(isDone ? "\(count) done" : count == 1 ? "1 task" : "\(count) tasks")
            Spacer()
            if !isDone {
                Button { addingCard = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add task to \(column.name)")
                    .help("Add Task")
            }
            Menu {
                Button("Rename…") { renaming = true }
                if !isDone {
                    Button("Move Left") { model.update { try $0.moveColumn(column.name, to: index - 1, project: project) } }
                        .disabled(index == 0)
                    Button("Move Right") { model.update { try $0.moveColumn(column.name, to: index + 1, project: project) } }
                        .disabled(index + 1 >= board.columns.count - 1)
                    Button("Delete", role: .destructive) { model.update { try $0.removeColumn(column.name, project: project) } }
                        .disabled(!column.tasks.isEmpty || board.columns.count < 3)
                }
                Divider()
                Button("Add Column…") { addingColumn = true }
            } label: {
                Label("\(column.name) column options", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Column Options")
        }
    }

    private var doneArea: some View { DoneArea() }

    /// Moves a dragged card here, onto card `target` (nil = empty space), taking its priority.
    /// Only cards on this board are taken, so dropped text from other apps is ignored.
    private func drop(_ id: String, onto target: String?, below: Bool) -> Bool {
        guard board.columns.contains(where: { $0.tasks.contains { $0.id == id } }) else { return false }
        return model.drop(id, to: column.name, onto: target, below: below, poofAt: NSEvent.mouseLocation)
    }
}

/// The Done column's drop target.
struct DoneArea: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.largeTitle).accessibilityHidden(true)
            Text("Drop here when done")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
    }
}
