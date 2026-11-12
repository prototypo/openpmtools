# Sync merge (part 1 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every saved change to `projects.json` and `boards.json` records who changed which field and when, deletes leave tombstones, and two diverged copies of either file can be merged with no data loss. Plus a "Move to" column choice in the Mac task editor.

**Architecture:** All writes already go through one save path per file (`ConfigStore.update`, `BoardsStore.update`, and the `ff` CLI's load/save). That path diffs the file before and after the change and records a `Stamp` (time, device, version vector) per changed field, plus a tombstone per deleted item. Stamps and tombstones live in two top-level tables in each file, so the item structs do not change shape. `merge` is a pure function per file type that uses the stamps. Nothing calls `merge` yet: part 2 (iCloud move, after the spike) wires it in; part 3 is the iOS app.

**Tech Stack:** Swift 6 tools, Swift 5 language mode, SwiftPM, Swift Testing (`import Testing`, `@Test`, `#expect`), Foundation only.

**Spec:** `docs/superpowers/specs/2026-11-12-ios-app-and-icloud-sync-design.md` (sections "Merge rules", "Shared data and per-Mac data", "Code changes → Mac").

## Global Constraints

- Two repos. `frequent-finder` (FFCore) work on a new branch `sync-merge` made from `main` (not from `brief-link-errors`). `openpmtools` work on the existing branch `ios-app-design`. `openpmtools` builds against `../frequent-finder` as checked out, so keep `frequent-finder` on `sync-merge` while working on `openpmtools` tasks.
- Run tests with `swift test` in the repo root. All existing tests must still pass.
- No new dependencies. Foundation only (no CryptoKit needed).
- Old files (no stamps, no tombstones, no column ids) must load, and must save with their existing content unchanged apart from the new fields.
- Shared FrequentFinder project fields: `name`, `urls`, `active`, `notes`. Per-Mac fields: `path`, `keyFiles`, `repos`, `Config.terminal`, `Config.linkedApps`. Per-Mac fields get no stamps and are never taken from the other side in a merge.
- Kept-both notes divider, exact text: `\n\n— Also edited on <by>, <yyyy-MM-dd HH:mm> —\n\n`. Kept-both titles: `<older> / <newer>`.
- Tombstones and their items' stamps older than 90 days are dropped on save.
- Mac-only code stays as is; iOS platform support is part 3.

## Review Focus

1. **Notes saved on every keystroke.** FrequentFinder saves notes as you type. A note typed for 5 minutes on one device and untouched on the other must merge to the typed text, with no kept-both copy. The version vector handles this; test `typedNotesMergeCleanly` in Task 3.
2. **Repeated merges.** Merging the merged result with either input again must change nothing (no second copy of kept-both text). Tests `mergeIsIdempotent` in Tasks 3 and 6.
3. **Clock skew.** A device whose clock is an hour behind still wins when its edit came causally after the other's. Test `causalBeatsClock` in Task 1.
4. **Two Macs, same old columns.** Two Macs loading the same old `boards.json` must give each column the same id, or every column doubles after the first merge. Test `oldColumnsGetNameIDs` in Task 4.
5. **Same card id on two devices.** Card ids are 6 hex characters, unique only in one file. Two different cards with the same id (different `created`) must both survive a merge. Test `cardIDCollisionKeepsBoth` in Task 6.

---

### Task 1: Stamps, devices and field merge (FFCore)

**Files:**
- Create: `frequent-finder/Sources/FFCore/Sync.swift`
- Test: `frequent-finder/Tests/FFCoreTests/SyncTests.swift`

**Interfaces:**
- Produces:
  - `public struct Device: Codable, Hashable, Sendable { public var id: String; public var name: String }`
  - `public static func Device.load(from url: URL = Device.defaultURL) throws -> Device` — reads the file; if missing, creates it with `id = UUID().uuidString` and `name = Host.current().localizedName ?? "Mac"`.
  - `public static var Device.defaultURL: URL` — `$FF_DEVICE` if set, else `~/.config/frequent-finder/device.json`. Never synced.
  - `public struct Stamp: Codable, Hashable, Sendable { public var at: Double; public var by: String; public var clock: [String: Int] }` — `at` is seconds since 1970 (sub-second precision on purpose), `by` the device name, `clock` a version vector: device id → edit count.
  - `public func Stamp.bumped(by device: Device, now: Date) -> Stamp` — same clock with `clock[device.id] += 1`, `at = now`, `by = device.name`. `Stamp.bumped` on `nil` starts from an empty clock: `static func Stamp.first(by:now:) -> Stamp`.
  - `public enum Causal { case same, aBeforeB, bBeforeA, concurrent }` and `public func causal(_ a: Stamp?, _ b: Stamp?) -> Causal` — compares clocks; a missing stamp is an empty clock.
  - `public func mergeValue<T: Equatable>(_ a: T, _ sa: Stamp?, _ b: T, _ sb: Stamp?) -> (T, Stamp?)` — the causally later side wins; if concurrent, the larger `at` wins; tie on `at`, the larger `by` wins (so every device picks the same). The result stamp is the winner's, with `clock` = pointwise max of both.
  - `public enum TextJoin { case notes, title }` and `public func mergeText(_ a: String?, _ sa: Stamp?, _ b: String?, _ sb: Stamp?, join: TextJoin) -> (String?, Stamp?)` — like `mergeValue`, but when concurrent and the texts differ, keep both: older (by `at`) first, then the divider (Global Constraints), then newer. A nil side is just the other text. Result stamp: clock = pointwise max, `at` and `by` from the newer side.
  - `public typealias Stamps = [String: Stamp]`, `public typealias Tombstones = [String: Double]` (key → deletion time).

- [ ] **Step 1: Write the failing tests** in `SyncTests.swift`:
  - `deviceFileIsCreatedOnce`: `Device.load(from:)` on a temp path twice returns equal devices; the file exists.
  - `causalOrder`: `causal(nil, s1) == .aBeforeB`; a stamp bumped from another is after it; two stamps bumped from the same parent by different devices are `.concurrent`; equal clocks are `.same`.
  - `causalBeatsClock`: a = first by device A at t=1000; b = a bumped by device B at t=10 (clock behind). `mergeValue(1, a, 2, b).0 == 2`.
  - `concurrentValueNewerWins`: two concurrent stamps, `at` 5 and 6 → the value with `at` 6 wins, either argument order.
  - `concurrentNotesKeepBoth`: concurrent "x" (at 5, by "Mac") and "y" (at 6, by "iPhone") → `"x\n\n— Also edited on iPhone, <date of 6> —\n\ny"`, same result with arguments swapped. Format the expected date with the same `DateFormatter` (`yyyy-MM-dd HH:mm`, current time zone) the code uses.
  - `concurrentTitlesKeepBoth`: → `"x / y"`.
  - `sameTextNoCopy`: concurrent stamps, equal texts → the text once.

- [ ] **Step 2: Run** `swift test --filter SyncTests` in `frequent-finder`. Expected: FAIL, `Device`, `Stamp` not defined.

- [ ] **Step 3: Implement** everything in the Interfaces block in `Sources/FFCore/Sync.swift`.

- [ ] **Step 4: Run** `swift test` in `frequent-finder`. Expected: all tests pass.

- [ ] **Step 5: Commit** (on branch `sync-merge`, made from `main`)

```bash
git switch -c sync-merge main
git add Sources/FFCore/Sync.swift Tests/FFCoreTests/SyncTests.swift
git commit -m "Add stamps, version vectors and field merge for sync"
```

### Task 2: Stamp every FrequentFinder save

**Files:**
- Modify: `frequent-finder/Sources/FFCore/Config.swift` (`Config` fields and decoder; `ConfigStore.save`/`update`)
- Modify: `frequent-finder/Sources/FFCore/CLI.swift:62` (use the stamping save)
- Create: `frequent-finder/Sources/FFCore/ConfigSync.swift`
- Test: `frequent-finder/Tests/FFCoreTests/ConfigSyncTests.swift`

**Interfaces:**
- Consumes: Task 1 (`Device`, `Stamp`, `Stamps`, `Tombstones`).
- Produces:
  - `Config.stamps: Stamps` and `Config.deleted: Tombstones`, both default `[:]`, read with `decodeIfPresent`, encoded only when not empty (so an untouched old file saves byte-identical apart from what changed).
  - Stamp keys: `project:<UUID>.name`, `.urls`, `.active`, `.notes`; `config.order` (the order of project ids). Tombstone key: `project:<UUID>`.
  - `public func Config.stamped(from before: Config, by device: Device, now: Date) -> Config` — for each shared field that differs from `before` (or every shared field of a new project, and `config.order` if the id order changed), set the stamp to `stamps[key].bumped(by:now:)`. For each project id in `before` but not in `self`, add a tombstone at `now` and remove its stamps. Drop tombstones (and stamps of keys under them) older than 90 days. Per-Mac fields are ignored.
  - `public func ConfigStore.save(_ config: Config, changedFrom before: Config) throws` — stamps with `Device.load()` and `Date()`, then saves. `update` and `CLI.run` (line 62) call this instead of `save(_:)`. `save(_:)` stays for the id migration in `load` and for tests.
  - `ConfigStore.init(url:device:)` gains `device: Device? = nil`; nil means `Device.load()` at save time. Tests pass a fixed device.

- [ ] **Step 1: Write the failing tests** in `ConfigSyncTests.swift` (device `Device(id: "A", name: "Mac A")`, fixed `now`):
  - `notesChangeIsStamped`: change one project's notes → only `project:<id>.notes` gets a stamp, with `clock == ["A": 1]`; a second change makes it `["A": 2]`.
  - `pathChangeIsNotStamped`: change `path`, `keyFiles`, `repos`, `terminal` → `stamps` stays empty.
  - `removeLeavesTombstone`: remove a project → `deleted["project:<id>"] == now`, and its stamps are gone.
  - `reorderStampsOrder`: move a project → `config.order` stamped.
  - `oldTombstonesArePruned`: a tombstone 91 days old is gone after any stamped save; one 89 days old stays.
  - `oldFileRoundTrips`: a JSON string without `stamps`/`deleted` loads, and `jsonData()` of it has no `stamps` or `deleted` key.
  - `cliSaveStamps`: running `ff notes <name> "hi"` through `CLI.run` with a temp `ConfigStore(url:device:)` leaves a notes stamp in the saved file.

- [ ] **Step 2: Run** `swift test --filter ConfigSyncTests`. Expected: FAIL.

- [ ] **Step 3: Implement** the Interfaces block. `CLI.run` must take the store's device the same way `update` does.

- [ ] **Step 4: Run** `swift test`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FFCore Tests/FFCoreTests/ConfigSyncTests.swift
git commit -m "Stamp shared project fields and tombstone deletes on every save"
```

### Task 3: Merge two FrequentFinder configs

**Files:**
- Modify: `frequent-finder/Sources/FFCore/ConfigSync.swift`
- Test: `frequent-finder/Tests/FFCoreTests/ConfigSyncTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `public func Config.merged(with other: Config) -> Config` — `self` is this Mac's copy.
  - Per-Mac fields (`path`, `keyFiles`, `repos`, `terminal`, `linkedApps`) always come from `self`. A project that exists only in `other` arrives with `path: nil` and empty `keyFiles`/`repos`.
  - Projects by id: `name`, `urls`, `active` with `mergeValue`; `notes` with `mergeText(join: .notes)`.
  - A project in only one side is kept unless the other side's tombstone for it is later than every stamp `at` of that project. An edit later than the tombstone keeps the project (spec: the edit is not lost).
  - Order: the side whose `config.order` stamp wins `mergeValue` gives the order; projects missing from it go at the end in the other side's order.
  - `stamps` and `deleted`: per key, the merged result's stamp; tombstones: the later time per key, minus those for projects that survived.

- [ ] **Step 1: Write the failing tests**:
  - `differentFieldsBothSurvive`: Mac A renames a project, Mac B edits its notes (both from the same start) → merged has the new name and the new notes.
  - `perMacFieldsStayLocal`: `other` has a different `path` for the project → merged keeps `self`'s path.
  - `newProjectFromOtherHasNoPath`.
  - `deleteBeatsOlderEdit` and `newerEditBeatsDelete`.
  - `typedNotesMergeCleanly`: start from a shared copy; on side A apply 300 separate notes edits (one character each, each through `stamped(from:by:now:)`); side B unchanged → merged notes equal A's text exactly.
  - `concurrentNotesKeptBoth`: both sides edit the same notes from the same start → both texts present with the divider.
  - `mergeIsIdempotent`: `m = a.merged(with: b)`; `m.merged(with: b) == m` and `m.merged(with: a) == m`.
  - `sharedPartIsSymmetric`: with equal per-Mac fields, `a.merged(with: b) == b.merged(with: a)`.

- [ ] **Step 2: Run** `swift test --filter ConfigSyncTests`. Expected: the new tests FAIL.

- [ ] **Step 3: Implement** `Config.merged(with:)`.

- [ ] **Step 4: Run** `swift test`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FFCore/ConfigSync.swift Tests/FFCoreTests/ConfigSyncTests.swift
git commit -m "Merge two FrequentFinder configs field by field"
```

### Task 4: Column ids (PMTCore)

**Files:**
- Modify: `openpmtools/Sources/PMTCore/Model.swift` (`Column`)
- Modify: `openpmtools/Sources/PMTCore/BoardOps.swift` (`createBoard`, `addColumn`)
- Test: `openpmtools/Tests/PMTCoreTests/BoardOpsTests.swift`, `StoreTests.swift`

**Interfaces:**
- Produces: `Column.id: String`. Decoding a column with no `id` gives `id = name.trimmed.lowercased()` (the same on every device). Columns made by `createBoard` and `addColumn` get the first 8 hex characters of a new UUID, lowercased. `renameColumn` keeps the id. CLI and app keep finding columns by name; nothing else changes.

- [ ] **Step 1: Write the failing tests**:
  - `oldColumnsGetNameIDs`: decode `{"name":" Doing ","tasks":[]}` → `id == "doing"`; decoding the same JSON twice gives the same id.
  - `newColumnsGetRandomIDs`: `addColumn` twice → two 8-character ids that differ.
  - `renameKeepsColumnID`.
  - Update `roundTrip` in `StoreTests.swift` if it builds `Column` values (the memberwise init now needs or defaults the id; give `Column.init(name:tasks:id:)` a default `id` from the name).

- [ ] **Step 2: Run** `swift test --filter "BoardOpsTests|StoreTests"` in `openpmtools`. Expected: FAIL.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run** `swift test`. Expected: all pass.

- [ ] **Step 5: Commit** (on `ios-app-design`)

```bash
git add Sources/PMTCore Tests/PMTCoreTests
git commit -m "Give board columns stable ids"
```

### Task 5: Stamp every OpenPMTools save

**Files:**
- Modify: `openpmtools/Sources/PMTCore/Model.swift` (`BoardsFile` fields and decoder)
- Modify: `openpmtools/Sources/PMTCore/Store.swift` (`save`, `update`)
- Create: `openpmtools/Sources/PMTCore/BoardsSync.swift`
- Test: `openpmtools/Tests/PMTCoreTests/BoardsSyncTests.swift`

**Interfaces:**
- Consumes: Task 1 (`Device`, `Stamp`, `Stamps`, `Tombstones`), Task 4 (`Column.id`).
- Produces:
  - `BoardsFile.stamps: Stamps`, `BoardsFile.deleted: Tombstones`, default `[:]`, encoded only when not empty.
  - Stamp keys. Cards (open and archived alike, by card id): `card:<id>.title`, `.notes`, `.due`, `.priority`, `.place` (value: the column id, or `"archive"`), `.done`, `.fromColumn`. Columns: `column:<project>/<columnID>.name`, `column:<project>/<columnID>.order` (card id order). Boards: `board:<project>.columns` (column id order). Own projects: `own:<UUID>.name`; `file.ownOrder`.
  - Tombstone keys: `card:<id>`, `column:<project>/<columnID>`, `board:<project>`, `own:<UUID>`.
  - `public func BoardsFile.stamped(from before: BoardsFile, by device: Device, now: Date) -> BoardsFile` — same rules as `Config.stamped` (Task 2): changed or new fields get bumped stamps, removed items get tombstones and lose their stamps, 90-day pruning. `created` never changes and gets no stamp.
  - `BoardsStore.init(url:device:)` with `device: Device? = nil`, and `public func BoardsStore.save(_ file: BoardsFile, changedFrom before: BoardsFile) throws`; `update` uses it.

- [ ] **Step 1: Write the failing tests** (device `Device(id: "A", name: "Mac A")`):
  - `moveStampsPlaceOnly`: `moveCard` to another column → `card:<id>.place` stamped, title/notes not; source and destination `column:…order` stamped.
  - `archiveStampsPlaceAndDone`: moving to the last column stamps `.place` (value `"archive"`), `.done`, `.fromColumn`.
  - `editStampsChangedFields`: `editCard` title only → only `.title` stamped.
  - `deleteCardLeavesTombstone`, `removeColumnLeavesTombstone`, `deleteBoardLeavesTombstones` (board and its cards).
  - `newCardStampsAllFields`.
  - `storeUpdateStamps`: `BoardsStore.update` with a fixed device leaves the stamps in the saved file.

- [ ] **Step 2: Run** `swift test --filter BoardsSyncTests`. Expected: FAIL.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run** `swift test`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PMTCore Tests/PMTCoreTests/BoardsSyncTests.swift
git commit -m "Stamp board fields and tombstone deletes on every save"
```

### Task 6: Merge two boards files

**Files:**
- Modify: `openpmtools/Sources/PMTCore/BoardsSync.swift`
- Test: `openpmtools/Tests/PMTCoreTests/BoardsSyncTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 4, 5.
- Produces: `public func BoardsFile.merged(with other: BoardsFile) -> BoardsFile`. Rules:
  - Boards by project id; columns by `(project, column id)`; cards by id across open and archived; own projects by id. An item on one side only is kept unless the other side's tombstone is later than every stamp `at` of that item.
  - Card fields with `mergeValue`; `title` with `mergeText(join: .title)`; `notes` with `mergeText(join: .notes)`.
  - A card's `.place` decides where it goes: a column id, or the archive (then `done` and `fromColumn` from their merged fields). If the column is gone, the board's first column.
  - **Card id collision:** same id but different `created` means two different cards. Keep `self`'s card under the id; give the other card the id `<id>-<last 4 hex digits of Int(created.timeIntervalSince1970)>`, adding 1 to that number until unused. Same rule on every device, so it is deterministic.
  - Column order: the side whose `board:<project>.columns` stamp wins; columns missing from it go just before the last column. Card order in a column: the side whose `.order` stamp wins; cards missing from it go at the top (where new cards go).
  - **Two columns with the same name** (case-insensitive) after merging: keep the one whose id sorts first, move the other's cards to the top of it.
  - Column `name` with `mergeValue`; own project `name` with `mergeValue`; own order by `file.ownOrder` like the column order.
  - `stamps` and `deleted` as in Task 3.

- [ ] **Step 1: Write the failing tests** (two devices A and B, both starting from one shared file):
  - `moveAndEditBothSurvive`: A moves a card to Doing, B edits its title → merged card is in Doing with B's title.
  - `bothAddCardsBothKept`: each side adds a card to To Do → both are in To Do, at the top.
  - `cardIDCollisionKeepsBoth`: each side has a different card with id `"abc123"` → merged has 2 cards, one with id `"abc123"` and one with `"abc123-xxxx"`; the result is the same whichever side is `self`.
  - `archivedOnOneSideEditedOnOther`: A archives a card, B edits its notes → archived, with B's notes.
  - `deleteBeatsOlderEdit`, `newerEditBeatsDelete` (cards).
  - `sameNamedColumnsCollapse`: each side adds a column "Review" (different random ids) → one "Review" column with both sides' cards.
  - `oldFilesMergeWithoutDuplicates`: two copies of an old file (no ids, no stamps), each loaded and changed on a different device → no column appears twice.
  - `mergeIsIdempotent`: `m.merged(with: b) == m`, `m.merged(with: a) == m`.
  - `mergeIsSymmetric`: `a.merged(with: b) == b.merged(with: a)` when no ids collide.

- [ ] **Step 2: Run** `swift test --filter BoardsSyncTests`. Expected: the new tests FAIL.

- [ ] **Step 3: Implement** `BoardsFile.merged(with:)`.

- [ ] **Step 4: Run** `swift test`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PMTCore/BoardsSync.swift Tests/PMTCoreTests/BoardsSyncTests.swift
git commit -m "Merge two boards files item by item"
```

### Task 7: "Move to" in the Mac task editor

**Files:**
- Modify: `openpmtools/Sources/OpenPMToolsApp/CardViews.swift` (`CardDraft`, `CardEditor`, the edit sheet in `CardView`)

**Interfaces:**
- Consumes: `BoardsFile.moveCard(_:to:at:now:)` (exists).
- Produces: `CardDraft.column: String?` and `CardEditor` parameter `columns: [String]? = nil`. When `columns` is given, the editor shows a `Picker("Move to", selection: $draft.column)` listing them, the card's current column selected. The edit sheet passes the board's `columns` and `column`. On Save, if `draft.column` differs from the current column, call `moveCard(card.id, to: draft.column!)` in the same `model.update` as the field edits, after them. The last column (Done) archives the card, as `moveCard` already does. New-task editors pass no `columns`, so they do not change.

- [ ] **Step 1: Implement** the Interfaces block.

- [ ] **Step 2: Build and run** `scripts/make-app.sh`, then `open build/OpenPMTools.app`. Check by hand: open a task, pick another column in "Move to", Save → the card is in that column. Pick Done → the card leaves the board and shows in search with "Done". Cancel → nothing moves. Expected: all three behave so.

- [ ] **Step 3: Run** `swift test`. Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenPMToolsApp/CardViews.swift
git commit -m "Add Move to column choice to the task editor"
```

### Task 8: Docs

**Files:**
- Modify: `openpmtools/README.md` (task editor paragraph: "Move to"), `frequent-finder/README.md` (one line: `~/.config/frequent-finder/device.json` names this Mac for sync; do not copy it to another Mac).

- [ ] **Step 1: Edit both READMEs** as above.
- [ ] **Step 2: Commit** in each repo: `git commit -am "Document Move to and the device file"`.

## Later plans (not in this plan)

- **Part 2, after the developer account and the iCloud spike:** split per-Mac fields into `local.json`, move the shared files to the iCloud folder, run `merged(with:)` on iCloud conflict versions (or switch to per-device files), point the backup script and watchers at the new folder.
- **Part 3:** the iOS/iPadOS app.

## Carry into Part 2 (from part 1 execution)

- Divider text is now `— Also edited on <by>, <yyyy-MM-dd HH:mm> UTC —` (UTC, for determinism).
- When saving a merged result, stamp against the merge result, never against the local pre-merge file.
- The one-time migration merges ALL Macs' unstamped copies before the first stamped save (a joined unstamped text beats a later unstamped copy).
- Every app and CLI must be a stamping build before sync is turned on: older builds strip `stamps`, `deleted` and column ids on save, which resets version vectors. Consider a `formatVersion` key.
- Tie the device id to the hardware UUID, so a Migration Assistant / Time Machine copy of `device.json` gets a new id.
- `Device.load` first-run race (two processes at once) can make two ids; harmless, but `.withoutOverwriting` would close it.
- Consider making the non-stamping `BoardsStore.save(_:)` / `ConfigStore.save(_:)` internal.
- Accepted: in a rare id-collision race, a deleted card can come back (never lost).
