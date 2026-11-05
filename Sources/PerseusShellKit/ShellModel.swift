import AppKit
import Foundation
import WebKit

/// One loaded Perseus item as the web app describes it in a "loaded" message.
struct ShellItem: Identifiable, Hashable {
    let index: Int
    /// The item's name from a Khan Academy exercise export, or empty.
    let label: String

    var id: Int { index }

    /// Falls back to a positional name because bare item arrays carry no labels.
    var displayName: String {
        label.isEmpty ? "Item \(index + 1)" : label
    }
}

/// The verdict for one item after Check answer. "invalid" means the answer was
/// incomplete (for example an empty numeric input), which is distinct from
/// wrong, so the sidebar can show it differently.
struct ItemScore: Hashable {
    enum Result: String {
        case correct, incorrect, invalid
    }

    let result: Result
    let earned: Int
    let total: Int
    let message: String
}

/// A message posted by the web app via `webkit.messageHandlers.shell`. The
/// shapes mirror `ShellMessage` in web/src/shell.ts.
enum ShellMessage {
    case ready
    case loaded(name: String, items: [ShellItem])
    case error(message: String)
    case score(index: Int, score: ItemScore)
    case reset(index: Int)

    /// Decodes a `WKScriptMessage.body`, which WebKit hands over as a plain
    /// dictionary. Hand-written rather than Codable because the payload is a
    /// tagged union keyed on "type" and the fields are few.
    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else {
            return nil
        }
        switch type {
        case "ready":
            self = .ready
        case "loaded":
            guard let name = dict["name"] as? String,
                  let rawItems = dict["items"] as? [[String: Any]]
            else { return nil }
            let items = rawItems.compactMap { raw -> ShellItem? in
                guard let index = raw["index"] as? Int else { return nil }
                return ShellItem(index: index, label: raw["label"] as? String ?? "")
            }
            self = .loaded(name: name, items: items)
        case "error":
            guard let message = dict["message"] as? String else { return nil }
            self = .error(message: message)
        case "score":
            guard let index = dict["index"] as? Int,
                  let result = (dict["result"] as? String).flatMap(ItemScore.Result.init(rawValue:))
            else { return nil }
            let score = ItemScore(
                result: result,
                earned: dict["earned"] as? Int ?? 0,
                total: dict["total"] as? Int ?? 0,
                message: dict["message"] as? String ?? ""
            )
            self = .score(index: index, score: score)
        case "reset":
            guard let index = dict["index"] as? Int else { return nil }
            self = .reset(index: index)
        default:
            return nil
        }
    }
}

/// The state the sidebar shows, fed by messages from the web app, plus the
/// commands the toolbar sends back to it. It owns a weak reference to the web
/// view so the SwiftUI layer never has to touch WebKit directly.
@MainActor
final class ShellModel: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var fileName: String?
    @Published private(set) var items: [ShellItem] = []
    @Published private(set) var scores: [Int: ItemScore] = [:]
    /// The most recent load or bridge failure, shown at the bottom of the sidebar.
    @Published var lastError: String?

    /// The file on disk the page is currently showing, if it came from Open…
    /// rather than the bundled sample. This is what gets watched and reloaded.
    @Published private(set) var watchedFileURL: URL?
    /// Whether edits to the open file are picked up automatically. Toggled from
    /// the File menu; Reload (⌘R) works regardless.
    @Published var isAutoReloadEnabled = true {
        didSet { syncWatcher() }
    }
    /// When the open file was last (re)loaded from disk, for the sidebar footer.
    @Published private(set) var lastLoadedAt: Date?

    private var watcher: FileWatcher?
    /// The bytes last handed to the page, so a save that did not change the
    /// content (or an attribute-only event) does not re-render anything.
    private var loadedData: Data?

    /// Set by `WebView` once the view exists. Weak because the view hierarchy
    /// owns the web view; the model only borrows it to run scripts.
    weak var webView: WKWebView?

    /// What the window subtitle shows: the file and how many items it held.
    var subtitle: String {
        guard let fileName else { return "No file loaded" }
        return "\(fileName) — \(items.count) \(items.count == 1 ? "item" : "items")"
    }

    // MARK: Messages from JavaScript

    /// Entry point for every `WKScriptMessage`. Logs the raw body as one JSON
    /// line on stdout before decoding, so even a malformed message is visible.
    func receive(body: Any) {
        Diagnostics.stdout("bridge <- \(Self.jsonLine(body))")
        guard let message = ShellMessage(body: body) else {
            Diagnostics.stderr("could not decode bridge message")
            return
        }
        apply(message)
    }

    private func apply(_ message: ShellMessage) {
        switch message {
        case .ready:
            isReady = true
        case let .loaded(name, items):
            fileName = name
            self.items = items
            // A new file means every earlier verdict is stale.
            scores = [:]
            lastError = nil
        case let .error(message):
            lastError = message
        case let .score(index, score):
            scores[index] = score
        case let .reset(index):
            scores[index] = nil
        }
    }

    // MARK: Commands to JavaScript

    /// Hands a file's text to the web app, which parses and renders it. The
    /// text is passed as a JSON string literal, which is also a valid JavaScript
    /// string literal, so arbitrary content cannot break out of the call.
    func loadJson(raw: String, name: String) {
        Diagnostics.stdout("bridge -> loadJson(\(Self.jsonLine(name)), \(raw.utf8.count) bytes)")
        call("loadJson", arguments: [raw, name])
    }

    /// Asks for a .json file with the standard open panel, reads it here, in
    /// Swift, and hands the text to the page. Both the toolbar button and the
    /// File menu's Open… call this, so the two never drift apart. A modal
    /// panel keeps the flow synchronous and avoids juggling callbacks.
    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Perseus item, an array of items, or an exercise export"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        open(url)
    }

    /// Reads `url`, renders it, and starts watching it for edits.
    func open(_ url: URL) {
        stopWatching()
        watchedFileURL = url
        loadedData = nil
        if load(from: url, preservingScroll: false) {
            syncWatcher()
        }
    }

    /// Re-reads the open file right now, whether or not auto-reload is on.
    func reloadFromDisk() {
        guard let url = watchedFileURL else { return }
        loadedData = nil
        _ = load(from: url, preservingScroll: true)
    }

    func loadSample() {
        Diagnostics.stdout("bridge -> loadSample()")
        // The sample lives in the bundle, so there is no file left to watch.
        stopWatching()
        watchedFileURL = nil
        loadedData = nil
        lastLoadedAt = nil
        call("loadSample", arguments: [])
    }

    // MARK: Watching the open file

    /// Starts or stops the watcher so it matches `watchedFileURL` and the
    /// auto-reload setting.
    private func syncWatcher() {
        guard isAutoReloadEnabled, let url = watchedFileURL else {
            stopWatching()
            return
        }
        guard watcher?.url != url else { return }
        stopWatching()
        watcher = FileWatcher(url: url) { [weak self] event in
            self?.handleFileEvent(event)
        }
        if watcher == nil {
            lastError = "Could not watch \(url.lastPathComponent) for changes."
            Diagnostics.stderr(lastError ?? "")
        } else {
            Diagnostics.stdout("watching \(url.path)")
        }
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func handleFileEvent(_ event: FileWatcher.Event) {
        guard let url = watchedFileURL else { return }
        switch event {
        case .changed:
            _ = load(from: url, preservingScroll: true)
        case .disappeared:
            stopWatching()
            lastError = "\(url.lastPathComponent) was moved or deleted; no longer watching it."
            Diagnostics.stderr(lastError ?? "")
        }
    }

    /// Reads the file and hands it to the page unless its bytes are identical
    /// to what the page already shows. Returns false if the file could not be
    /// read or decoded; the error is shown in the sidebar.
    @discardableResult
    private func load(from url: URL, preservingScroll: Bool) -> Bool {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            lastError = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
            Diagnostics.stderr(lastError ?? "")
            return false
        }
        if data == loadedData {
            Diagnostics.stdout("unchanged \(url.lastPathComponent); not reloading")
            return true
        }
        guard let raw = String(data: data, encoding: .utf8) else {
            lastError = "Could not read \(url.lastPathComponent): the file is not UTF-8 text."
            Diagnostics.stderr(lastError ?? "")
            return false
        }
        loadedData = data
        lastLoadedAt = Date()
        if preservingScroll {
            reloadJson(raw: raw, name: url.lastPathComponent)
        } else {
            loadJson(raw: raw, name: url.lastPathComponent)
        }
        return true
    }

    /// Like `loadJson`, but keeps the page's scroll position, so re-rendering
    /// after an edit does not throw the user back to the top. The restore runs
    /// on the next animation frame, after React has committed the new cards.
    private func reloadJson(raw: String, name: String) {
        Diagnostics.stdout("bridge -> loadJson(\(Self.jsonLine(name)), \(raw.utf8.count) bytes, reload)")
        let args = [raw, name].map(Self.jsonLine).joined(separator: ", ")
        run(bridgeScript: """
            var el = document.scrollingElement || document.documentElement;
            var x = el.scrollLeft, y = el.scrollTop;
            api.loadJson(\(args));
            requestAnimationFrame(function () { el.scrollTo(x, y); });
            """, name: "loadJson")
    }

    func scrollToItem(_ index: Int) {
        Diagnostics.stdout("bridge -> scrollToItem(\(index))")
        call("scrollToItem", arguments: [index])
    }

    /// Invokes `window.perseusShell.<name>(...)`. The script checks that the
    /// bridge has been registered so a click before the page is ready produces
    /// a readable error instead of a JavaScript TypeError.
    private func call(_ name: String, arguments: [Any]) {
        let args = arguments.map(Self.jsonLine).joined(separator: ", ")
        run(bridgeScript: "api.\(name)(\(args));", name: name)
    }

    /// Runs `body` with `api` bound to `window.perseusShell`, after checking
    /// that `api.<name>` exists so the failure mode is a sidebar message.
    private func run(bridgeScript body: String, name: String) {
        guard let webView else {
            lastError = "The web view is not available."
            return
        }
        let script = """
        (function () {
            var api = window.perseusShell;
            if (!api || typeof api.\(name) !== "function") { return "unavailable"; }
            \(body)
            return "ok";
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.lastError = "Bridge call \(name) failed: \(error.localizedDescription)"
                Diagnostics.stderr(self?.lastError ?? "")
            } else if (result as? String) != "ok" {
                self?.lastError = "The page has not registered window.perseusShell.\(name) yet."
                Diagnostics.stderr(self?.lastError ?? "")
            }
        }
    }

    /// Compact JSON with sorted keys, so log lines are stable and greppable.
    /// `.fragmentsAllowed` lets bare strings and numbers through, which is what
    /// makes this double as the JavaScript-literal encoder for `call`.
    private static func jsonLine(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value) || value is String || value is NSNumber,
              let data = try? JSONSerialization.data(
                withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]
              )
        else {
            return String(describing: value)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
