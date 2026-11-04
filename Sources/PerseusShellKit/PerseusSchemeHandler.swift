import Foundation
import WebKit

/// Serves the built web app at perseus://app/<path> straight from the resource
/// bundle. A custom scheme (rather than `loadFileURL`) gives the page a proper
/// origin, so module scripts, `fetch("items.json")` and relative font URLs all
/// behave as they would on a web server.
@MainActor
final class PerseusSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "perseus"
    static let host = "app"
    static let indexURL = URL(string: "\(scheme)://\(host)/index.html")!

    /// The directory holding index.html and its assets.
    private let webRoot: URL

    /// Set PERSEUS_SHELL_LOG_REQUESTS=1 to log every response on stderr. Off by
    /// default because a page load touches dozens of files; 404s always log.
    private static let logsAllRequests =
        ProcessInfo.processInfo.environment["PERSEUS_SHELL_LOG_REQUESTS"] != nil

    init(webRoot: URL) {
        self.webRoot = webRoot.standardizedFileURL
    }

    /// Module scripts are refused by WebKit unless the response says they are
    /// JavaScript, and fonts need their real types to be accepted, so the map
    /// covers everything the Vite build emits. Unknown extensions fall back to
    /// octet-stream rather than being refused.
    private static let mimeTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "mjs": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "map": "application/json; charset=utf-8",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "ico": "image/x-icon",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "txt": "text/plain; charset=utf-8",
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        guard url.host == Self.host, let fileURL = fileURL(for: url) else {
            respond(urlSchemeTask, url: url, status: 404, mime: "text/plain; charset=utf-8",
                    body: Data("Not found: \(url.path)".utf8))
            return
        }
        guard let data = FileManager.default.contents(atPath: fileURL.path) else {
            respond(urlSchemeTask, url: url, status: 404, mime: "text/plain; charset=utf-8",
                    body: Data("Not found: \(url.path)".utf8))
            return
        }
        let mime = Self.mimeTypes[fileURL.pathExtension.lowercased()] ?? "application/octet-stream"
        respond(urlSchemeTask, url: url, status: 200, mime: mime, body: data)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Every response is produced synchronously inside `start`, so there is
        // never an in-flight task left to cancel here.
    }

    /// Maps the URL path onto a file under the web root, or nil when the path
    /// escapes the root or names something that is not a regular file. An empty
    /// path or "/" means index.html, mirroring a web server's directory index.
    private func fileURL(for url: URL) -> URL? {
        var path = url.path
        if path.isEmpty || path == "/" {
            path = "/index.html"
        }
        let candidate = webRoot.appendingPathComponent(path).standardizedFileURL
        guard candidate.path.hasPrefix(webRoot.path + "/") else {
            Diagnostics.stderr("refused path outside web root: \(url.absoluteString)")
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            Diagnostics.stderr("404 \(url.absoluteString)")
            return nil
        }
        return candidate
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, body: Data) {
        if Self.logsAllRequests {
            Diagnostics.stderr("\(status) \(url.absoluteString) \(mime) \(body.count) bytes")
        }
        // An HTTPURLResponse (not a bare URLResponse) is what lets us return a
        // real 404 status, so a missing asset shows up as such in Web Inspector.
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": String(body.count),
                // The bundle is rebuilt by a script, so never let WebKit cache it.
                "Cache-Control": "no-cache",
            ]
        ) else {
            task.didFailWithError(URLError(.cannotCreateFile))
            return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}
