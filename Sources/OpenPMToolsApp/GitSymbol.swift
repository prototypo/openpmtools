import FFCore
import SwiftUI

// Copied from FrequentFinder's Sources/FFApp/MenuContent.swift (GitSymbol), which is private app code there.
/// Git state as a symbol plus words, so it never relies on colour alone.
enum GitSymbol {
    static func name(for status: GitStatus?) -> String {
        guard let status else { return "circle.dashed" }
        return status.isDirty ? "pencil.circle" : "checkmark.circle"
    }

    static func color(for status: GitStatus?) -> Color {
        guard let status else { return .secondary }
        return status.isDirty ? .orange : .green
    }

    /// "clean", "3 changed, 2 to push, 1 to pull", ...
    static func description(for status: GitStatus?) -> String {
        guard let status else { return "not a git repository" }
        var parts = [status.isDirty ? "\(status.changes) changed" : "clean"]
        if status.ahead > 0 { parts.append("\(status.ahead) to push") }
        if status.behind > 0 { parts.append("\(status.behind) to pull") }
        return parts.joined(separator: ", ")
    }
}
