# Due dates, priorities, and New Task: design

Agreed with David on 2026-11-11 (grilling session). Covers the five "Doing" cards on the OpenPMTools board:
due dates, priorities, priority from due date, colour by due date, and the New Task shortcut.

## Due dates
- A due date is a day only, no time. Saved as `"2026-11-14"`.
- Set in the task editor (with an on/off switch) or with `pmt ... --due 2026-11-14`; `--due none` removes it.

## Priority
- Levels: None, Low, Medium, High. Set in the editor or with `--priority low|medium|high|none`.
- The due date raises priority. Due today or overdue: at least High. Due tomorrow or the day after: at least Medium.
  Computed each time, never saved. Priority never goes down. Removing the date returns the set priority.
- Card icon: Low `↓`, Medium `!`, High `!!`, None nothing. If the date raised it, tooltip "Raised: due soon".
  VoiceOver reads "High priority".

## Colour
- A stripe along the top of the card, and the due date as a small label in the same colour.
- Red: due today or overdue. Overdue also shows ⚠︎.
- Yellow: due tomorrow or the day after.
- Green: due later.
- None: no due date, or the task is done.
- Colour is never the only signal (HIG). The date label always has a symbol and words, and VoiceOver reads the words:
  overdue `exclamationmark.triangle.fill` "Overdue · 12 Nov"; today `clock.badge.exclamationmark` "Today";
  tomorrow / day after `clock` "Tomorrow" / "In 2 days"; later `calendar` "20 Nov". Done tasks: plain date, no symbol.

## Sorting
- Cards in a column show sorted by effective priority (High first), then due date (earliest first, none last),
  then the saved (drag) order. Display only: the file keeps the drag order.
- The Big Board uses the same sort; ties keep board order, then card order. The Done column is not sorted.
- Dropping a card onto a card gives it that card's effective priority (saved as its own). Due date unchanged.
  Dropping on empty space keeps its priority and puts it last in saved order. Same on project boards and the
  Big Board, also across columns, also onto another project's card on the Big Board.
- When a drop changes a priority, VoiceOver says "Priority changed to High". Nothing else shows.
- Colours and raised priorities update at midnight and when the app becomes active.

## New Task
- ⌘N: New Task…; ⇧⌘N: New Project….
- A new task is saved first in the first column, so it shows at the top of its priority group. The column "+"
  button also saves new tasks first in its column.
- On the Big Board the New Task sheet has a Project menu, starting on the project used last.
- ⌘N is disabled when no project with a board is selected (main window) or there are no boards (Big Board).

## Other
- Done tasks keep due date and priority; restoring brings them back. Done tasks show no colour.
- `pmt board`, `pmt task show`, and `--json` show due date and priority; `task show` says when priority was raised.
- Search results show the stripe colour, date label, and priority icon.
- Tasks saved before this change have no date and no priority.
