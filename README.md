# OpenPMTools

A personal Kanban board for macOS. It shows your projects on the left and the selected project's board on the right.
Tasks move across columns; moving one into the last column (Done) archives it, so it can still be found and restored.
It is a companion to [FrequentFinder](../frequent-finder): FrequentFinder's active projects appear automatically
and follow its changes live, and projects that exist only in OpenPMTools ("My Projects") make it useful on its own.
Drag a project from My Projects onto FrequentFinder's All Projects window to make it a FrequentFinder project; its
board stays with it. The `pmt` command does everything the app does to boards and tasks.
The Big Board toolbar button opens a window with every open task from every project. Columns with the same name are
merged, and each card shows its project's name and colour. A card can only move to a column its own board has.

![A board with To Do, Doing, Waiting and Done columns](docs/images/board.png)

## Working with FrequentFinder

FrequentFinder's active projects show up in the sidebar under their own section, with their boards, and renames follow live.
To add one, drag a project from My Projects onto the sidebar of FrequentFinder's All Projects window; its board goes with it.
This needs FrequentFinder on its `main` branch (projects there have ids, which boards are matched by).

## Build and install

Needs macOS 15 or later, Xcode (or the Swift toolchain), and the FrequentFinder repo checked out next to this one
(`../frequent-finder`).

```bash
scripts/make-app.sh            # builds build/OpenPMTools.app and installs ~/.local/bin/pmt
scripts/make-app.sh --install  # also copies the app to /Applications
```

Make sure `~/.local/bin` is on your `PATH`.

## Command line

```
$ pmt help
Usage:
  pmt projects [--json]
  pmt project add <name>
  pmt project remove <name> [--force]
  pmt project rename <name> <new>
  pmt board <project> [--json]
  pmt board create <project> <column> <column>...   (the last column is Done)
  pmt board delete <project> [--force]
  pmt board list [--json]
  pmt board attach <project-id> <project-name>
  pmt column add <project> <name> [--at N]
  pmt column rename <project> <name> <new>
  pmt column move <project> <name> <N>
  pmt column remove <project> <name>
  pmt task add <project> <title> [--notes "..."] [--column <name>]
  pmt task edit <id> [--title "..."] [--notes "..."]
  pmt task move <id> <column>
  pmt task done <id>
  pmt task delete <id>
  pmt task restore <id>
  pmt task show <id>
  pmt search <text> [--done] [--json]
  pmt help
Positions (--at, column move) count from 1.
Data file: ~/.config/openpmtools/boards.json (override with PMT_CONFIG)
```

## Data file

`~/.config/openpmtools/boards.json` (set `PMT_CONFIG` to use another file) holds your own projects and every
board. Boards are matched to projects by id, so renaming a project keeps its board. FrequentFinder's
`~/.config/frequent-finder/projects.json` (or `FF_CONFIG`) is read for its projects. The app reloads both when
they change.

## Development

```bash
swift test
swift scripts/make-icon.swift   # redraws Resources/AppIcon.icns
```
