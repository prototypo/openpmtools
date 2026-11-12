import AppKit
import PMTCore
import SwiftUI

/// One card: click to edit; drag to move; context menu to move, edit or delete.
struct CardView: View {
    @Environment(AppModel.self) private var model
    let card: Card
    let column: String
    let columns: [String]
    let flashing: Bool
    /// Moves this card to a column; the point is the card's centre on screen, for the poof.
    let move: (String, NSPoint) -> Void
    /// A dragged card id dropped on this card; true when it landed on the lower half.
    let drop: (String, Bool) -> Bool
    /// On the Big Board: the card's project name and colour.
    var tag: (name: String, color: Color)? = nil
    @State private var editing = false
    @State private var deleting = false
    @State private var targeted = false
    @State private var frame = CGRect.zero

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let tag {
                Text(tag.name).font(.caption.weight(.semibold)).foregroundStyle(tag.color).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let p = priority { PriorityIcon(priority: p, raised: card.isRaised(today: model.today)) }
                Text(card.title).font(.headline)
            }
            if let due = card.due { DueLabel(due: due, today: model.today, done: false) }
            if let notes = card.notes {
                Text(notes).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .padding(.leading, tag == nil ? 0 : 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            if let tag { UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6).fill(tag.color).frame(width: 5) }
        }
        .overlay(alignment: .top) {
            if let u = card.urgency(today: model.today) {
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(u.color).frame(height: 4)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .opacity(flashing || targeted ? 1 : 0))
        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { editing = true }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onDrag {
            model.dragging = card.id
            return NSItemProvider(object: card.id as NSString)
        }
        .dropDestination(for: String.self) { ids, location in
            guard let id = ids.first else { return false }
            return drop(id, location.y > frame.height / 2)
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(card.notes ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { editing = true }
        .contextMenu {
            Menu("Move To") {
                ForEach(columns, id: \.self) { name in
                    Button(name) { move(name, screenCenter()) }.disabled(name == column)
                }
            }
            Button("Edit…") { editing = true }
            Divider()
            Button("Delete…", role: .destructive) { deleting = true }
        }
        .sheet(isPresented: $editing) {
            CardEditor(heading: "Edit Task", button: "Save",
                       draft: CardDraft(title: card.title, notes: card.notes ?? "", due: card.due, priority: card.priority, column: column),
                       columns: columns) { d in
                model.update {
                    try $0.editCard(card.id, title: d.title, notes: d.notes)
                    try $0.setDue(card.id, d.due)
                    try $0.setPriority(card.id, d.priority)
                    if let to = d.column, to != column { try $0.moveCard(card.id, to: to) }
                }
            }
        }
        .confirmationDialog("Delete “\(card.title)”?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { model.update { try $0.deleteCard(card.id) } }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var priority: Priority? { card.effectivePriority(today: model.today) }

    /// Title, project, priority, due words, column.
    private var accessibilityText: String {
        var parts = [card.title]
        if let tag { parts.append(tag.name) }
        if let priority { parts.append("\(priority.label) priority") }
        if let due = card.due { parts.append(dueSpoken(due, today: model.today)) }
        return parts.joined(separator: ", ") + ", in \(column)"
    }

    /// The card's centre in screen coordinates. SwiftUI's global space is the window's content view.
    private func screenCenter() -> NSPoint {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let content = window.contentView else {
            return NSEvent.mouseLocation
        }
        let y = content.isFlipped ? frame.midY : content.bounds.height - frame.midY
        return window.convertPoint(toScreen: content.convert(NSPoint(x: frame.midX, y: y), to: nil))
    }
}

/// What the task editor fills in. `project` is used only when the editor shows a Project menu.
struct CardDraft {
    var title = ""
    var notes = ""
    var due: Day?
    var priority: Priority?
    var project: UUID?
    var column: String?
}

/// Title, notes, due date and priority for a new or existing card; a Project menu when `projects` is given.
/// `save` returns false on failure; the error then shows here.
struct CardEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let heading: String
    let button: String
    @State var draft: CardDraft
    var projects: [ProjectEntry]? = nil
    var columns: [String]? = nil
    let save: (CardDraft) -> Bool
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.headline)
            if let projects {
                Picker("Project", selection: $draft.project) {
                    ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            TextField("Title", text: $draft.title)
            Text("Notes").foregroundStyle(.secondary)
            TextEditor(text: $draft.notes)
                .font(.body)
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                .accessibilityLabel("Notes")
            HStack {
                Toggle("Due date", isOn: Binding(get: { draft.due != nil },
                                                 set: { draft.due = $0 ? (draft.due ?? model.today) : nil }))
                if let due = draft.due {
                    DatePicker("Due date", selection: Binding(get: { due.localDate },
                                                              set: { draft.due = Day.today(now: $0) }),
                               displayedComponents: .date)
                        .labelsHidden()
                }
            }
            Picker("Priority", selection: $draft.priority) {
                Text("None").tag(Priority?.none)
                ForEach(Priority.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            if let columns {
                Picker("Move to", selection: $draft.column) {
                    ForEach(columns, id: \.self) { Text($0).tag(Optional($0)) }
                }
            }
            if let failure {
                Text(failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(button) {
                    if save(draft) {
                        dismiss()
                    } else {
                        failure = model.loadError ?? model.error
                        model.error = nil  // shown here, not also in the sidebar
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || (projects != nil && draft.project == nil))
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// File > New Task… (⌘N) runs this. A window offers it only when it has somewhere to put the task.
struct NewTaskAction { let run: () -> Void }

extension FocusedValues {
    @Entry var newTask: NewTaskAction?
}

/// File menu: New Task… (⌘N) for the focused window, New Project… (⇧⌘N).
struct NewItemCommands: Commands {
    let model: AppModel
    @FocusedValue(\.newTask) private var newTask

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task…") { newTask?.run() }
                .keyboardShortcut("n")
                .disabled(newTask == nil || model.loadError != nil)
            Button("New Project…") { model.addingProject = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.loadError != nil)
        }
    }
}

extension Urgency {
    var color: Color {
        switch self {
        case .later: .green
        case .soon: .yellow
        case .now: .red
        }
    }
}

/// The due date as a pill: a symbol and words, so colour is never the only signal (HIG).
/// The fill is pale so the dark text stays readable on yellow. Done cards: plain date, no colour.
struct DueLabel: View {
    let due: Day
    let today: Day
    let done: Bool

    var body: some View {
        let probe = Card(id: "", title: "", created: .distantPast, due: due)
        let urgency = done ? nil : probe.urgency(today: today)
        let symbol: String? = switch urgency {
        case .now: probe.isOverdue(today: today) ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark"
        case .soon: "clock"
        case .later: "calendar"
        case nil: nil
        }
        // A done card gets the plain date: with "today" long ago, dueText has no relative words.
        let words = done ? dueText(due, today: Day("1900-01-01")!) : dueText(due, today: today)
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            Text(words)
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background((urgency?.color ?? .secondary).opacity(urgency == nil ? 0.12 : 0.25), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dueSpoken(due, today: done ? nil : today))
    }
}

/// Low ↓, Medium !, High !! before the title. The tooltip says when the due date raised it.
struct PriorityIcon: View {
    let priority: Priority
    let raised: Bool

    var body: some View {
        Text(priority.symbol)
            .font(.headline)
            .foregroundStyle(priority == .low ? Color.secondary : Color.primary)
            .help(raised ? "Raised: due soon" : "\(priority.label) priority")
            .accessibilityLabel("\(priority.label) priority")
    }
}
