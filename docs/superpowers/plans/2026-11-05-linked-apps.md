# Linked Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open an OpenPMTools board from FrequentFinder, and a FrequentFinder project from OpenPMTools, with neither app naming the other in code.

**Architecture:** Each app owns a URL scheme and opens `<scheme>://project/<uuid>`. Each app keeps its own list of Linked Apps (bundle id, name, scheme). You add an app by dropping it from Finder (or with Add App…). The scheme is read from the dropped app's Info.plist. Each project shows one "Open in <name>" button per linked app that is installed. Shared, app-neutral code (`LinkedApp`) lives in FFCore, which OpenPMTools already depends on.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftUI, AppKit (`NSWorkspace`), Swift Testing, SwiftPM, macOS 15+.

**Spec:** No separate spec. The decisions below come from the conversation of 2026-11-05 and are the spec.

## Decisions (the spec)

- Option 1 of the discussion: custom URL schemes, no other coupling.
- FrequentFinder: Linked Apps is a section in **Settings**, for all projects (answer 1A).
- OpenPMTools: a new **Settings** window (⌘,) with a Linked Apps list.
- In both: you drag **an app** (from Finder or the Dock) onto Linked Apps to add it (answer 2A).
- Neither app's source names the other app. The only shared contract is the URL format.

## Global Constraints

- Schemes: `frequentfinder` (FrequentFinder), `openpmtools` (OpenPMTools). Declared in each `scripts/make-app.sh` Info.plist as `CFBundleURLTypes` → `CFBundleURLSchemes`.
- Link format: `<scheme>://project/<UUID>`; host `project`, path `/<UUID>`, UUID case-insensitive on input, lowercase on output. Anything else is ignored.
- A linked app is opened with `open -b <bundleID> <link>` (FFCore `Launcher.open`), so the link goes to that app even if another app claims the scheme.
- An app with no `CFBundleURLTypes` scheme cannot be linked: error `"<App name> cannot open project links."`. The first scheme of the first URL type is used.
- An app cannot link itself: error `"<App name> is this app."`.
- FrequentFinder stores `linkedApps` in `projects.json` (`Config`, next to `terminal`). OpenPMTools stores it in UserDefaults key `linkedApps` (JSON). Missing = empty list.
- The "Open in" button shows only when `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` finds the app.
- Bundle ids: `org.hyland-wood.FrequentFinder`, `org.hyland-wood.OpenPMTools`.
- Tests never touch real config files or real defaults.
- No changes to `ff` or `pmt` CLIs.

## Review Focus

1. **A link with an id the app does not know** (an OpenPMTools-only project opened in FrequentFinder, or a deleted project). Expected: a clear message "No project with this link." and no empty or broken window. Pinned by `projectIDRejectsBadLinks` (Task 1) plus the hand checks in Tasks 2 and 4.
2. **A link arrives while the app is not running, or has no windows open.** Expected: exactly one window, showing that project. Pinned by the hand checks in Tasks 2 and 4.
3. **The linked app is later deleted from the Mac.** Expected: its button hides; Settings still lists it, marked "Not installed", with a remove button. Pinned by the hand check in Task 3 and Task 5.
4. **Dropping a non-app file or an app with no scheme.** Expected: the drop is refused with the error above, and the list does not change. Pinned by `linkedAppFromAppWithoutSchemeThrows` (Task 1).
5. **Dropping the same app twice.** Expected: one entry; the name and scheme are refreshed from the app. Pinned by `addLinkedAppReplacesSameBundleID` (Task 1).

---

### Task 1: `LinkedApp` in FFCore (frequent-finder repo)

**Files:**
- Create: `Sources/FFCore/LinkedApp.swift`
- Modify: `Sources/FFCore/Config.swift` (add `linkedApps` to `Config`, decode with default `[]`)
- Modify: `Sources/FFCore/Errors.swift` (add `case notLinkable(String)`, `case linkedSelf(String)`)
- Test: `Tests/FFCoreTests/LinkedAppTests.swift`

**Interfaces:**
- Produces:
  - `public struct LinkedApp: Codable, Hashable, Sendable { public var bundleID: String; public var name: String; public var scheme: String }`
  - `public init(appAt url: URL) throws` — reads `Contents/Info.plist`: `CFBundleIdentifier`, name from `CFBundleDisplayName` ?? `CFBundleName` ?? file name without `.app`, scheme from `CFBundleURLTypes[0].CFBundleURLSchemes[0]`. Throws `FFError.notLinkable(name)` when any is missing.
  - `public func link(to project: UUID) -> URL` → `<scheme>://project/<uuid lowercased>`
  - `public static func projectID(in url: URL, scheme: String) -> UUID?`
  - `extension Array where Element == LinkedApp`: `public mutating func add(_ app: LinkedApp, selfBundleID: String?) throws` (replaces an entry with the same `bundleID`, keeps its place; throws `.linkedSelf(name)` when `app.bundleID == selfBundleID`) and `public mutating func remove(bundleID: String)`. Both apps use these.
  - `Config.linkedApps: [LinkedApp]`.
  - `public func open(_ project: UUID) throws` on `LinkedApp` → `Launcher.open("-b", bundleID, link(to: project).absoluteString)`.

- [ ] **Step 1: Write the failing tests**

Helper: `makeApp(name:, bundleID:, schemes: [String]?) -> URL` writes a temp `<name>.app/Contents/Info.plist`.

```swift
@Test func linkedAppReadsInfoPlist() throws {
    let app = try LinkedApp(appAt: makeApp(name: "Boards", bundleID: "org.example.Boards", schemes: ["boards", "other"]))
    #expect(app == LinkedApp(bundleID: "org.example.Boards", name: "Boards", scheme: "boards"))
}
@Test func linkedAppFromAppWithoutSchemeThrows() throws {
    #expect(throws: FFError.notLinkable("Plain")) { try LinkedApp(appAt: makeApp(name: "Plain", bundleID: "org.example.Plain", schemes: nil)) }
}
@Test func linkRoundTrips() {
    let id = UUID(), app = LinkedApp(bundleID: "b", name: "B", scheme: "boards")
    #expect(app.link(to: id).absoluteString == "boards://project/\(id.uuidString.lowercased())")
    #expect(LinkedApp.projectID(in: app.link(to: id), scheme: "boards") == id)
    #expect(LinkedApp.projectID(in: URL(string: "boards://project/\(id.uuidString)")!, scheme: "BOARDS") == id)
}
@Test func projectIDRejectsBadLinks() {
    for s in ["boards://project/nope", "boards://board/\(UUID())", "other://project/\(UUID())",
              "boards://project/\(UUID())/extra", "boards://project/"] {
        #expect(LinkedApp.projectID(in: URL(string: s)!, scheme: "boards") == nil, "\(s)")
    }
}
@Test func addLinkedAppReplacesSameBundleID() throws {
    var apps: [LinkedApp] = []
    try apps.add(LinkedApp(bundleID: "b", name: "Old", scheme: "x"), selfBundleID: "me")
    try apps.add(LinkedApp(bundleID: "c", name: "C", scheme: "c"), selfBundleID: "me")
    try apps.add(LinkedApp(bundleID: "b", name: "New", scheme: "y"), selfBundleID: "me")
    #expect(apps.map(\.name) == ["New", "C"])
    #expect(throws: FFError.linkedSelf("Me")) { try apps.add(LinkedApp(bundleID: "me", name: "Me", scheme: "m"), selfBundleID: "me") }
    apps.remove(bundleID: "b")
    #expect(apps.map(\.name) == ["C"])
}
@Test func configWithoutLinkedAppsDecodes() throws {
    let c = try JSONDecoder().decode(Config.self, from: Data(#"{"terminal":"iterm","projects":[]}"#.utf8))
    #expect(c.linkedApps.isEmpty)
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter LinkedAppTests` → "cannot find 'LinkedApp' in scope".
- [ ] **Step 3: Implement** the Interfaces above. Error text: `.notLinkable(n)` → `"\(n) cannot open project links."`, `.linkedSelf(n)` → `"\(n) is this app."`. `projectID` uses `URLComponents`: scheme compared case-insensitively, host == `project`, path components exactly `["/", <uuid>]`.
- [ ] **Step 4: Run, expect PASS** — `swift test` → all tests pass.
- [ ] **Step 5: Commit** on branch `linked-apps` in frequent-finder.

### Task 2: FrequentFinder opens `frequentfinder://project/<id>`

**Files:**
- Modify: `scripts/make-app.sh` (add `CFBundleURLTypes` with scheme `frequentfinder`)
- Modify: `Sources/FFApp/FrequentFinderApp.swift`, `Sources/FFApp/AppModel.swift`

**Interfaces:**
- Consumes: `LinkedApp.projectID(in:scheme:)` (Task 1).
- Produces: `AppModel.project(id: UUID) -> Project?` (if not already present).

The menu-bar app may have no window open when the link arrives. SwiftUI's default then makes a new window of the first `WindowGroup` (an empty project window). Pick the mechanism that passes the hand checks below; two candidates, try in order:
1. `.handlesExternalEvents(matching: ["project"])` on the `WindowGroup("Project", for: String.self)` scene, and in its content `.onOpenURL { name = model.project(id:)?.name }` writing the window's `$name` binding; existing project windows refuse the event with `.handlesExternalEvents(preferring: [], allowing: [])` so they are never retargeted.
2. `AppDelegate.application(_:open:)` plus a model flag observed by an always-present scene.

- [ ] **Step 1: Implement** the scheme in `make-app.sh` and the handler. Unknown id: show an alert "No project with this link." (no project window left open).
- [ ] **Step 2: Build and install** — `./scripts/make-app.sh --install` → "Installed /Applications/FrequentFinder.app".
- [ ] **Step 3: Hand check** (with `<id>` from `ff list --json` or projects.json):
  - App quit: `open "frequentfinder://project/<id>"` → app starts, exactly one window, that project.
  - App running, no windows: same → one window.
  - Another project window open: same → it stays as it was; the linked project opens (or comes to front if already open).
  - `open "frequentfinder://project/00000000-0000-0000-0000-000000000000"` → the alert, no window.
- [ ] **Step 4: Commit.**

### Task 3: FrequentFinder Linked Apps in Settings, and Open in buttons

**Files:**
- Modify: `Sources/FFApp/SettingsView.swift` (new `LinkedAppsSection` view in the general settings `Form`)
- Modify: `Sources/FFApp/ProjectWindow.swift` (Open in buttons)
- Modify: `README.md` (GUI section: Linked Apps and the link format; Config file section: `linkedApps`)

**Interfaces:**
- Consumes: `LinkedApp(appAt:)`, `[LinkedApp].add(_:selfBundleID:)` and `.remove(bundleID:)` through `model.update { try $0.linkedApps.add(...) }`, `LinkedApp.open(_:)` (Task 1).

- [ ] **Step 1: Implement Linked Apps section.** Section title "Linked Apps". One row per app: app icon (`NSWorkspace.shared.icon(forFile:)` when installed), name, "Not installed" in secondary text when not found, remove button (`minus.circle`, label "Remove <name>"). An "Add App…" button opens an `NSOpenPanel` limited to `.applicationBundle`, starting in `/Applications`. The section is a `dropDestination(for: URL.self)` taking `.app` file URLs; it shows the accent outline while targeted, like `ProjectEditor`. Errors go to `model.error`. `selfBundleID` is `Bundle.main.bundleIdentifier`. Footer text: "Drop an app here. Each project then gets an Open in button for it."
- [ ] **Step 2: Implement Open in buttons.** In `ProjectWindow`'s form, a top section with one button per installed linked app: `Button("Open in \(app.name)") { model.attempt { try app.open(p.id) } }`. No section when none are installed.
- [ ] **Step 3: Build, install, hand check.** Drop OpenPMTools.app (after Task 4 is installed) onto Linked Apps → row appears; project window shows "Open in OpenPMTools". Drop TextEdit → "TextEdit cannot open project links." Drop FrequentFinder itself → "Frequent Finder is this app." Rename `/Applications/OpenPMTools.app` temporarily → button hides, row says "Not installed".
- [ ] **Step 4: `swift test`** → all pass. **Commit**, push, open PR in frequent-finder.

### Task 4: OpenPMTools opens `openpmtools://project/<id>` (openpmtools repo)

**Files:**
- Modify: `scripts/make-app.sh` (add `CFBundleURLTypes` with scheme `openpmtools`)
- Modify: `Sources/OpenPMToolsApp/OpenPMToolsApp.swift`

**Interfaces:**
- Consumes: `LinkedApp.projectID(in:scheme:)` (Task 1; FFCore is a local-path dependency, so nothing to bump).
- Produces: `AppModel.open(project: UUID) -> Bool`. It clears `search` and `highlight`, then selects the project the way `show(_:in:)` does (sidebar row if active, else `offSidebar`). Returns false when `catalog.entry(for:)` and `file.board(for:)` are both nil.

- [ ] **Step 1: Implement** `.onOpenURL` on `ContentView` (the single `Window` scene). Unknown id: `model.error = "No project with this link."`.
- [ ] **Step 2: Build and install** — `./scripts/make-app.sh --install`.
- [ ] **Step 3: Hand check:** app quit, `open "openpmtools://project/<id>"` → main window opens on that board. Window closed, app running → same. Unknown id → message in the sidebar footer. A FrequentFinder project with no board → board setup view for it.
- [ ] **Step 4: Commit** on branch `linked-apps` in openpmtools.

### Task 5: OpenPMTools Settings window with Linked Apps, and Open in buttons

**Files:**
- Create: `Sources/OpenPMToolsApp/SettingsView.swift`
- Modify: `Sources/OpenPMToolsApp/OpenPMToolsApp.swift` (add `Settings { SettingsView().environment(model) }`; Open in toolbar buttons)
- Modify: `Sources/OpenPMToolsApp/AppModel.swift` (`linkedApps`)
- Modify: `README.md` (Linked Apps and the link format)

**Interfaces:**
- Consumes: `LinkedApp`, `LinkedApp(appAt:)`, `LinkedApp.open(_:)` (Task 1).
- Produces: `AppModel.linkedApps: [LinkedApp]`, loaded from UserDefaults `linkedApps` (JSON) at start and saved on every change (`didSet`). Settings edits it with `[LinkedApp].add(_:selfBundleID:)` and `.remove(bundleID:)`; errors go to `model.error`.

- [ ] **Step 1: Implement SettingsView** with the same Linked Apps list, drop target, Add App… button, "Not installed" marking and footer as Task 3 Step 1. Frame about 460×320.
- [ ] **Step 2: Implement Open in buttons.** In `ContentView`'s toolbar, when a project is shown (`model.selection ?? model.offSidebar`), one button per installed linked app, label "Open in <name>", system image `arrow.up.forward.app`, calling `app.open(id)`; errors to `model.error`. Also a "Open in <name>" item per app in the sidebar row context menu.
- [ ] **Step 3: Build, install, hand check.** Settings (⌘,) → drop FrequentFinder.app → row appears; select a FrequentFinder project → "Open in Frequent Finder" opens its window. Select an own project → FrequentFinder shows "No project with this link." Drop OpenPMTools itself → "OpenPMTools is this app."
- [ ] **Step 4: `swift test`** → all pass. **Commit**, push, open PR in openpmtools (after the frequent-finder PR is merged, since it needs `LinkedApp`).
