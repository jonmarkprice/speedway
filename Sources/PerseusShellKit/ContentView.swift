import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The window: a sidebar of items on the left, the web view on the right, and
/// a toolbar that replaces the web app's own file buttons.
struct ContentView: View {
    @ObservedObject var model: ShellModel
    let webBundle: Result<URL, WebBundle.MissingError>

    @State private var selection: Int?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            switch webBundle {
            case let .success(webRoot):
                WebView(model: model, webRoot: webRoot)
            case let .failure(error):
                MissingBundleView(message: error.localizedDescription)
            }
        }
        .navigationTitle("Perseus Renderer")
        .navigationSubtitle(model.subtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open…", systemImage: "folder", action: model.openFile)
                    .help("Open a Perseus .json file")
                Button("Load sample", systemImage: "doc.text", action: model.loadSample)
                    .help("Load the bundled items.json")
            }
        }
        .onChange(of: selection) { _, index in
            // Selecting a row is how the user jumps to that item in the page.
            if let index {
                model.scrollToItem(index)
            }
        }
        .onChange(of: model.items) {
            // A new file invalidates the old selection, and the page has
            // scrolled back to the top on its own.
            selection = nil
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.items.isEmpty {
                Text("No items loaded")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.items, selection: $selection) { item in
                    ItemRow(item: item, score: model.scores[item.index])
                }
                .listStyle(.sidebar)
            }
            if let error = model.lastError {
                Divider()
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(10)
            }
            if model.watchedFileURL != nil {
                Divider()
                watchStatus
                    .padding(10)
            }
        }
    }

    /// Footer under the item list: whether edits to the open file are being
    /// picked up, and when it was last read from disk.
    private var watchStatus: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(
                model.isAutoReloadEnabled ? "Reloading on save" : "Auto-reload off",
                systemImage: model.isAutoReloadEnabled ? "arrow.triangle.2.circlepath" : "pause.circle"
            )
            if let at = model.lastLoadedAt {
                Text("Loaded \(at, format: .dateTime.hour().minute().second())")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .help("Edits to the open file re-render the page. Toggle in File > Reload When File Changes.")
    }
}

/// One sidebar row: the item's name and, once checked, a ✓ or ✗ whose tooltip
/// is the score message the page showed.
private struct ItemRow: View {
    let item: ShellItem
    let score: ItemScore?

    var body: some View {
        HStack {
            Text(item.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let score {
                Text(score.result == .correct ? "✓" : "✗")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color(for: score.result))
                    .accessibilityLabel(score.result.rawValue)
            }
        }
        .tag(item.index)
        .help(score?.message ?? item.displayName)
    }

    /// Orange for "invalid" distinguishes an incomplete answer from a wrong one.
    private func color(for result: ItemScore.Result) -> Color {
        switch result {
        case .correct: .green
        case .incorrect: .red
        case .invalid: .orange
        }
    }
}

/// Shown instead of the web view when scripts/build-web.sh has not been run.
private struct MissingBundleView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Web bundle not found")
                .font(.title2.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 520)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
