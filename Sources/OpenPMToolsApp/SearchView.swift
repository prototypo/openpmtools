import PMTCore
import SwiftUI

/// Search results across all boards. Open cards go to their board; done cards show read-only with Restore.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var showing: ArchivedCard?
    @State private var showingProject: UUID?

    var body: some View {
        let results = model.file.search(model.search, includeDone: model.includeDone)
        if results.isEmpty {
            ContentUnavailableView.search(text: model.search)
        } else {
            List(results, id: \.card.id) { r in
                let project = model.catalog.entry(for: r.project)?.name ?? "(orphaned board)"
                let place = r.column ?? "Done"
                Button {
                    if r.column != nil {
                        model.show(r.card.id, in: r.project)
                    } else {
                        showingProject = r.project
                        showing = model.file.board(for: r.project)?.archive.first { $0.id == r.card.id }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.card.title).font(.headline)
                        Text("\(project) · \(place)").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.card.title), \(project), \(place)")
            }
            .sheet(isPresented: Binding(get: { showing != nil }, set: { if !$0 { showing = nil } })) {
                if let card = showing, let project = showingProject {
                    DoneCardView(card: card) {
                        showing = nil
                        if model.update({ try $0.restoreCard(card.id) }) { model.show(card.id, in: project) }
                    }
                }
            }
        }
    }
}

/// A done card, read-only, with Restore.
private struct DoneCardView: View {
    @Environment(\.dismiss) private var dismiss
    let card: ArchivedCard
    let restore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.title).font(.headline).textSelection(.enabled)
            if let notes = card.notes {
                Text(notes).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Text("Done \(card.done.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
            Text("From \(card.fromColumn)").foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Close", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Restore", action: restore).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
