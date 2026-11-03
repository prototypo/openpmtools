# OpenPMTools design

Date: 2026-11-03

## Intent

David is about to launch a book, *Breakthrough*. The launch has many tasks, and he is losing track of which are done
and which are still to do. OpenPMTools is a personal Kanban board for macOS. It shows his projects on the left and
the selected project's board on the right.

It is a companion to FrequentFinder (`/Users/davidhyland-wood/Documents/GitHub/frequent-finder`), which tracks his
projects and their files. The two apps work together, but each also works alone.

## Goals

- A native macOS app, **OpenPMTools**, that follows Apple's Human Interface Guidelines.
- A command-line tool, **`pmt`**, that can do everything the app does to boards and tasks.
- Projects on the left, in the same style as FrequentFinder's All Projects window.
- FrequentFinder projects appear in OpenPMTools without any action from the user, and follow FrequentFinder changes
  live.
- Projects that exist only in OpenPMTools ("own projects"), so the app is useful without FrequentFinder.
- Dragging an own project onto FrequentFinder makes it a FrequentFinder project, and its board stays with it.
- Moving a task into Done plays a "puff of smoke" animation, and the task is archived, not deleted.
- Search across all projects, with an option to include done (archived) tasks. A done task can be read and restored.

## Non-goals

- No due dates, labels, priorities, assignees, or attachments. A task is a title and short notes.
- No sync, no accounts, no sharing. One person, one Mac.
- No menu bar icon. OpenPMTools is a normal Dock app.
- OpenPMTools never edits FrequentFinder projects, except the one case of the drag-to-add.

## Anti-goals (failure even if it works)

- Losing a task. Every remove path must be deliberate. Done means archived, not gone.
- Damaging FrequentFinder's `projects.json`. OpenPMTools reads it; it writes it only through FrequentFinder's own
  safe-update code (see "Drag to FrequentFinder").
- A board UI that feels like a web page. It must feel like a Mac app.

## Constraints

- macOS 15 or later, Swift 6 toolchain, SwiftUI. Swift Package Manager only (no Xcode project), like FrequentFinder.
- New code lives in this repo: `/Users/davidhyland-wood/Documents/GitHub/openpmtools`.
- Follow FrequentFinder's layout and habits so the two codebases read alike:
  - `Package.swift` with a core library target (`PMTCore`), an executable `pmt`, an app executable `OpenPMTools`,
    and a test target for the core.
  - `scripts/make-app.sh` builds `build/OpenPMTools.app` and installs `pmt` to `~/.local/bin`. `--install` also
    copies the app to `/Applications`.
  - JSON store with atomic writes, a "re-read, change, save only if changed" update function, and a folder watcher
    so the app follows changes made by `pmt` (see `Sources/FFCore/Config.swift` and `Sources/FFApp/AppModel.swift`
    in FrequentFinder).
  - Clear errors: a file that cannot be parsed blocks edits instead of being overwritten.

## Decided by David

- App name: **OpenPMTools**. CLI name: **`pmt`**.
- A task has a **title** and **short notes**. Nothing else.
- A new board is made by naming its columns.
- **The last column is always Done.** Whatever it is called, a card dropped there goes away in a puff of smoke and
  is archived. The Done column is always empty on screen; it is a drop target.
- FrequentFinder projects appear as soon as they are created in FrequentFinder, and you can make a board for them.
- Own projects can be created in OpenPMTools without FrequentFinder.
- An own project can be dragged onto the FrequentFinder interface to add it there.
- A done task found by search can be read, and can be restored.

## Data

### Where things are stored

- OpenPMTools data: `~/.config/openpmtools/boards.json`, or `$PMT_CONFIG` if set. (Claude's call, mirrors
  `$FF_CONFIG`.)
- FrequentFinder data: read from FrequentFinder's own location (`$FF_CONFIG` or
  `~/.config/frequent-finder/projects.json`). If the file is missing, there are simply no FrequentFinder projects
  and no error is shown.

### Shape (Claude's call)

```
boards.json
  ownProjects: [ { id: <UUID>, name } ]
  boards: [
    { project: <project UUID>,
      columns: [ { name, tasks: [ { id, title, notes?, created } ] } ],   // last column always has no tasks
      archive: [ { id, title, notes?, created, done, fromColumn } ] }
  ]
```

- **Every project has a UUID (decided by David).** A board belongs to a project **by UUID**, so renaming a project
  in either app never disconnects its board.
  - FrequentFinder projects get a new `id: UUID` field in `projects.json`. A project with no `id` (every existing
    one today) gets a new UUID when loaded, and `ConfigStore.load` saves the file once if it had to add any, so
    the ids are stable from then on. This must not change anything else in the file.
  - Own projects get a UUID when created.
- People still type **names** in `pmt` and see names in the app. A name is resolved to a UUID without regard to
  case, like FrequentFinder's `Config.index(of:)`. Two projects with the same name (one in each app) are handled
  under "Project list rules".
- Task `id` is stable and short enough to type in `pmt` (for example the first 6 hex digits of a UUID, longer if
  there is a clash). The builder chooses the exact form.
- Archived tasks stay in their board's `archive`. Deleting a board deletes its archive too (CLI asks for `--force`
  if it has tasks).

### Project list rules (Claude's calls)

- The sidebar has two sections: **FrequentFinder** (its active projects, in its order) and **My Projects** (own
  projects).
- Inactive FrequentFinder projects are hidden, as in FrequentFinder. Their boards are kept.
- FrequentFinder projects show their git status symbol, like FrequentFinder's sidebar.
- If a UUID exists in both FrequentFinder and own projects, it shows once, under FrequentFinder. The own-project
  entry is removed on the next save. This is what makes drag-to-add "move" the project.
- Names must be unique across both lists. Creating an own project with a name FrequentFinder already uses is
  refused. If FrequentFinder later gains a project with the same name as an own project (different UUID), both
  show, and `pmt` asks the user to rename one before it accepts that name.
- A board whose project no longer exists anywhere (for example, a FrequentFinder project was removed) is not lost.
  `pmt board list` shows it as orphaned, and `pmt board attach <board-project-id> <project-name>` connects it to
  another project. The app does not need a UI for this in the first version.

## Reusing FrequentFinder code (Claude's call)

OpenPMTools needs to read FrequentFinder's config and get git status. FrequentFinder's `FFCore` already does both
(`Config`, `ConfigStore`, `Git`, `GitStatus.combine`). Reuse it instead of copying it:

- In FrequentFinder, add a library product for `FFCore` in its `Package.swift`.
- In FrequentFinder, add the project `id` (see "Data"). Its `ff list --json` shows it. `ff add` creates one, and
  accepts `--id <UUID>` so a project can be added with a known id (used by drag-to-add).
- OpenPMTools depends on it by local path: `.package(path: "../frequent-finder")`.
- `GitSymbol` (status to SF Symbol and colour) is private app code in FrequentFinder's `MenuContent.swift`. Do not
  move it. Copy its ~20 lines into OpenPMTools' app target. Keep FrequentFinder's change small.

This means building OpenPMTools needs the FrequentFinder repo next to it, with the `FFCore` product on its `main`.
Running OpenPMTools does not need FrequentFinder to be installed or running.

**Order of work:** the FrequentFinder change comes first. Start a branch from FrequentFinder's `main`, open a PR,
and have David merge it to `main` before the OpenPMTools build depends on it. Then build and reinstall
FrequentFinder (`scripts/make-app.sh --install`) so drag-to-add works.

## The app

### Window

- One main window: `NavigationSplitView`. Sidebar = projects. Detail = the selected project's board.
- Remembers its size, place, and selected project across launches.
- Toolbar: a search field (⌘F), and in the sidebar a "+" button to add an own project. File > New Project… does
  the same.

### No board yet

- The detail area says the project has no board, and shows an editable list of column names, pre-filled with
  "To Do", "Doing", "Done". You can add, remove, rename, and reorder columns. A note says the last column is Done.
- "Create Board" makes it. At least two columns are needed (one working column plus Done).

### Board

- Columns side by side, scrolling sideways if there are many.
- Each card shows the title and the notes (notes cut short to a few lines on the card).
- Drag a card to another column, or up and down within a column to reorder it.
- Drop a card on the last (Done) column: a puff-of-smoke animation plays where it was dropped, and the card is
  archived. macOS has this animation built in (`NSAnimationEffect.disappearingItemDefault`, the Dock "poof").
  Use it unless it looks wrong in practice.
- A "+" at the top of each working column adds a task. Clicking a card opens it for editing (title and notes).
  Delete is in the card's context menu and asks for confirmation.
- Card context menu also has "Move to" with each column, so tasks can be moved without dragging (accessibility).
- Columns can be added, renamed, reordered, and removed later (from a board menu or column header menu). A column
  that still has tasks cannot be removed. The Done column can be renamed but stays last.

### Search

- The toolbar search field looks at task titles and notes in all projects, case-insensitive. "All" includes
  boards with no sidebar row (inactive FrequentFinder projects and orphaned boards), so no task is out of reach.
  Clicking such a task shows its board in the detail area with no sidebar row selected. `pmt search` does the same.
- An "Include Done" toggle next to the field adds archived tasks.
- Results replace the detail area while searching. Each result shows the title, project, and column (or "Done").
- Clicking an open task goes to its board and highlights the card.
- Clicking a done task shows it read-only with a **Restore** button. Restore puts it back at the bottom of the
  first column (Claude's call; the column it left from is kept in `fromColumn` in case this should change).

### HIG checklist

- Standard menus (File, Edit, View, Window, Help), standard shortcuts, ⌘, not needed (no settings in v1).
- Works in light and dark mode, uses system colors and SF Symbols.
- Every control has an accessibility label. Card moves are possible without dragging.
- Undo (⌘Z) for task moves, archives, and deletes is wanted if SwiftUI's `UndoManager` makes it cheap. Restore from
  search covers archive in any case.

## Drag to FrequentFinder

- In OpenPMTools, an own project row in the sidebar can be dragged.
- The drag carries the project's UUID and name, as a small custom type (for example JSON under a
  `org.hyland-wood.openpmtools.project` type). Plain text of the name may be added too, for other drop targets.
- **FrequentFinder change:** its All Projects window sidebar accepts the drop and adds a project with that UUID,
  that name, and no folder, through `ConfigStore.update`. If the UUID already exists, nothing changes. If only the
  name already exists, the drop is refused with a clear message. This is done on a branch in the FrequentFinder
  repo.
- After the drop, OpenPMTools sees FrequentFinder's file change, shows the project under FrequentFinder, and drops
  the own-project entry. The board stays, because it is matched by UUID.

## The `pmt` command

Same style as `ff`: plain text output by default, `--json` where a list is printed, clear error messages, non-zero
exit on error. Suggested commands (builder can adjust names, but not drop abilities):

```
pmt projects [--json]                         list all projects (FrequentFinder and own), with board yes/no
pmt project add <name>                         add an own project
pmt project remove <name>                      remove an own project (its board too, needs --force if it has tasks)
pmt project rename <name> <new>                rename an own project (FrequentFinder projects: use ff rename)

pmt board <project> [--json]                   show the board: columns and tasks with ids
pmt board create <project> <col> <col>...     create a board; the last column is Done
pmt board delete <project> [--force]
pmt board list [--json]                        all boards with project id, marking orphaned ones
pmt board attach <project-id> <project-name>   connect an orphaned board to another project

pmt column add <project> <name> [--at N]
pmt column rename <project> <name> <new>
pmt column move <project> <name> <N>
pmt column remove <project> <name>             refused if it has tasks

pmt task add <project> <title> [--notes "..."] [--column <name>]   default: first column
pmt task edit <id> [--title "..."] [--notes "..."]
pmt task move <id> <column>                    moving to the last column archives it
pmt task done <id>                             same as moving to Done
pmt task delete <id>
pmt task restore <id>
pmt task show <id>

pmt search <text> [--done] [--json]
```

## Testing

- Core logic in `PMTCore` has unit tests, like FrequentFinder's `FFCoreTests`: store load/save/update, board and
  task operations (including "move to last column archives"), restore, search, project-list merging with
  FrequentFinder, and CLI parsing.
- FrequentFinder gets tests for the new `id`: an old file without ids loads, gets ids, is saved once, and keeps
  the same ids on the next load; nothing else in the file changes.
- Tests use temp files via `PMT_CONFIG` / `FF_CONFIG`, never the real ones.
- The UI is checked by running the app.

## Left to the builder

- Exact task id format, file layout inside `Sources/`, and view breakdown.
- App icon (can be made the same way as FrequentFinder's `scripts/make-icon.swift`).
- Exact look of cards and columns, within the HIG.
- Whether the smoke animation needs anything beyond the built-in poof.
