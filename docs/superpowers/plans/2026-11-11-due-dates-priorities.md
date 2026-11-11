# Due Dates, Priorities, and New Task Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tasks get an optional due date and priority; the date raises priority, colours the card, and cards sort by priority; ⌘N adds a task.

**Architecture:** All rules (dates, effective priority, urgency, display order, drop-with-priority) live in PMTCore as pure functions with a `today: Day` parameter, so they are unit-tested. The app only draws them and passes `model.today`. The saved order in boards.json stays the drag order; sorting is display-only.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftUI/AppKit, Swift Testing, SwiftPM, macOS 15+.

**Spec:** `docs/superpowers/specs/2026-11-11-due-dates-priorities-design.md`

## Global Constraints

- Due date is a day: JSON string `"YYYY-MM-DD"` (key `due`). Priority JSON string `"low" | "medium" | "high"` (key `priority`). Both omitted when none. Old files load unchanged.
- Raise rule: due ≤ today → at least High; due ≤ today + 2 days → at least Medium. Never lowers. Never saved.
- Urgency colours: due ≤ today → red; due ≤ today + 2 → yellow; later → green; no date or done → none. ⚠︎ only when due < today.
- Display order: effective priority (High, Medium, Low, None), then due (earliest first, none last), then saved order. Stable.
- Priority icons: Low `↓`, Medium `!`, High `!!`. Raised tooltip: `Raised: due soon`. VoiceOver: `High priority` etc.; after a drop that changes priority, announce `Priority changed to High`.
- New cards (⌘N and column "+") are inserted at index 0 of the column's saved order.
- Shortcuts: ⌘N = New Task…, ⇧⌘N = New Project….
- "today" is the local calendar day (`Calendar.current`), refreshed at midnight (`.NSCalendarDayChanged`) and on app activation.
- Colour is never the only signal. Label symbol and words: overdue `exclamationmark.triangle.fill` + `Overdue · 12 Nov`; today `clock.badge.exclamationmark` + `Today`; due +1 `clock` + `Tomorrow`; due +2 `clock` + `In 2 days`; later `calendar` + `20 Nov`. Done: date only, no symbol. VoiceOver reads the words.
- The date label is a capsule filled with the urgency colour at 25% opacity, text in the primary colour (yellow text on white fails contrast). The top stripe is the urgency colour at full strength, 4 pt.

## Review Focus

1. A boards.json written before this change (no `due`/`priority` keys) loads, and saving it adds no keys for cards without them. → Task 1 `oldCardsDecodeWithoutNewKeys`.
2. Invalid dates (`2026-02-30`, `14/11/2026`, `2026-1-5`) are refused, not silently shifted. → Task 1 `dayRejectsBadText`.
3. Dropping a card on itself, or on the card just below it on the same board, keeps the saved order sensible (no off-by-one). → Task 2 `dropOnSelfIsNoChange`, `dropBelowNextCard`.
4. On the Big Board, dropping onto another project's card takes its priority but keeps the card on its own board, last in saved order. → Task 2 `dropOntoOtherBoardsCard`.
5. ⌘N with nothing to add to (no selection, project without board, Big Board with no boards) is disabled, not a crash or silent no-op. → Task 5 hand check (app target has no unit tests).

---

### Task 1: Day, Priority, urgency, display order (PMTCore)

**Files:**
- Create: `Sources/PMTCore/Due.swift`
- Modify: `Sources/PMTCore/Model.swift` (Card, ArchivedCard)
- Modify: `Sources/PMTCore/Errors.swift`
- Test: `Tests/PMTCoreTests/DueTests.swift`

**Interfaces:**
- Produces:
  - `public struct Day: Codable, Hashable, Comparable, Sendable` — single-value coded as `"YYYY-MM-DD"`. `public init?(_ text: String)` (strict: 4-2-2 digits, real calendar date, Gregorian). `public var text: String`. `public static func today(now: Date = Date(), calendar: Calendar = .current) -> Day`. `public func adding(days: Int) -> Day`.
  - `public enum Priority: String, Codable, CaseIterable, Comparable, Sendable { case low, medium, high }` with `public var label: String` ("Low"…), `public var symbol: String` ("↓", "!", "!!"). `public init?(argument: String)` accepts case-insensitive `low|medium|high`.
  - `public enum Urgency: Sendable { case later, soon, now }` — green, yellow, red.
  - `Card` and `ArchivedCard` gain `public var due: Day?` and `public var priority: Priority?` (init params default nil; ArchivedCard copies both ways).
  - `extension Card`: `public func urgency(today: Day) -> Urgency?`, `public func isOverdue(today: Day) -> Bool`, `public func effectivePriority(today: Day) -> Priority?`, `public func isRaised(today: Day) -> Bool`.
  - `public func dueText(_ due: Day, today: Day) -> String` (see Task 4 Interfaces for the words).
  - `public func displayOrder<T>(_ items: [T], today: Day, card: (T) -> Card) -> [T]` — stable sort by the Global Constraints order.
  - `PMTError.badDue(String)` → `"Due date must look like 2026-11-14 (got 'X')."`; `PMTError.badPriority(String)` → `"Priority must be low, medium, high or none (got 'X')."`

- [ ] **Step 1: Write the failing tests** in `DueTests.swift`:
  - `dayParsesAndPrints`: `Day("2026-11-14")?.text == "2026-11-14"`; `Day("2026-12-31")!.adding(days: 1).text == "2027-01-01"`; `Day("2026-11-14")! < Day("2026-11-15")!`.
  - `dayRejectsBadText`: nil for `"2026-02-30"`, `"14/11/2026"`, `"2026-1-5"`, `""`, `"2026-11-14x"`.
  - `todayUsesCalendarTimeZone`: with a calendar in `TimeZone(identifier: "Pacific/Auckland")` and `now = 2026-11-14T12:00:00Z`, `Day.today(...)` is `"2026-11-15"`.
  - `urgencyAndRaise` with today `2026-11-14`: due `11-13` → `.now`, overdue, effective High, raised; due `11-14` → `.now`, not overdue, High; due `11-16` → `.soon`, Medium; due `11-17` → `.later`, effective = set priority; set High + due `11-16` → High, not raised; no due → urgency nil, effective = set.
  - `displayOrderSorts`: cards [none, low, high-due-11-20, none-due-11-15 (→ Medium), high-due-11-18] sort to [high-11-18, high-11-20, none-11-15, low, none]; two equal cards keep input order.
  - `oldCardsDecodeWithoutNewKeys`: decode `{"id":"a","title":"T","created":"2026-11-01T00:00:00Z"}` (ISO 8601 dates) → `due == nil && priority == nil`; re-encode with `BoardsFile.jsonData()`-style encoder has no `"due"` or `"priority"`. A card with both set round-trips with `"due" : "2026-11-14"` and `"priority" : "high"`.
  - `dueWordsAndSymbols` (today 2026-11-14): `dueText` gives `"Overdue · 12 Nov"` for 11-12, `"Today"`, `"Tomorrow"`, `"In 2 days"`, `"20 Nov"` for 11-20.
  - `archivedKeepsDueAndPriority`: `ArchivedCard(card, ...).card == card` for a card with both set.

- [ ] **Step 2: Run** `swift test --filter DueTests` — Expected: build fails (Day, Priority not defined).

- [ ] **Step 3: Implement** `Due.swift`, the Model fields, and the errors. Day stores `year, month, day`; parse with a regex `^\d{4}-\d{2}-\d{2}$` then check via a Gregorian UTC calendar that the components round-trip. `adding(days:)` uses that same UTC calendar.

- [ ] **Step 4: Run** `swift test` — Expected: all pass (existing 38 + new).

- [ ] **Step 5: Commit** `git commit -m "Add due dates and priorities to cards"`

---

### Task 2: Card operations (PMTCore)

**Files:**
- Modify: `Sources/PMTCore/BoardOps.swift`
- Test: `Tests/PMTCoreTests/BoardOpsTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  - `addCard(project:title:notes:column:due: Day? = nil, priority: Priority? = nil, now:)` — inserts at index 0.
  - `public mutating func setDue(_ id: String, _ due: Day?) throws` and `public mutating func setPriority(_ id: String, _ priority: Priority?) throws` — open cards only (`noSuchTask` otherwise).
  - `public struct DropResult: Equatable, Sendable { public var archived: Bool; public var priorityChanged: Bool }`
  - `public mutating func dropCard(_ id: String, to column: String, onto target: String?, below: Bool, today: Day, now: Date = Date()) throws -> DropResult` — `column` is matched case-insensitively on the dragged card's own board. With `target`: the card takes `target`'s effective priority (saved as `priority`; `.none` effective → nil); when target is in that column of the same board, the card is placed just before it (after it if `below`) in saved order, else at the end. Without `target`: priority unchanged, placed at the end. Dropping on itself: no change. Moving to the last column archives (as `moveCard`).
  - `bigBoard(today: Day)` — each column's `cards` in `displayOrder`. (Replace `bigBoard()`; update its callers.)
  - `restoreCard` keeps due and priority (comes from `ArchivedCard.card`).

- [ ] **Step 1: Write the failing tests**:
  - `newCardsGoFirst`: add A then B to To Do → saved order `[B, A]`.
  - `setDueAndPriority`: set and clear both; archived id → `noSuchTask`.
  - `dropTakesTargetsEffectivePriority`: target none-priority due today; dropped card none → becomes `.high`, `priorityChanged == true`.
  - `dropOnEmptySpaceKeepsPriority`: low card dropped with `onto: nil` into Doing → still low, last in Doing, `priorityChanged == false`.
  - `dropOnSelfIsNoChange`: file unchanged, `DropResult(archived: false, priorityChanged: false)`.
  - `dropBelowNextCard`: saved [A, B, C], drop A onto B below → [B, A, C]; then drop C onto B above → [C, B, A]; then drop B onto A below → [C, A, B].
  - `dropOntoOtherBoardsCard`: two boards with column "Doing"; drop board-1 card onto board-2 high card in "Doing" → card is on board 1, last in its "Doing", priority high.
  - `dropIntoDoneArchives`: to last column → `archived == true`, archive keeps due and priority; restore brings them back.
  - Update `moveToLastColumnArchives` and any other test that assumed add appends.
  - `bigBoardSortsByPriority`: two boards' "To Do" merged; a high card from board 2 comes before board 1's none cards.

- [ ] **Step 2: Run** `swift test` — Expected: the new tests fail (missing functions / wrong order).

- [ ] **Step 3: Implement.** In `dropCard`, compute the target's effective priority and position *before* removing the dragged card; adjust the insert index by −1 when the dragged card was earlier in the same column.

- [ ] **Step 4: Run** `swift test` — Expected: all pass.

- [ ] **Step 5: Commit** `git commit -m "Add setDue, setPriority, dropCard; new cards go first; Big Board sorts by priority"`

---

### Task 3: `pmt` options and output

**Files:**
- Modify: `Sources/PMTCore/CLI.swift`
- Modify: `README.md` (usage block)
- Test: `Tests/PMTCoreTests/CLITests.swift`

**Interfaces:**
- Consumes: Task 1–2. `today = Day.today(now: now)`.
- Produces: usage lines
  - `pmt task add <project> <title> [--notes "..."] [--column <name>] [--due YYYY-MM-DD] [--priority low|medium|high]`
  - `pmt task edit <id> [--title "..."] [--notes "..."] [--due YYYY-MM-DD|none] [--priority low|medium|high|none]`
  - Board text: task lines become `  <id>  <title>` + `  [<symbol> <Label>]` when effective priority set (`, raised` inside the brackets when raised) + `  [due YYYY-MM-DD]` when set; lines in display order.
  - Board JSON task objects add `"due"` (string or absent), `"priority"` (set, string or absent), `"effectivePriority"` (string or absent).
  - `task show` adds `due: YYYY-MM-DD` and `priority: High (raised: due soon)` lines when set.

- [ ] **Step 1: Write the failing tests** (fixed `now` = 2026-11-14 12:00 local, passed to `PMTCLI.run`):
  - `cliDueAndPriority`: add with `--due 2026-11-15 --priority low` → board line `  <id>  T  [! Medium, raised]  [due 2026-11-15]`; `task edit <id> --due none --priority none` → line `  <id>  T`.
  - `cliBadDueAndPriority`: `--due 15/11/2026` throws `badDue("15/11/2026")`; `--priority urgent` throws `badPriority("urgent")`.
  - `cliShowsDueInShowAndJSON`: `task show` contains `due: 2026-11-15` and `priority: Medium (raised: due soon)`; `board --json` contains `"effectivePriority" : "medium"`.
  - Update `cliEndToEnd` if new-first order changes its output.

- [ ] **Step 2: Run** `swift test --filter CLITests` — Expected: new tests fail.

- [ ] **Step 3: Implement** with `takeOption("--due")` / `takeOption("--priority")`; `"none"` (any case) means clear. Edit applies `setDue` / `setPriority` only when the option was given. Update README's usage block to match `pmt help`.

- [ ] **Step 4: Run** `swift test` — Expected: all pass.

- [ ] **Step 5: Commit** `git commit -m "pmt: --due and --priority; show them in board and task show"`

---

### Task 4: Cards show date, colour, priority; boards sort; drops set priority (app)

**Files:**
- Modify: `Sources/OpenPMToolsApp/AppModel.swift` (`today`)
- Modify: `Sources/OpenPMToolsApp/CardViews.swift`
- Modify: `Sources/OpenPMToolsApp/BoardView.swift`
- Modify: `Sources/OpenPMToolsApp/BigBoardView.swift`
- Modify: `Sources/OpenPMToolsApp/SearchView.swift`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `AppModel.today: Day` — set at init; updated on `.NSCalendarDayChanged` and `NSApplication.didBecomeActiveNotification`.
  - `extension Urgency { var color: Color }` (green, yellow, red) in CardViews.swift.
  - PMTCore (add to Task 1, test `dueWordsAndSymbols`): `public func dueText(_ due: Day, today: Day) -> String` → `"Overdue · 12 Nov"`, `"Today"`, `"Tomorrow"`, `"In 2 days"`, `"20 Nov"` (day + English abbreviated month from a fixed table, so it is testable).
  - `struct DueLabel: View { let due: Day; let today: Day; let done: Bool }` — capsule label (Global Constraints) with the symbol from Global Constraints and `dueText`; done → plain date, no colour, no symbol.
  - `struct PriorityIcon: View { let priority: Priority; let raised: Bool }` — `.help("Raised: due soon")` when raised.
  - `AppModel.drop(_ id: String, to column: String, onto target: String?, below: Bool, poofAt: NSPoint) -> Bool` — calls `dropCard` via `update`, plays the poof when archived, posts `AccessibilityNotification.Announcement("Priority changed to \(label)")` when `priorityChanged` (label "None" when cleared). Replaces `AppModel.move` for drops; the context-menu Move To keeps `move`.

- [ ] **Step 1: Model.** Add `today` and its two observers.
- [ ] **Step 2: CardView.** Top stripe (Global Constraints) when the card has an urgency; `PriorityIcon` before the title when effective priority set; `DueLabel` under the title when due set. Accessibility label adds `", High priority"` and `", due 14 Nov"` (`", overdue"` when overdue). Tag stripe on the leading edge stays for the Big Board.
- [ ] **Step 3: BoardView.** `ForEach` over `displayOrder(column.tasks, today: model.today) { $0 }`. The card drop calls `model.drop(id, to: column.name, onto: card.id, below: below, ...)`; the column drop calls it with `onto: nil`. Delete the old index arithmetic in `ColumnView.drop`; keep the "only cards on this board" guard.
- [ ] **Step 4: BigBoardView.** Use `bigBoard(today: model.today)`. Card drop → `model.drop(id, to: column.name, onto: loc.card.id, below: below, ...)`; empty-space drop → `onto: nil`. Keep the beep-and-refuse when the card's board has no such column (the `blocked` check).
- [ ] **Step 5: SearchView.** Open results show `PriorityIcon` and `DueLabel` (with urgency) in the row; done results show the date label without colour.
- [ ] **Step 6: Run** `swift build` and `swift test` — Expected: build clean, all tests pass.
- [ ] **Step 7: Hand check** (`swift run OpenPMTools` with `PMT_CONFIG` pointing at a copy of boards.json; set dates with `pmt task edit … --due`): colours for overdue / today / +2 / +3 / none; ⚠︎ only overdue; sort order; drop onto a High card makes a None card High and VoiceOver announces it (`⌘F5`); drop on empty space keeps priority; Big Board same; refused drop still beeps.
- [ ] **Step 8: Commit** `git commit -m "Show due dates, urgency colour and priority on cards; sort by priority; drops take priority"`

---

### Task 5: Editor fields, ⌘N New Task, ⇧⌘N New Project (app)

**Files:**
- Modify: `Sources/OpenPMToolsApp/CardViews.swift` (CardEditor)
- Modify: `Sources/OpenPMToolsApp/BoardView.swift` ("+" sheet)
- Modify: `Sources/OpenPMToolsApp/OpenPMToolsApp.swift` (commands, ContentView sheet)
- Modify: `Sources/OpenPMToolsApp/BigBoardView.swift` (New Task sheet)
- Modify: `README.md`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `struct CardDraft { var title: String; var notes: String; var due: Day?; var priority: Priority?; var project: UUID? }`
  - `CardEditor(heading:button:draft:projects: [ProjectEntry]? = nil, save: (CardDraft) -> Bool)` — fields: Title, Notes, a "Due date" Toggle that shows a `DatePicker(.date)` when on (default today), a Priority `Picker` (None, Low, Medium, High), and a Project `Picker` only when `projects` is non-nil.
  - `struct NewTaskAction { let run: () -> Void }` as a `FocusedValues` entry `newTask`. Main window provides it via `.focusedSceneValue` only when the shown project has a board; Big Board provides it only when boards exist.
  - Commands: `CommandGroup(replacing: .newItem)` with `New Task…` (⌘N, `@FocusedValue(\.newTask)`, disabled when nil) and `New Project…` (⇧⌘N).
  - Big Board remembers the last project in `@AppStorage("lastNewTaskProject")`; the sheet starts on it (or the first board's project if gone).

- [ ] **Step 1: CardEditor** with `CardDraft`; Edit sheet saves via `editCard` + `setDue` + `setPriority` in one `model.update`.
- [ ] **Step 2: Column "+"** uses the new editor and `addCard(... due:priority:)` (index 0 comes from Task 2).
- [ ] **Step 3: ⌘N main window.** ContentView sheet: heading `New Task in <first column>`, adds to the shown project's first column.
- [ ] **Step 4: ⌘N Big Board.** Sheet with Project picker over projects that have boards; adds to that board's first column; stores the choice.
- [ ] **Step 5: Commands** as in Interfaces. README: one paragraph on due dates, priorities, colours, sorting, and ⌘N / ⇧⌘N.
- [ ] **Step 6: Run** `swift build` and `swift test` — Expected: clean, all pass.
- [ ] **Step 7: Hand check:** ⌘N with a project → task at top of its group; ⌘N with nothing selected → menu item disabled; ⌘N on Big Board → picker starts on last project; ⇧⌘N → New Project sheet; edit sheet sets and clears date and priority.
- [ ] **Step 8: Commit** `git commit -m "Due date and priority in the task editor; ⌘N New Task, ⇧⌘N New Project"`
