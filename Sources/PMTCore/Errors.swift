import Foundation

public enum PMTError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case usage(String)
    case badConfig(String)
    case noSuchProject(String)
    case duplicateName(String)
    case emptyName
    case ambiguousName(String)
    case noBoard
    case boardExists
    case boardHasTasks
    case tooFewColumns
    case noSuchColumn(String)
    case duplicateColumn(String)
    case doneColumn
    case columnNotEmpty(String)
    case noSuchTask(String)
    case emptyTitle
    case noSuchBoard(String)
    case taskDone(String)
    case badDue(String)
    case badPriority(String)

    public var description: String {
        switch self {
        case .usage(let text): text
        case .badConfig(let detail): "Cannot read \(detail.hasSuffix(".") ? detail : detail + ".") Fix the file; it was not changed."
        case .noSuchProject(let name): "No project named '\(name)'."
        case .duplicateName(let name): "A project named '\(name)' already exists."
        case .emptyName: "Project name cannot be empty."
        case .ambiguousName(let name): "More than one project is named '\(name)'. Rename one: pmt project rename \(name) <new> (OpenPMTools) or ff rename \(name) <new> (FrequentFinder)."
        case .noBoard: "That project has no board."
        case .boardExists: "That project already has a board."
        case .boardHasTasks: "The board still has tasks; move or remove them first."
        case .tooFewColumns: "A board needs at least two columns."
        case .noSuchColumn(let name): "No column named '\(name)'."
        case .duplicateColumn(let name): "A column named '\(name)' already exists."
        case .doneColumn: "The last column is Done: it must stay last, cannot be removed, and holds no tasks."
        case .columnNotEmpty(let name): "Column '\(name)' still has tasks."
        case .noSuchTask(let id): "No task '\(id)'."
        case .emptyTitle: "Task title cannot be empty."
        case .noSuchBoard(let name): "No board for '\(name)'."
        case .taskDone(let id): "Task \(id) is done already. To change it, restore it first: pmt task restore \(id)"
        case .badDue(let text): "Due date must look like 2026-11-14 (got '\(text)')."
        case .badPriority(let text): "Priority must be low, medium, high or none (got '\(text)')."
        }
    }

    public var errorDescription: String? { description }
}
