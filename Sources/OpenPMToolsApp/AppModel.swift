import AppKit
import FFCore
import Foundation
import Observation
import PMTCore

/// Pattern copied from FrequentFinder's Sources/FFApp/AppModel.swift.
@MainActor @Observable
final class AppModel {
    let store = BoardsStore()
    private(set) var file = BoardsFile()
    private(set) var ff = FFCore.Config()
    private(set) var catalog = Catalog(ff: FFCore.Config(), file: BoardsFile())
    /// Set when boards.json cannot be read. Edits are blocked so the file is never overwritten.
    private(set) var loadError: String?
    /// Set when FrequentFinder's projects.json cannot be read. Its section is then empty.
    private(set) var ffError: String?
    /// The last failed action, shown in the UI.
    var error: String?
    /// Git status by path. Missing = not a git repo, or not checked yet.
    private(set) var git: [String: GitStatus] = [:]
    /// The selected sidebar project. The view keeps it in @AppStorage across launches.
    var selection: UUID?
    /// Set by File > New Project…; the sidebar shows its name sheet.
    var addingProject = false
    /// The toolbar search text. While not empty, the detail area shows the results.
    var search = ""
    /// Set by Edit > Find > Find…; the window then focuses the search field.
    var focusSearch = false
    var includeDone = false
    /// A board shown from search whose project has no sidebar row (inactive or orphaned).
    var offSidebar: UUID?
    /// A card for the shown board to scroll to and flash.
    var highlight: (project: UUID, card: String)?
    /// The card being dragged, so the Big Board can grey out columns it cannot go to.
    /// SwiftUI reports no drag end, so this clears itself once the mouse button is up.
    // ponytail: polls the mouse button 5 times a second until it is up; use an NSDraggingSource if that ever misses.
    var dragging: String? {
        didSet {
            guard dragging != nil, oldValue == nil else { return }
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard NSEvent.pressedMouseButtons == 0 else { return }
                    self?.dragging = nil
                    timer.invalidate()
                }
            }
        }
    }
    @ObservationIgnored private var watchers: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var timer: Timer?

    /// Git status refreshes on load, every minute, and whenever one of our windows comes to the front.
    init() {
        reload()
        for dir in Set([store.url.deletingLastPathComponent(), ConfigStore.defaultURL.deletingLastPathComponent()]) {
            watch(dir)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAllGit() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAllGit() }
        }
    }

    func reload() {
        (ff, ffError) = Catalog.loadFrequentFinder()
        do {
            file = try store.load()
            loadError = nil
        } catch {
            loadError = "\(error)"
        }
        catalog = Catalog(ff: ff, file: file)
        refreshAllGit()
    }

    /// The project folder and all its repos summed up. Nil for own projects.
    func combinedGit(_ entry: ProjectEntry) -> GitStatus? {
        guard let p = entry.ff else { return nil }
        return GitStatus.combine([p.path.flatMap { git[$0] }] + p.repos.map { git[p.fullPath(of: $0)] })
    }

    /// Applies a change to the latest file contents, saves it, and only then shows it.
    /// Does nothing while boards.json is broken. Returns true on success.
    // ponytail: no undo (⌘Z). Restoring an old copy of the whole file would overwrite pmt's edits made since;
    // Restore in search brings back a done card. Add per-op inverse actions on UndoManager if undo is wanted.
    @discardableResult
    func update(_ change: (inout BoardsFile) throws -> Void) -> Bool {
        guard loadError == nil else { return false }
        do {
            file = try store.update(ff: ff, change)
            catalog = Catalog(ff: ff, file: file)
            error = nil
            return true
        } catch PMTError.badConfig(let detail) {
            loadError = "\(PMTError.badConfig(detail))"
        } catch {
            self.error = "\(error)"
        }
        return false
    }

    /// Shows a card's board with the card highlighted, selecting its sidebar row if it has one.
    func show(_ card: String, in project: UUID) {
        search = ""
        highlight = (project, card)
        if let entry = catalog.entry(for: project), entry.isActive {
            offSidebar = nil
            selection = project
        } else {
            selection = nil
            offSidebar = project
        }
    }

    func refreshAllGit() {
        let paths = catalog.ffProjects.compactMap(\.ff).flatMap { p in [p.path].compactMap { $0 } + p.repos.map(p.fullPath(of:)) }
        Task.detached {
            let results = paths.map { ($0, Git.status(at: $0)) }
            await MainActor.run {
                for (path, status) in results { self.git[path] = status }
            }
        }
    }

    /// Watches a config folder so the display follows atomic saves (ours, pmt's and FrequentFinder's).
    // ponytail: misses editors that write a file in place; harmless, since update() re-reads before saving.
    private func watch(_ dir: URL) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            self.error = "Cannot watch \(dir.path) for changes: \(error)"
            return
        }
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else {
            error = "Cannot watch \(dir.path) for changes: \(String(cString: strerror(errno)))"
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watchers.append(source)
    }
}
