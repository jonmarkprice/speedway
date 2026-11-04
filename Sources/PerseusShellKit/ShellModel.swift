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
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            loadJson(raw: raw, name: url.lastPathComponent)
        } catch {
            lastError = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func loadSample() {
        Diagnostics.stdout("bridge -> loadSample()")
        call("loadSample", arguments: [])
    }

    func scrollToItem(_ index: Int) {
        Diagnostics.stdout("bridge -> scrollToItem(\(index))")
        call("scrollToItem", arguments: [index])
    }

    /// Invokes `window.perseusShell.<name>(...)`. The script checks that the
    /// bridge has been registered so a click before the page is ready produces
    /// a readable error instead of a JavaScript TypeError.
    private func call(_ name: String, arguments: [Any]) {
        guard let webView else {
            lastError = "The web view is not available."
            return
        }
        let args = arguments.map(Self.jsonLine).joined(separator: ", ")
        let script = """
        (function () {
            var api = window.perseusShell;
            if (!api || typeof api.\(name) !== "function") { return "unavailable"; }
            api.\(name)(\(args));
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
