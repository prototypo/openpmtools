import AppKit
import PMTCore
import SwiftUI

/// Every open task from every board, in one set of columns merged by name.
/// A card can only go to a column its own board has.
struct BigBoardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let message = model.loadError {
            ContentUnavailableView("Cannot read boards.json", systemImage: "exclamationmark.triangle", description: Text(message))
        } else if model.file.boards.isEmpty {
            ContentUnavailableView("No boards yet", systemImage: "rectangle.split.3x1")
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(model.file.bigBoard(), id: \.name) { BigColumnView(column: $0) }
                }
                .padding(12)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .safeAreaInset(edge: .bottom) {
                if let message = model.error {
                    Text(message).foregroundStyle(.red).padding(8)
                }
            }
        }
    }
}

private struct BigColumnView: View {
    @Environment(AppModel.self) private var model
    let column: BigColumn
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.name).font(.headline)
                let count = column.cards.count + column.archived
                Text("\(count)").foregroundStyle(.secondary)
                    .accessibilityLabel(count == 1 ? "1 task" : "\(count) tasks")
            }
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(Array(column.cards.enumerated()), id: \.element.card.id) { i, loc in
                        let board = model.file.board(for: loc.project)
                        CardView(card: loc.card, column: column.name, columns: board?.columns.map(\.name) ?? [],
                                 flashing: false, move: { model.move(loc.card.id, to: $0, at: nil, poofAt: $1) },
                                 drop: { id, below in drop(id, onto: i, below: below) },
                                 tag: (projectName(loc.project), projectColor(loc.project)))
                    }
                    if column.isDone && column.cards.isEmpty { DoneArea().frame(minHeight: 160) }
                }
                .padding(2)
            }
            .frame(maxHeight: .infinity, alignment: .top)
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
    }

    private func projectName(_ id: UUID) -> String { model.catalog.entry(for: id)?.name ?? "(orphaned board)" }

    /// A colour per board, in board order, so each project keeps its colour while boards are only added.
    // ponytail: 12 colours; more boards than that repeat. Add a user-picked colour per project if that matters.
    private func projectColor(_ id: UUID) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .indigo, .brown, .mint, .cyan, .yellow]
        return palette[(model.file.boards.firstIndex { $0.project == id } ?? 0) % palette.count]
    }

    /// Moves a dragged card into this column on its own board. Dropped on a card of the same board,
    /// it lands before or after that card; otherwise at the end. Fails if its board has no such column.
    private func drop(_ id: String, onto target: Int?, below: Bool) -> Bool {
        guard let board = model.file.boards.first(where: { $0.columns.contains { $0.tasks.contains { $0.id == id } } }),
              let col = board.columns.first(where: { $0.name.caseInsensitiveCompare(column.name) == .orderedSame })
        else { return false }
        var at: Int?
        if let t = target, column.cards[t].project == board.project,
           let i = col.tasks.firstIndex(where: { $0.id == column.cards[t].card.id }) {
            var t = below ? i + 1 : i
            // moveCard takes the card out first, so a card from higher up in this column shifts the target.
            if let from = col.tasks.firstIndex(where: { $0.id == id }) {
                if from == t { return true }
                if from < t { t -= 1 }
            }
            at = t
        }
        model.move(id, to: col.name, at: at, poofAt: NSEvent.mouseLocation)
        return true
    }
}
