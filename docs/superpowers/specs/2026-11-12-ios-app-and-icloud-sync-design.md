# iOS/iPadOS app and iCloud sync: design

Date: 2026-11-12

## Why

The user is away from the Mac (for example at a cafe) and wants to know: "How much work is waiting? Can I stay
longer?" Today the boards and project notes exist only on the Mac. The user also wants to make small changes away
from the Mac: add a task, move a task to another column, and edit project notes.

## What gets built

1. **Sync.** `projects.json` (FrequentFinder) and `boards.json` (OpenPMTools) move into an iCloud Drive folder.
   Every Mac app, `ff`, `pmt` and the iOS app read and write them there.
2. **A merge that never loses data.** When two devices save different copies of a file, the copies are merged
   item by item. No edit is silently dropped.
3. **One iOS/iPadOS app** (SwiftUI) that shows the OpenPMTools boards plus FrequentFinder notes and web links.
4. **A "Move to" column choice in the task editor**, on the Mac and on iOS.

## Goals

- iPhone: a fast look at the work in one column of one project.
- iPhone and iPad: add a task, move a task to a column (Done archives it, as on the Mac), edit a task.
- iPhone and iPad: read and edit a FrequentFinder project's notes (basic Markdown, Edit button, saved as you type,
  same as the Mac). See its web links; tapping one opens Safari.
- iPad: looks like the Mac OpenPMTools window: projects on the left, the full board on the right, and the Big Board.
- Works offline. Changes sync and merge when the device is online again.

## Non-goals

- No key files, folders, repos, git status, Finder, Terminal or Linked Apps on iOS. Mac paths mean nothing there.
- No adding, removing or renaming projects on iOS (user's call: do that on the Mac). Board setup (columns) also
  stays Mac-only (builder's call, same reason).
- No CloudKit or database. The user chose to keep the JSON files.
- No App Store release. The app is installed on the user's own devices from Xcode.

## Anti-goals (a failure even if it works)

- **Any data loss.** The user said: "No app should be designed for data loss." This is the hard rule. If a merge
  cannot decide, it keeps both versions.
- Breaking `ff`, `pmt`, the daily backup script, or the live updates between the two Mac apps.
- iPhone screens that try to show the whole board or the Big Board. They do not fit.

## Decided by the user

- Sync: iCloud Drive (not Dropbox). The user will get a paid Apple Developer account.
- One native SwiftUI app for iPhone and iPad that reuses `PMTCore` and `FFCore` (not a web app).
- Keep the JSON files and add a merge (not CloudKit).
- iPhone flow: project list → pick a project → pick a column (for example Doing) → that column's tasks as a list.
  Tap a task to open it; the task editor has "Move to".
- The Mac task editor gets the same "Move to" choice.
- FrequentFinder projects on iOS show notes (editable) and URLs, not files or folders.
- iPad looks like the Mac app, including the Big Board.

## Sync design

### Where the files go

- One iCloud container shared by all the apps. Builder's call for the id: `iCloud.org.hyland-wood.pmtools`.
- On the Mac this is the folder `~/Library/Mobile Documents/iCloud~org~hyland-wood~pmtools/Documents/`.
  The files go in it as `projects.json` and `boards.json`.
- `ConfigStore.defaultURL` and `BoardsStore.defaultURL` change to that folder. `FF_CONFIG` and `PMT_CONFIG` still
  override it (tests depend on this).
- One-time move on the Mac: if the old file in `~/.config/...` exists and the new one does not, copy it across and
  leave the old file in place, renamed `*.moved-to-icloud`. Never delete user data.
- `FileManager.homeDirectoryForCurrentUser` does not exist on iOS. On iOS the stores get their URL from
  `FileManager.url(forUbiquityContainerIdentifier:)`.
- The daily backup script (in the OpenPMTools README) changes to copy from the new folder.
- The Mac apps already watch the data folder for atomic saves. Point the watchers at the new folder.

### Shared data and per-Mac data

The user has more than one Mac on the same Apple ID. So some of `projects.json` must not sync:

- **Shared (in iCloud):** each project's `id`, `name`, `urls`, `active`, `notes`. Everything in `boards.json`.
- **Per Mac (stays in `~/.config/frequent-finder/local.json`, never synced):** each project's `path`, `keyFiles`
  and `repos`, keyed by project id; the `terminal` choice; `linkedApps`. (OpenPMTools' linked apps are already in
  UserDefaults, which is per Mac.)
- `FFCore` joins the two into the `Project` and `Config` values the apps use today, and splits them on save.
- A Mac where a project has no local folder shows it like iOS does: notes and links, no git status. The user can add
  that Mac's own folder, files and repos in Settings or with `ff`.
- One-time move on each Mac: the per-Mac fields from that Mac's old `projects.json` go to its `local.json`; the
  shared fields go to iCloud. The first Mac's file goes up as is. A later Mac's projects are merged in by id; a
  project with the same name but a different id is matched by name (my call), its local fields are kept under the
  shared id, and any board for its old id is moved to the shared id. Nothing is dropped: if two boards collide,
  the cards of both are kept.

### Merge rules

Every **field** that can change gets its own modified time (for example a `modified: [String: Date]` map per item,
keyed by field name). Per-item times are not enough: the phone setting a card's due date and the Mac changing its
priority must both survive. Every delete leaves a marker (a "tombstone": the id and the time it was deleted), so a
merge does not bring the item back.

- Items: FrequentFinder projects; OpenPMTools own projects, boards, columns, cards and archived cards.
- Same id on both sides: merge field by field. For each field, the newer time wins.
- Exception, text that people type (project notes, card notes, card titles): if both sides changed it and the texts
  differ, keep both, one after the other, with a short divider line that says which device and time the second one
  came from (titles: joined with " / "). Builder's call: if the last common version is not known, treat any
  difference where both sides have a time after the last sync as a conflict.
- An item on only one side: keep it, unless the other side has a newer tombstone for it.
- Delete against edit: a delete newer than every edit removes the item (that is what the user asked for). An edit
  newer than the delete brings the item back with the edit, so the edit is not lost (my call).
- A card is in exactly one place (one column or the archive). The card's newest `modified` decides where.
- Order of cards in a column: keep the newer side's order, then add cards that only the other side has.
- Tombstones older than 90 days can be dropped (builder's call).
- Old files without `modified` load with `modified` = the distant past, so any real edit beats them.

The merge is a pure function: `merge(a, b) -> merged`, in `FFCore` for `Config` and in `PMTCore` for `BoardsFile`.
It must be tested well, with one test per rule above.

### When the merge runs

iCloud keeps the losing copies of a file as conflict versions (`NSFileVersion.unresolvedConflictVersionsOfItem`).
Before every load (in the apps and in `ff` and `pmt`), merge any conflict versions into the current file, save it,
and mark the conflicts resolved. Read and write through `NSFileCoordinator` so iCloud never sees a half-written
file.

**Risk to check first (spike):** it is not certain that an unsigned or non-sandboxed Mac command-line tool
(`ff`, `pmt`) sees conflict versions for a file in iCloud Drive. Check this before building the rest. Make a
conflict on purpose (edit on the Mac and the phone while the phone is offline) and see what each tool sees.
The spike also covers the Mac apps: today `make-app.sh` signs them ad hoc (`codesign --sign -`), with no team and no
entitlements, so they reach the folder by path, the same as the CLIs. Also check that the container folder appears
and keeps syncing on the Mac when no Mac process holds the iCloud entitlement. If it does not, the Mac apps must be
signed with the team and an iCloud entitlement (a provisioning profile embedded by `make-app.sh`, or Xcode
projects).

Other things the builder must handle (my calls): a file iCloud has not downloaded yet must never be read as empty
and then saved over (wait for the download, or refuse to save). Card ids are 6-hex prefixes today, unique only in
one file: new cards made on iOS need ids that cannot collide with the Mac's (for example a longer random id).
Columns are matched by name today; give them ids so a rename on one device and an edit on another merge correctly.

**Fallback if it does not work:** each device writes only its own file (for example `boards.<device-id>.json`),
and every reader loads all of them and merges with the same `merge` function. This cannot conflict at the file
level. The merge rules stay the same.

## Code changes

### Shared core (`FFCore`, `PMTCore`)

- Add `.iOS(.v18)` to `platforms` in both `Package.swift` files.
- Put Mac-only code behind `#if os(macOS)`: git (`Git.swift`, `Process.swift`), `Launcher`, linked-app scheme
  reading, the CLIs. The iOS app needs only the models, the stores, `BoardOps`, `Catalog`, `Due`, and the merge.
- Add `modified` and tombstones to the models, and set `modified` in every operation that changes an item
  (`BoardOps`, `Commands`, the apps' edit paths). Keep reading old files.

### Mac

- `CardEditor` (in `Sources/OpenPMToolsApp/CardViews.swift`) gets a "Move to" picker listing the board's columns.
  Picking the last column (Done) archives the card, as moving a card there already does.

### iOS app

- An Xcode project (SwiftPM alone cannot build an iOS app). Builder's call: put it in this repo as `iOS/`, using
  the two packages as local dependencies. Bundle id `org.hyland-wood.OpenPMTools.iOS`, iCloud capability with the
  container above.
- The sidebar list matches the Mac: FrequentFinder's active projects, then My Projects.
- iPhone (compact width): `NavigationStack`. Project list → project screen (its columns with task counts, its
  notes, its web links) → column screen (task list) → task editor. No drag and drop; "Move to" does that job. Each
  task row shows title, priority and the due label, as on the Mac card.
- iPad (regular width): `NavigationSplitView` with the sidebar and the board, plus the Big Board, reusing the Mac
  views' behaviour (drag and drop works on iPad).
- New task: a + button on the project and column screens.
- The app reloads when iCloud reports that a file changed (`NSMetadataQuery` or `NSFilePresenter`) and when it
  comes to the front.
- Shared view code with the Mac app is welcome but not required. AppKit code (`NSWorkspace`, `NSWindow`) stays Mac
  only.

## Left to the builder

- How to share SwiftUI view code between the Mac app and the iOS app.
- Exact layout and look of the iPhone screens, inside the flow above.
- The divider text for kept-both notes.
- How to show sync state (for example "Not synced yet") if it turns out to be needed.

## Order of work

1. Per-field modified times, tombstones, column ids and `merge` in the cores, with tests. This needs no developer
   account, so it can start first.
2. Spike, once the developer account is active: iCloud conflict versions as seen by `ff`, `pmt` and the Mac apps
   (decides merge-on-conflict vs. per-device files, and whether the Mac apps need an entitlement).
3. Move the data files to the iCloud folder; Mac apps, CLIs and backup script follow.
4. "Move to" in the Mac task editor.
5. iOS app: iPhone flow, then iPad layout.
