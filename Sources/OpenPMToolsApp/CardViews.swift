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
            Text(card.title).font(.headline)
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
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .opacity(flashing || targeted ? 1 : 0))
        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { editing = true }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .draggable(card.id)
        .dropDestination(for: String.self) { ids, location in
            guard let id = ids.first else { return false }
            return drop(id, location.y > frame.height / 2)
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tag.map { "\(card.title), \($0.name), in \(column)" } ?? "\(card.title), in \(column)")
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
            CardEditor(heading: "Edit Task", button: "Save", title: card.title, notes: card.notes ?? "") { title, notes in
                model.update { try $0.editCard(card.id, title: title, notes: notes) }
            }
        }
        .confirmationDialog("Delete “\(card.title)”?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { model.update { try $0.deleteCard(card.id) } }
        } message: {
            Text("This cannot be undone.")
        }
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

/// Title and notes for a new or existing card. `save` returns false on failure; the error then shows here.
struct CardEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let heading: String
    let button: String
    @State var title: String
    @State var notes: String
    let save: (String, String) -> Bool
    @State var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.headline)
            TextField("Title", text: $title)
            Text("Notes").foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .font(.body)
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                .accessibilityLabel("Notes")
            if let failure {
                Text(failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(button) {
                    if save(title, notes) {
                        dismiss()
                    } else {
                        failure = model.loadError ?? model.error
                        model.error = nil  // shown here, not also in the sidebar
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
