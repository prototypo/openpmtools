# OpenPMTools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS Kanban app (OpenPMTools) and CLI (`pmt`) whose projects come from FrequentFinder or are its own, with boards linked to projects by UUID.

**Architecture:** Two repos. FrequentFinder first gets project UUIDs, a public `FFCore` library product, a shared drag type, and a drop target (Tasks 1–2, merged by David before Task 3). OpenPMTools is a SwiftPM package that depends on `FFCore` by local path: `PMTCore` (model, store, catalog, search, CLI) is unit-tested; `pmt` and the SwiftUI app are thin layers over it.

**Tech Stack:** Swift 6 toolchain (language mode 5, like FrequentFinder), SwiftUI, AppKit (`NSAnimationEffect`), Swift Testing, SwiftPM, macOS 15+.

**Spec:** `docs/superpowers/specs/2026-11-03-openpmtools-design.md` (read it first; this plan does not repeat its UI rules).

## Global Constraints

- macOS 15 or later (`platforms: [.macOS(.v15)]`), `swift-tools-version: 6.0`, `swiftLanguageModes: [.v5]`. No Xcode project. No third-party packages.
- App name **OpenPMTools**, bundle id `org.hyland-wood.OpenPMTools`. CLI name **`pmt`**, installed to `~/.local/bin/pmt`.
- OpenPMTools data: `$PMT_CONFIG` if set, else `~/.config/openpmtools/boards.json`. FrequentFinder data: FFCore's `ConfigStore.defaultURL` (`$FF_CONFIG` or `~/.config/frequent-finder/projects.json`).
- JSON written pretty-printed, sorted keys, without escaping slashes, ISO 8601 dates, atomic writes.
- OpenPMTools writes `projects.json` only through `FFCore.ConfigStore` (the one-time id migration in `load()`, and FrequentFinder's own drop handler). It never stores a FrequentFinder project's name.
- The last column of a board is Done. It never holds cards; a card moved there is archived.
- A board links to a project by UUID. People type and see names; names resolve case-insensitively after trimming whitespace, and are unique across FrequentFinder and own projects.
- Drag type identifier: `org.hyland-wood.openpmtools.project`, payload JSON `{"id": "<UUID>", "name": "<name>"}`.
- Tests never touch the real config files: use temp files.
- Commits end with the session's attribution lines.

## Review Focus

1. **An old FrequentFinder build saves `projects.json` and drops the `id` fields** (before David reinstalls). FrequentFinder then makes new ids, and boards lose their project. Expected: no board or card is lost. The boards show as orphaned in `pmt board list`, their cards are still found by search, and `pmt board attach` reconnects them. Pinned by `orphanBoardsAreListedAndSearchable` (Task 5) and `cliBoardAttach` (Task 6).
2. **`pmt` changes `boards.json` while the app is open.** Expected: the app's next edit does not overwrite the CLI's change, because `update` re-reads first. Pinned by `updateKeepsOutsideChanges` (Task 3).
3. **`projects.json` is broken or missing.** Expected: OpenPMTools still works with own projects. It shows the error only in the FrequentFinder section and never writes that file. Pinned by `brokenFrequentFinderFileGivesEmptyCatalog` (Task 5).
4. **A card is dragged or moved after `pmt` deleted it, or is dropped where it already is.** Expected: there is no crash and no duplicate card. The app shows "No task with id …", or does nothing. Pinned by `moveUnknownCardThrows` and `moveToSamePlaceIsNoChange` (Task 4).
5. **Names that differ only by case or spaces** (" Breakthrough " vs "breakthrough"), for projects and columns. Expected: they are treated as the same name and refused as duplicates. Pinned by `ownProjectNamesAreUniqueAcrossBothApps` (Task 5) and `createBoardValidatesColumns` (Task 4).

---

## File Structure

**FrequentFinder** (`/Users/davidhyland-wood/Documents/GitHub/frequent-finder`, branch `openpmtools-support` from `main`)
- Modify `Sources/FFCore/Config.swift`: `Project.id`, decode default, migration in `ConfigStore.load()`.
- Modify `Sources/FFCore/Commands.swift`: `add(... id:)`, `addDropped(id:name:)`, `index(of id: UUID)`.
- Modify `Sources/FFCore/CLI.swift`: `ff add --id <UUID>`.
- Create `Sources/FFCore/ProjectDrag.swift`: the shared drag payload and its `Transferable` conformance.
- Modify `Package.swift`: `.library(name: "FFCore", targets: ["FFCore"])`.
- Modify `Sources/FFApp/AllProjectsView.swift`: drop target on the sidebar list.
- Modify `scripts/make-app.sh`: `UTImportedTypeDeclarations` in Info.plist.
- Modify tests: `Tests/FFCoreTests/ConfigTests.swift`, `CommandTests.swift`, `CLITests.swift`.
- Modify `README.md`: `--id`, drag-from-OpenPMTools.

**OpenPMTools** (`/Users/davidhyland-wood/Documents/GitHub/openpmtools`, branch `build-openpmtools` from `main`)
- `Package.swift`
- `Sources/PMTCore/Model.swift`: `OwnProject`, `Card`, `ArchivedCard`, `Column`, `Board`, `BoardsFile`.
- `Sources/PMTCore/Store.swift`: `BoardsStore`.
- `Sources/PMTCore/Errors.swift`: `PMTError`.
- `Sources/PMTCore/BoardOps.swift`: board, column and card edits on `BoardsFile`.
- `Sources/PMTCore/Catalog.swift`: merged project list, own-project edits, orphans, search.
- `Sources/PMTCore/CLI.swift`: `PMTCLI.run`.
- `Sources/pmt/main.swift`
- `Sources/OpenPMToolsApp/`: `OpenPMToolsApp.swift`, `AppModel.swift`, `Sidebar.swift`, `GitSymbol.swift`, `BoardSetupView.swift`, `BoardView.swift`, `CardViews.swift`, `SearchView.swift`.
- `Tests/PMTCoreTests/`: `Helpers.swift`, `StoreTests.swift`, `BoardOpsTests.swift`, `CatalogTests.swift`, `CLITests.swift`.
- `scripts/make-app.sh`, `scripts/make-icon.swift`, `Resources/AppIcon.icns`, `README.md`.

---

### Task 1: FrequentFinder project UUIDs

**Files:**
- Modify: `frequent-finder/Sources/FFCore/Config.swift`, `Sources/FFCore/Commands.swift`, `Sources/FFCore/CLI.swift`, `README.md`
- Test: `frequent-finder/Tests/FFCoreTests/ConfigTests.swift`, `CommandTests.swift`, `CLITests.swift`

**Interfaces:**
- Produces: `Project.id: UUID` (Codable key `id`); `Project.init(id: UUID = UUID(), name:path:keyFiles:urls:repos:active:notes:)`; `Config.index(of id: UUID) -> Int?`; `Config.add(path:name:id: UUID? = nil, cwd:)`. `ConfigStore.load()` saves the file once when any project had no `id`.

- [ ] **Step 1: Create the branch.** `cd /Users/davidhyland-wood/Documents/GitHub/frequent-finder && git switch -c openpmtools-support main`

- [ ] **Step 2: Write the failing tests** (ConfigTests.swift)

```swift
@Test func missingIDsAreAddedAndSavedOnce() throws {
    let store = try tempStore()
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"projects":[{"name":"A","path":"/a"},{"name":"B"}],"terminal":"iterm"}"#.utf8).write(to: store.url)
    let first = try store.load()
    let second = try store.load()
    #expect(first == second)                                   // ids stable after the one-time save
    #expect(Set(first.projects.map(\.id)).count == 2)
    #expect(first.terminal == .iterm && first.projects.map(\.name) == ["A", "B"] && first.projects[0].path == "/a")
}

@Test func loadWithAllIDsDoesNotWrite() throws {
    let store = try tempStore()
    try store.save(Config(projects: [Project(name: "A", path: "/a")]))
    let before = try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as! Date
    Thread.sleep(forTimeInterval: 1.1)
    _ = try store.load()
    let after = try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as! Date
    #expect(before == after)
}
```

CommandTests.swift:

```swift
@Test func addWithKnownID() throws {
    var c = Config()
    let id = UUID()
    try c.add(path: nil, name: "Book", id: id, cwd: "/")
    #expect(c.projects[0].id == id)
    #expect(c.index(of: id) == 0)
    #expect(throws: FFError.duplicateID(id.uuidString)) { try c.add(path: nil, name: "Other", id: id, cwd: "/") }
}
```

CLITests.swift: `ff add --name Book --id 6F9619FF-8B86-D011-B42D-00CF4FC964FF` then `ff list --json` output contains `"id" : "6F9619FF-8B86-D011-B42D-00CF4FC964FF"`; `ff add --name X --id nope` throws `FFError.usage`.

- [ ] **Step 3: Run tests to verify they fail.** Run: `swift test` — Expected: compile errors (`id`, `duplicateID` unknown).

- [ ] **Step 4: Implement.**
  - `Project`: add `public let id: UUID` first in the struct and as the first `init` parameter (default `UUID()`); decoder uses `decodeIfPresent(UUID.self, forKey: .id) ?? UUID()`.
  - `ConfigStore.load()`: after decoding, if the raw JSON had any project with no `id` (decode a private probe struct `{ projects: [{ id: UUID? }]? }` from the same data), call `save(config)` before returning. A failed save throws (do not swallow).
  - `FFError.duplicateID(String)`: "A project with id '\(id)' already exists."
  - `Config.index(of id: UUID) -> Int?`; `add(path:name:id:cwd:)` throws `duplicateID` when the id is taken.
  - CLI: `--id` option on `add`; a value that is not a UUID throws `FFError.usage(usage)`. Add `[--id UUID]` to the `add` lines of `usage`.
  - Existing tests that compare whole `Project`/`Config` values after `load()` or `add` (`ConfigTests.missingKeysGetDefaults`, `CommandTests` line 27) now fail on random ids. Fix them by building the expected value with the loaded project's `id`, not by excluding `id` from `==`.

- [ ] **Step 5: Run tests.** Run: `swift test` — Expected: all pass.

- [ ] **Step 6: Update README** (`ff add ... [--id UUID]` in the command list; one line: "Each project has a fixed `id`, added automatically, so other tools can refer to it after a rename.").

- [ ] **Step 7: Commit.** `git commit -am "Give every project a stable UUID"`

---

### Task 2: FrequentFinder library product, drag type, and drop target

**Files:**
- Create: `frequent-finder/Sources/FFCore/ProjectDrag.swift`
- Modify: `Package.swift`, `Sources/FFCore/Commands.swift`, `Sources/FFApp/AllProjectsView.swift`, `scripts/make-app.sh`, `README.md`
- Test: `Tests/FFCoreTests/CommandTests.swift`

**Interfaces:**
- Consumes: Task 1's `Project.id`, `Config.index(of: UUID)`.
- Produces (public in FFCore): `struct ProjectDrag: Codable, Hashable, Sendable, Transferable { id: UUID; name: String }`; `extension UTType { static let openPMToolsProject = UTType(exportedAs: "org.hyland-wood.openpmtools.project", conformingTo: .json) }`; `Config.addDropped(_ drag: ProjectDrag) throws -> Bool` (true = added). Library product `FFCore`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func addDroppedProject() throws {
    var c = Config(projects: [Project(name: "Existing", path: nil)])
    let drag = ProjectDrag(id: UUID(), name: "Breakthrough")
    #expect(try c.addDropped(drag) == true)
    #expect(c.projects.last?.id == drag.id && c.projects.last?.name == "Breakthrough" && c.projects.last?.path == nil)
    #expect(try c.addDropped(drag) == false)                                  // same id again: no change
    #expect(c.projects.count == 2)
    #expect(throws: FFError.duplicateName("existing")) { try c.addDropped(ProjectDrag(id: UUID(), name: "existing")) }
}

@Test func projectDragJSON() throws {
    let drag = ProjectDrag(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")!, name: "B")
    let back = try JSONDecoder().decode(ProjectDrag.self, from: JSONEncoder().encode(drag))
    #expect(back == drag)
}
```

- [ ] **Step 2: Run to verify failure.** `swift test` — Expected: `ProjectDrag` not found.

- [ ] **Step 3: Implement.**
  - `ProjectDrag.swift`: `import CoreTransferable`, `import UniformTypeIdentifiers`; `transferRepresentation` is `CodableRepresentation(contentType: .openPMToolsProject)` plus `ProxyRepresentation(exporting: \.name)` so it drops as plain text elsewhere.
  - `addDropped`: same id present → `false`; else `add(path: nil, name: drag.name, id: drag.id, cwd: "/")` and `true`.
  - `Package.swift`: add `products: [.library(name: "FFCore", targets: ["FFCore"]), .executable(name: "ff", targets: ["ff"]), .executable(name: "FrequentFinder", targets: ["FrequentFinder"])]`.
  - `AllProjectsView`: on the sidebar `List`, `.dropDestination(for: ProjectDrag.self) { drags, _ in model.update { c in for d in drags { _ = try c.addDropped(d) } }; return true }`. A thrown `duplicateName` shows through `model.error` the way other failed edits do (check how `ProjectWindow`/`SettingsView` show `model.error` and show it in this window the same way).
  - `make-app.sh` Info.plist: add `UTImportedTypeDeclarations` with one dict: `UTTypeIdentifier` = `org.hyland-wood.openpmtools.project`, `UTTypeConformsTo` = [`public.json`], `UTTypeDescription` = `OpenPMTools Project`.

- [ ] **Step 4: Run tests.** `swift test` — Expected: all pass. `scripts/make-app.sh` — Expected: builds with no errors.

- [ ] **Step 5: README.** One line under "How to use the GUI": dragging a project from OpenPMTools onto the All Projects sidebar adds it.

- [ ] **Step 6: Commit, push, open PR.** `git commit -am "Share FFCore and accept projects dragged from OpenPMTools"`, `git push -u origin openpmtools-support`, `gh pr create` (body says it adds project ids, the FFCore library, and the drop target, for OpenPMTools).

- [ ] **Step 7: STOP for David.** He merges the PR. Then: `git switch main && git pull && scripts/make-app.sh --install`. Do not start Task 3 until `main` in `../frequent-finder` has `.library(name: "FFCore"`.

---

### Task 3: OpenPMTools package, model, and store

**Files:**
- Create: `openpmtools/Package.swift`, `Sources/PMTCore/Model.swift`, `Sources/PMTCore/Store.swift`, `Sources/PMTCore/Errors.swift`, `Tests/PMTCoreTests/Helpers.swift`, `Tests/PMTCoreTests/StoreTests.swift`

**Interfaces:**
- Produces:
  - `Package.swift`: dependency `.package(path: "../frequent-finder")`; targets `PMTCore` (depends on `.product(name: "FFCore", package: "frequent-finder")`), executable `pmt` (PMTCore), executable `OpenPMTools` at `Sources/OpenPMToolsApp` (PMTCore, FFCore), test `PMTCoreTests`.
  - `struct OwnProject: Codable, Hashable, Sendable { id: UUID; name: String }`
  - `struct Card: Codable, Hashable, Sendable { id: String; title: String; notes: String?; created: Date }`
  - `struct ArchivedCard: Codable, Hashable, Sendable { id, title, notes, created, done: Date, fromColumn: String }` with `init(_ card: Card, fromColumn: String, done: Date)` and `var card: Card`.
  - `struct Column: Codable, Hashable, Sendable { name: String; tasks: [Card] }`
  - `struct Board: Codable, Hashable, Sendable { project: UUID; columns: [Column]; archive: [ArchivedCard] }`
  - `struct BoardsFile: Codable, Equatable, Sendable { ownProjects: [OwnProject]; boards: [Board] }` (missing keys decode as empty), `func jsonData() throws -> Data`.
  - `struct BoardsStore: Sendable { let url: URL; static var defaultURL: URL; func load() throws -> BoardsFile; func save(_:) throws; func update(ff: FFCore.Config, _ change: (inout BoardsFile) throws -> Void) throws -> BoardsFile }`. `update` re-reads, applies `change`, then calls `pruneOwnProjects(ff:)` (Task 5; until then a no-op stub in Catalog.swift), saves only if changed.
  - `enum PMTError: Error, Equatable, CustomStringConvertible, LocalizedError` with cases: `usage(String)`, `badConfig(String)`, `noSuchProject(String)`, `duplicateName(String)`, `emptyName`, `ambiguousName(String)`, `noBoard`, `boardExists`, `boardHasTasks`, `tooFewColumns`, `noSuchColumn(String)`, `duplicateColumn(String)`, `doneColumn`, `columnNotEmpty(String)`, `noSuchTask(String)`, `emptyTitle`, `noSuchBoard(String)`. Messages follow `FFError`'s style; `badConfig` says "Cannot read \(detail). Fix or delete it; it was not changed." and `doneColumn` says "The last column is Done: it must stay last, cannot be removed, and holds no tasks."
  - `Helpers.swift`: `makeTempDir()` (copy FrequentFinder's), `tempStore() -> BoardsStore`.

- [ ] **Step 0: Create the branch.** `cd /Users/davidhyland-wood/Documents/GitHub/openpmtools && git switch -c build-openpmtools main`

- [ ] **Step 1: Write the failing tests** (StoreTests.swift): `missingFileIsEmpty`, `roundTrip` (a file with one own project, one board with two columns, one card, one archived card, equal after save/load), `brokenFileThrowsBadConfig` (same shape as FrequentFinder's), and:

```swift
@Test func updateKeepsOutsideChanges() throws {
    let store = try tempStore()
    let a = OwnProject(id: UUID(), name: "A"), b = OwnProject(id: UUID(), name: "B")
    try store.save(BoardsFile(ownProjects: [a], boards: []))
    var other = try store.load(); other.ownProjects.append(b); try store.save(other)   // the CLI's edit
    let result = try store.update(ff: Config()) { $0.boards.append(Board(project: a.id, columns: [], archive: [])) }
    #expect(result.ownProjects == [a, b] && result.boards.count == 1)
}

@Test func defaultURLHonoursPMTConfig() { /* setenv("PMT_CONFIG", "~/x/boards.json", 1); #expect(BoardsStore.defaultURL.path == NSHomeDirectory() + "/x/boards.json"); unsetenv */ }
```

- [ ] **Step 2: Run to verify failure.** `swift test` — Expected: compile errors.
- [ ] **Step 3: Implement** the types above. Encoder/decoder use `.iso8601` dates. Write `Sources/pmt/main.swift` and `Sources/OpenPMToolsApp/OpenPMToolsApp.swift` as minimal placeholders so the package builds (Tasks 6 and 7 replace them).
- [ ] **Step 4: Run tests.** `swift test` — Expected: pass.
- [ ] **Step 5: Commit.** `git add -A && git commit -m "Add PMTCore model and boards store"`

---

### Task 4: Board, column, and card operations

**Files:**
- Create: `Sources/PMTCore/BoardOps.swift`, `Tests/PMTCoreTests/BoardOpsTests.swift`

**Interfaces:**
- Consumes: Task 3 types.
- Produces (all `mutating`/methods on `BoardsFile`, all throw `PMTError`):
  - `func board(for project: UUID) -> Board?`
  - `createBoard(project: UUID, columns: [String])` — trims names; refuses empty (`emptyName`), case-insensitive duplicates (`duplicateColumn`), fewer than 2 (`tooFewColumns`), existing board (`boardExists`).
  - `deleteBoard(project: UUID, force: Bool)` — `noBoard`; `boardHasTasks` when any card or archived card and `!force`.
  - `addColumn(_ name: String, project: UUID, at index: Int? = nil)` — 0-based; nil or any index past the working columns inserts just before Done.
  - `renameColumn(_ name: String, to: String, project: UUID)`
  - `moveColumn(_ name: String, to index: Int, project: UUID)` — Done cannot move and nothing can move to or past its place (`doneColumn`).
  - `removeColumn(_ name: String, project: UUID)` — `doneColumn` for the last column; `columnNotEmpty`; `tooFewColumns` if it would leave fewer than 2.
  - `newCardID(using make: () -> UUID = UUID.init) -> String` — lowercase hex of the UUID without dashes, first 6 characters; if that id is used by any card or archived card in any board, take one more character until unique.
  - `addCard(project: UUID, title: String, notes: String? = nil, column: String? = nil, now: Date = Date()) -> String` — returns the id; nil column = first; Done column → `doneColumn`; blank title → `emptyTitle`; blank notes stored as nil.
  - `editCard(_ id: String, title: String? = nil, notes: String? = nil)` — open cards only; `notes: ""` clears.
  - `moveCard(_ id: String, to column: String, at index: Int? = nil, now: Date = Date()) -> Bool` — returns true when archived (moved to the last column). Index nil = bottom. Moving within a column reorders.
  - `deleteCard(_ id: String)` — open or archived.
  - `restoreCard(_ id: String)` — archived → bottom of the first column.
  - `func locate(_ id: String) -> CardLocation?` where `struct CardLocation: Hashable, Sendable { project: UUID; column: String?; card: Card; done: Date? }` (`column == nil` means archived).
  - Card ids match case-insensitively; an unknown id throws `noSuchTask(id)`. Column names match case-insensitively; unknown throws `noSuchColumn(name)`. A project without a board throws `noBoard`.

- [ ] **Step 1: Write the failing tests.** Use `let p = UUID()` and a fixed `let t = Date(timeIntervalSince1970: 1_800_000_000)`.

```swift
@Test func createBoardValidatesColumns() throws {
    var f = BoardsFile()
    #expect(throws: PMTError.tooFewColumns) { try f.createBoard(project: p, columns: ["Done"]) }
    #expect(throws: PMTError.duplicateColumn("to do")) { try f.createBoard(project: p, columns: [" To Do", "to do", "Done"]) }
    #expect(throws: PMTError.emptyName) { try f.createBoard(project: p, columns: ["  ", "Done"]) }
    try f.createBoard(project: p, columns: [" To Do ", "Doing", "Done"])
    #expect(f.board(for: p)?.columns.map(\.name) == ["To Do", "Doing", "Done"])
    #expect(throws: PMTError.boardExists) { try f.createBoard(project: p, columns: ["A", "B"]) }
}

@Test func moveToLastColumnArchives() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["To Do", "Doing", "Done"])
    let id = try f.addCard(project: p, title: "Press kit", notes: "Need photo", now: t)
    #expect(try f.moveCard(id, to: "Doing") == false)
    #expect(try f.moveCard(id.uppercased(), to: "done", now: t) == true)
    let b = f.board(for: p)!
    #expect(b.columns.allSatisfy(\.tasks.isEmpty))
    #expect(b.archive == [ArchivedCard(Card(id: id, title: "Press kit", notes: "Need photo", created: t), fromColumn: "Doing", done: t)])
    try f.restoreCard(id)
    #expect(f.board(for: p)!.columns[0].tasks.map(\.id) == [id] && f.board(for: p)!.archive.isEmpty)
}

@Test func moveUnknownCardThrows() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "Done"])
    #expect(throws: PMTError.noSuchTask("abc123")) { try f.moveCard("abc123", to: "A") }
}

@Test func moveToSamePlaceIsNoChange() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "Done"])
    let x = try f.addCard(project: p, title: "x"), y = try f.addCard(project: p, title: "y")
    let before = f
    _ = try f.moveCard(y, to: "A")              // already at the bottom of A
    #expect(f == before)
    _ = try f.moveCard(y, to: "A", at: 0)
    #expect(f.board(for: p)!.columns[0].tasks.map(\.id) == [y, x])
}

@Test func cardIDsGrowOnClash() throws {
    var f = BoardsFile(); try f.createBoard(project: p, columns: ["A", "Done"])
    let fixed = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
    let first = f.newCardID(using: { fixed })
    #expect(first == "abcdef")
    f.boards[0].columns[0].tasks.append(Card(id: first, title: "x", notes: nil, created: t))
    #expect(f.newCardID(using: { fixed }) == "abcdef1")
}
```

Also: `addCardRules` (Done column → `doneColumn`; blank title → `emptyTitle`; default column is first), `columnRules` (add before Done by default; move/remove Done → `doneColumn`; remove non-empty → `columnNotEmpty`; remove to fewer than 2 → `tooFewColumns`; rename to an existing name → `duplicateColumn`), `deleteBoardNeedsForce`, `deleteArchivedCard`.

- [ ] **Step 2: Run to verify failure.** `swift test --filter BoardOpsTests` — Expected: compile errors.
- [ ] **Step 3: Implement** in `BoardOps.swift`. Keep one private helper that finds `(board, column?, index)` for an id; every card op uses it.
- [ ] **Step 4: Run tests.** `swift test` — Expected: pass.
- [ ] **Step 5: Commit.** `git commit -am "Add board, column and card operations"` (add the new files first).

---

### Task 5: Project catalog, own projects, orphans, and search

**Files:**
- Create: `Sources/PMTCore/Catalog.swift` (replaces Task 3's stub), `Tests/PMTCoreTests/CatalogTests.swift`

**Interfaces:**
- Consumes: FFCore `Config`, `Project`, `ConfigStore`; Task 3–4 types.
- Produces:
  - `struct ProjectEntry: Hashable, Identifiable, Sendable { id: UUID; name: String; ff: FFCore.Project? }` — `ff == nil` means own project. `var isActive: Bool { ff?.active ?? true }`.
  - `struct Catalog: Sendable { init(ff: FFCore.Config, file: BoardsFile) }` with `ffProjects: [ProjectEntry]` (active only, FrequentFinder order), `ownProjects: [ProjectEntry]` (own entries whose id is not in FrequentFinder, file order), `func entry(for id: UUID) -> ProjectEntry?` (any FF project, including inactive, or own), `func resolve(_ name: String) throws -> ProjectEntry` (trimmed, case-insensitive across all FF projects, including inactive, and own; none → `noSuchProject`; one in each list → `ambiguousName`), `orphanBoards: [UUID]` (boards whose project is in neither list).
  - `static func loadFrequentFinder(_ store: ConfigStore = ConfigStore()) -> (config: FFCore.Config, error: String?)` — missing file → empty, no error; broken → empty config and the error text.
  - On `BoardsFile`: `addOwnProject(_ name: String, ff: Config) throws -> UUID` (trimmed; `emptyName`; `duplicateName` if used by any own or FF project); `renameOwnProject(_ id: UUID, to: String, ff: Config)`; `removeOwnProject(_ id: UUID, force: Bool)` (removes its board via `deleteBoard(project:force:)` rules); `pruneOwnProjects(ff: Config)` (drops own entries whose id is in FF); `attachBoard(_ boardProject: UUID, to project: UUID)` (`noSuchBoard` if no such board, `boardExists` if the target already has one); `search(_ text: String, includeDone: Bool) -> [CardLocation]` (trimmed text; empty → `[]`; `localizedCaseInsensitiveContains` on title or notes; open cards in board/column order, then archived cards newest `done` first).

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func catalogMergesAndPrunes() throws {
    let shared = UUID()
    let ff = Config(projects: [Project(id: shared, name: "Breakthrough", path: nil),
                               Project(name: "Old", path: nil, active: false)])
    var f = BoardsFile(ownProjects: [OwnProject(id: shared, name: "Breakthrough"), OwnProject(id: UUID(), name: "Garden")], boards: [])
    let c = Catalog(ff: ff, file: f)
    #expect(c.ffProjects.map(\.name) == ["Breakthrough"])     // inactive hidden
    #expect(c.ownProjects.map(\.name) == ["Garden"])          // the dragged one shows once, under FF
    #expect(try c.resolve(" old ").name == "Old")            // inactive still resolves for pmt
    f.pruneOwnProjects(ff: ff)
    #expect(f.ownProjects.map(\.name) == ["Garden"])
}

@Test func ownProjectNamesAreUniqueAcrossBothApps() throws {
    let ff = Config(projects: [Project(name: "Breakthrough", path: nil)])
    var f = BoardsFile()
    #expect(throws: PMTError.duplicateName("breakthrough ")) { try f.addOwnProject("breakthrough ", ff: ff) }
    _ = try f.addOwnProject(" Garden ", ff: ff)
    #expect(throws: PMTError.duplicateName("GARDEN")) { try f.addOwnProject("GARDEN", ff: ff) }
    #expect(f.ownProjects.map(\.name) == ["Garden"])
}

@Test func orphanBoardsAreListedAndSearchable() throws {
    let gone = UUID()
    var f = BoardsFile(); try f.createBoard(project: gone, columns: ["A", "Done"])
    _ = try f.addCard(project: gone, title: "Launch email")
    #expect(Catalog(ff: Config(), file: f).orphanBoards == [gone])
    #expect(f.search("EMAIL", includeDone: false).map(\.card.title) == ["Launch email"])
    let newID = try f.addOwnProject("Breakthrough", ff: Config())
    try f.attachBoard(gone, to: newID)
    #expect(Catalog(ff: Config(), file: f).orphanBoards.isEmpty)
}

@Test func brokenFrequentFinderFileGivesEmptyCatalog() throws {
    let dir = try makeTempDir()
    let url = URL(fileURLWithPath: dir + "/projects.json")
    try Data("{ broken".utf8).write(to: url)
    let (config, error) = Catalog.loadFrequentFinder(ConfigStore(url: url))
    #expect(config.projects.isEmpty && error != nil)
    #expect(try String(contentsOf: url, encoding: .utf8) == "{ broken")      // never written
    #expect(Catalog.loadFrequentFinder(ConfigStore(url: URL(fileURLWithPath: dir + "/none.json"))).error == nil)
}
```

Also: `searchIncludesDoneOnlyWhenAsked` (an archived card is found only with `includeDone: true`, after open cards), `ambiguousNameThrows` (an own project and an FF project with the same name but different ids → `ambiguousName`; build the file directly, since `addOwnProject` refuses it), `removeOwnProjectNeedsForceWhenBoardHasTasks`.

- [ ] **Step 2: Run to verify failure.** `swift test --filter CatalogTests` — Expected: compile errors.
- [ ] **Step 3: Implement** in `Catalog.swift`.
- [ ] **Step 4: Run tests.** `swift test` — Expected: pass.
- [ ] **Step 5: Commit.** `git commit -m "Add project catalog, own projects, orphans and search"`

---

### Task 6: The `pmt` command

**Files:**
- Create: `Sources/PMTCore/CLI.swift`, `Tests/PMTCoreTests/CLITests.swift`
- Modify: `Sources/pmt/main.swift`

**Interfaces:**
- Consumes: everything in Tasks 3–5.
- Produces: `enum PMTCLI { static let usage: String; static func run(_ argv: [String], store: BoardsStore, ffStore: ConfigStore, now: Date = Date()) throws -> String }`. `main.swift` mirrors FrequentFinder's `Sources/ff/main.swift` (usage → stderr exit 2; other errors → `pmt: <message>` exit 1).

The commands, arguments and meanings are the spec's list ("The `pmt` command"), with `board attach` as there. Fixed details:
- Project arguments are names, resolved with `Catalog.resolve`. `board attach` takes the orphan board's full UUID (case-insensitive) then a project name.
- `--at N` and `column move <N>` are **1-based** for people; convert to 0-based.
- `--force`, `--done`, `--json` are flags; `--notes`, `--title`, `--column`, `--at` take a value. Copy FrequentFinder's `takeFlag`/`takeOption`.
- Each run: load FF with `Catalog.loadFrequentFinder(ffStore)` (a broken FF file is not an error for `pmt`), then make edits through `store.update(ff:)`. Read-only commands use `store.load()`.
- Text output:
  - `projects`: one line per project, `name<TAB>FrequentFinder|own<TAB>board|no board`, plus `<TAB>(inactive)` for inactive FF projects. Empty: `No projects. Add one with: pmt project add <name>`.
  - `board <project>`: each column name on its own line, last one as `<name> (done)`; under each, cards as `  <id>  <title>`.
  - `board list`: `<project name or (orphaned)><TAB><project UUID><TAB><open count> open, <archived count> done`.
  - `task add` prints the new id. Moving to Done (`task move`/`task done`) prints `Archived <id>`.
  - `task show`: `id`, `title`, `project`, `column` (or `Done <ISO date>`), then the notes after a blank line.
  - `search`: `<id><TAB><project><TAB><column or Done><TAB><title>`; none: `No tasks found.`
  - `--json` on `projects`, `board`, `board list`, `search`: pretty JSON of the same fields (builder picks key names; must decode with `JSONSerialization`).

- [ ] **Step 1: Write the failing tests.** Each test makes a temp `BoardsStore` and a temp `ConfigStore`; helper `func pmt(_ args: String...) throws -> String`.

```swift
@Test func cliEndToEnd() throws {
    _ = try pmt("project", "add", "Breakthrough")
    _ = try pmt("board", "create", "breakthrough", "To Do", "Doing", "Done")
    let id = try pmt("task", "add", "Breakthrough", "Launch email", "--notes", "Draft by Friday")
    #expect(try pmt("board", "Breakthrough") == "To Do\n  \(id)  Launch email\nDoing\nDone (done)")
    #expect(try pmt("task", "move", id, "Done") == "Archived \(id)")
    #expect(try pmt("search", "friday") == "No tasks found.")
    #expect(try pmt("search", "friday", "--done") == "\(id)\tBreakthrough\tDone\tLaunch email")
    _ = try pmt("task", "restore", id)
    #expect(try pmt("board", "Breakthrough").contains("To Do\n  \(id)"))
}

@Test func cliSeesFrequentFinderProjects() throws {
    try ffStore.save(Config(projects: [Project(name: "openpmtools", path: nil)]))
    #expect(try pmt("projects") == "openpmtools\tFrequentFinder\tno board")
    #expect(throws: PMTError.duplicateName("OpenPMTools")) { try pmt("project", "add", "OpenPMTools") }
}

@Test func cliBoardAttach() throws {
    let gone = UUID()
    var f = BoardsFile(); try f.createBoard(project: gone, columns: ["A", "Done"]); try store.save(f)
    #expect(try pmt("board", "list") == "(orphaned)\t\(gone.uuidString)\t0 open, 0 done")
    _ = try pmt("project", "add", "Book")
    _ = try pmt("board", "attach", gone.uuidString.lowercased(), "book")
    #expect(try pmt("board", "list").hasPrefix("Book\t"))
}
```

Also: `cliUsageErrors` (no args, unknown command, missing value after `--notes` → `PMTError.usage`), `cliColumnMoveIsOneBased`, `cliDeleteBoardNeedsForce`, `cliJSONParses` (each `--json` output parses with `JSONSerialization`).

- [ ] **Step 2: Run to verify failure.** `swift test --filter CLITests` — Expected: compile errors.
- [ ] **Step 3: Implement** `PMTCLI` and `main.swift`. `usage` lists every command (spec list) and ends with `Data file: ~/.config/openpmtools/boards.json (override with PMT_CONFIG)`.
- [ ] **Step 4: Run tests.** `swift test` — Expected: pass. Then `swift run pmt help` prints the usage.
- [ ] **Step 5: Commit.** `git commit -m "Add pmt command"`

---

### Task 7: App shell — model, sidebar, board setup, build script

**Files:**
- Create: `Sources/OpenPMToolsApp/OpenPMToolsApp.swift` (replace placeholder), `AppModel.swift`, `Sidebar.swift`, `GitSymbol.swift`, `BoardSetupView.swift`, `scripts/make-app.sh`, `scripts/make-icon.swift`, `Resources/AppIcon.icns`, `README.md`

**Interfaces:**
- Consumes: PMTCore; FFCore `ConfigStore`, `Git.status(at:)`, `GitStatus.combine`, `Project.fullPath(of:)`, `ProjectDrag`.
- Produces: `@MainActor @Observable final class AppModel` with `file: BoardsFile`, `ff: FFCore.Config`, `catalog: Catalog`, `loadError: String?` (boards.json broken: edits blocked), `ffError: String?`, `error: String?` (last failed action), `git: [String: GitStatus]`, `selection: UUID?` (stored in `@AppStorage("selection")` as a string by the view), `func update(_ change: (inout BoardsFile) throws -> Void)`, `func combinedGit(_ entry: ProjectEntry) -> GitStatus?`, `func reload()`.

- [ ] **Step 1: AppModel.** Follow FrequentFinder's `AppModel.swift` pattern exactly: `reload()` on init, watch **both** folders (`BoardsStore.defaultURL` and `ConfigStore.defaultURL` parents) with `DispatchSource` `.write`, `reload()` on either. Reload FF via `Catalog.loadFrequentFinder()`. Git refresh on load, every 60 s, and on window key, for active FF projects' path and repos. `update` calls `store.update(ff:)`, sets `file`, and rebuilds `catalog`; it catches `PMTError.badConfig` into `loadError` and other errors into `error`. Edits do nothing while `loadError != nil`.
- [ ] **Step 2: GitSymbol.swift.** Copy `GitSymbol` (`name`, `color`, `description`) from `frequent-finder/Sources/FFApp/MenuContent.swift:75-93`, with a comment naming the source.
- [ ] **Step 3: App and Sidebar.** A single `Window("OpenPMTools", id: "main")` with `NavigationSplitView`, `.frame(minWidth: 760, minHeight: 480)`. Sidebar `List(selection:)` with `Section("FrequentFinder")` (git symbol, name, accessibility label as in FrequentFinder's `AllProjectsView`; an `ffError` shows as a secondary-text row in this section) and `Section("My Projects")`. Own rows are `.draggable(ProjectDrag(id:name:))` and have a context menu: Rename…, Delete… (confirmation dialog; uses `removeOwnProject(force: true)` after confirming when the board has tasks). A toolbar "+" button (and File > New Project…, ⌘N) asks for a name in a sheet and calls `addOwnProject`; errors show in the sheet. Detail: no selection → "Select a project"; selected and no board → `BoardSetupView`; with a board → `BoardView` (Task 8; a placeholder `Text` until then).
- [ ] **Step 4: BoardSetupView.** Title "<project> has no board". Editable column list pre-filled `["To Do", "Doing", "Done"]` (TextFields; add, delete, reorder with `.onMove`). Footer note: "The last column is Done. Tasks moved there are archived." A "Create Board" button (default action, disabled with fewer than 2 non-blank names) calls `createBoard`.
- [ ] **Step 5: Build script and icon.** `scripts/make-app.sh` copies FrequentFinder's, with: app `OpenPMTools`, `CFBundleIdentifier` `org.hyland-wood.OpenPMTools`, `CFBundleName` `OpenPMTools`, no `LSUIElement`, installs `pmt`, plus `UTExportedTypeDeclarations` for `org.hyland-wood.openpmtools.project` (conforms to `public.json`, description `OpenPMTools Project`). Icon: adapt FrequentFinder's `scripts/make-icon.swift` to draw a three-column board glyph; commit the generated `Resources/AppIcon.icns`.
- [ ] **Step 6: Verify.** `swift test` passes; `scripts/make-app.sh` builds; `open build/OpenPMTools.app`. Check: the FrequentFinder projects show with git symbols; `ff deactivate <name>` hides one within a second; `ff rename` shows the new name; adding an own project works; creating a board from the setup view works; `pmt board <name>` shows it.
- [ ] **Step 7: README.** What it is (one paragraph from the spec's intent), build/install (same as FrequentFinder's), `pmt help` output, data file location. Commit: `git commit -m "Add OpenPMTools app shell, sidebar and board setup"`

---

### Task 8: Board view — cards, drag and drop, puff of smoke, columns

**Files:**
- Create: `Sources/OpenPMToolsApp/BoardView.swift`, `CardViews.swift`
- Modify: `Sidebar.swift` (replace the placeholder)

**Interfaces:**
- Consumes: `AppModel.update`, Task 4 ops, `Board`, `Card`.
- Produces: `struct BoardView: View { let project: ProjectEntry; var highlight: String? }` (Task 9 sets `highlight` to a card id to scroll to and flash it).

- [ ] **Step 1: Layout.** Horizontal `ScrollView` of fixed-width columns (about 240 pt). Each column: header with the name and count, a "+" button (working columns only), and its cards. The Done column shows a dashed drop area with `sparkles` or `wind` SF Symbol and the text "Drop here when done". Use system materials and colors so light and dark mode both work.
- [ ] **Step 2: Cards.** `CardView` shows the title (headline) and notes (secondary, `lineLimit(3)`). Clicking opens an edit popover or sheet with Title and Notes fields (Notes as a `TextEditor`); Save calls `editCard`. The context menu has Move To ▸ (each column, including Done), Edit…, and Delete… (with confirmation, then `deleteCard`). The "+" button opens the same editor empty and calls `addCard(column:)`.
- [ ] **Step 3: Drag and drop.** Cards are `.draggable(card.id)` (String). Each column is `.dropDestination(for: String.self)`; dropping between cards inserts at that index (`moveCard(_:to:at:)`). A drop on Done calls `moveCard` and, when it returns true, `NSAnimationEffect.disappearingItemDefault.show(centeredAt: NSEvent.mouseLocation, size: NSSize(width: 64, height: 64))` on the main thread. "Move To ▸ Done" plays the same effect at the card's location. Errors (for example a card deleted by `pmt`) show through `model.error`.
- [ ] **Step 4: Columns.** Each column header has a menu: Rename…, Move Left, Move Right, Delete (disabled when not empty, and absent for Done), and Add Column… (inserts after this one; for Done, inserts before it). They call the Task 4 column ops.
- [ ] **Step 5: Accessibility.** Each card has the accessibility label "<title>, in <column>". Move To gives a way to move without dragging. Every icon-only button has a label.
  Undo (⌘Z) is not part of this plan: an undo that restores an old copy of the whole file would overwrite `pmt` edits, and Restore already brings back a done card. Leave a `// ponytail:` note in `AppModel.update` that names this limit.
- [ ] **Step 6: Verify.** `scripts/make-app.sh && open build/OpenPMTools.app`. Drag a card across columns and within a column. Drop one on Done: the poof plays, and the card is gone. `pmt search <word> --done` finds it. Then run `pmt task add <project> "From CLI"`: the card shows up in the open window. Check dark mode (System Settings > Appearance). Commit: `git commit -m "Add board view with drag and drop and archive animation"`

---

### Task 9: Search and restore

**Files:**
- Create: `Sources/OpenPMToolsApp/SearchView.swift`
- Modify: `Sidebar.swift` / `OpenPMToolsApp.swift` (toolbar search)

**Interfaces:**
- Consumes: `BoardsFile.search(_:includeDone:)`, `CardLocation`, `Catalog.entry(for:)`, `restoreCard`, `BoardView(highlight:)`.

- [ ] **Step 1: Search field.** `.searchable(text:placement: .toolbar)` on the split view. ⌘F focuses it (SwiftUI gives this on macOS; check that it works, and add a Find menu command only if it does not). An "Include Done" `Toggle` sits next to it as a toolbar item.
- [ ] **Step 2: Results.** While the text is not empty, the detail area shows `SearchView`: a list of results showing the title, the project name (`catalog.entry(for:)?.name ?? "(orphaned board)"`), and the column or "Done". Empty: `ContentUnavailableView.search`.
- [ ] **Step 3: Open result.** Clicking an open card clears the search, selects its project (`selection = project`), and shows `BoardView(highlight: id)`. If the project has no sidebar row (inactive or orphaned), it shows that board in the detail area with no sidebar selection.
- [ ] **Step 4: Done result.** Clicking an archived card shows it read-only: the title, the notes, the "Done <date>" text, and "From <fromColumn>". It has a **Restore** button that calls `restoreCard` and then opens the board with the card highlighted.
- [ ] **Step 5: Verify.** Build and run. Search a word that is in two projects, and check that both show. Turn on Include Done and find an archived card. Click Restore: the card is back at the bottom of the first column. Commit: `git commit -m "Add search across projects with restore"`

---

### Task 10: Drag-to-FrequentFinder check and finish

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Verify the drag end to end.** Open FrequentFinder's All Projects window and OpenPMTools. Drag an own project that has a board onto FrequentFinder's sidebar. Expected: the project shows in FrequentFinder. In OpenPMTools, it moves to the FrequentFinder section with its board, and `pmt projects` lists it once as `FrequentFinder`. Then `ff rename <it> <new>`: OpenPMTools shows the new name, and the board stays.
- [ ] **Step 2: Verify the dupe refusal.** Make an own project, then `ff add --name <same name>`. Expected: both show; `pmt board <name>` says the name is ambiguous.
- [ ] **Step 3: README.** Add a "Working with FrequentFinder" section with 3–4 lines: the projects show up there, you drag to add, renames follow, and FrequentFinder must be on its `main` branch with ids (build note). Add a screenshot of the board to `docs/images/board.png`, as FrequentFinder's README does.
- [ ] **Step 4: Full test run.** `swift test` in both repos — Expected: all pass. Commit: `git commit -am "Document working with FrequentFinder"`. Then use superpowers:finishing-a-development-branch.
