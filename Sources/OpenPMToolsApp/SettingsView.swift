import AppKit
import FFCore
import SwiftUI

extension LinkedApp {
    /// Where the app is installed; nil when macOS cannot find it.
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
}

/// Settings (⌘,): the list of apps that get an "Open in" button on every project.
/// Same behaviour as Frequent Finder's Linked Apps; the two copies are kept in step by hand.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Linked Apps").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.linkedApps, id: \.bundleID, content: row)
                Button("Add App…", action: chooseApp)
                Text("Drop an app here. Each project then gets an Open in button for it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2).opacity(targeted ? 1 : 0))
            .dropDestination(for: URL.self) { urls, _ in add(urls) } isTargeted: { targeted = $0 }
            if let failure { Text(failure).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 320)
    }

    private func row(_ app: LinkedApp) -> some View {
        HStack {
            if let url = app.appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            Text(app.name)
            if app.appURL == nil { Text("Not installed").foregroundStyle(.secondary) }
            Spacer()
            Button { model.linkedApps.remove(bundleID: app.bundleID) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove \(app.name)")
                .accessibilityLabel("Remove \(app.name)")
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Link"
        if panel.runModal() == .OK, let url = panel.url { _ = add([url]) }
    }

    /// Links every dropped app, or none if one of them cannot be linked.
    private func add(_ urls: [URL]) -> Bool {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        var apps = model.linkedApps
        do {
            for url in files { try apps.add(LinkedApp(appAt: url), selfBundleID: Bundle.main.bundleIdentifier) }
        } catch {
            failure = "\(error)"
            return false
        }
        model.linkedApps = apps
        failure = nil
        return true
    }
}

/// "Open in <app>" buttons for a project, one per installed linked app.
struct OpenInButtons: View {
    @Environment(AppModel.self) private var model
    let project: UUID

    var body: some View {
        ForEach(model.linkedApps.filter { $0.appURL != nil }, id: \.bundleID) { app in
            Button {
                do { try app.open(project) } catch { model.error = "\(error)" }
            } label: {
                Label("Open in \(app.name)", systemImage: "arrow.up.forward.app")
            }
            .help("Open in \(app.name)")
        }
    }
}
