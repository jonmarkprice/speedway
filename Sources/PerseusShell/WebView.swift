import SwiftUI
import WebKit

/// Hosts the web app. Builds the configuration (scheme handler, message
/// handler, inspector), loads perseus://app/index.html, and forwards messages
/// to the model.
struct WebView: NSViewRepresentable {
    let model: ShellModel
    let webRoot: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            PerseusSchemeHandler(webRoot: webRoot),
            forURLScheme: PerseusSchemeHandler.scheme
        )
        // "shell" is the name the page looks for at webkit.messageHandlers.shell.
        configuration.userContentController.add(context.coordinator, name: "shell")
        // The private preference is what older guidance used to enable Web
        // Inspector; `isInspectable` below is the public API since macOS 13.3.
        // Setting both costs nothing and keeps "Inspect Element" available.
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
        webView.navigationDelegate = context.coordinator
        model.webView = webView
        webView.load(URLRequest(url: PerseusSchemeHandler.indexURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Nothing is driven by SwiftUI state; the model talks to the web view
        // directly through `evaluateJavaScript`.
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // The content controller retains its handlers, so remove ours to avoid
        // keeping the coordinator alive past the view.
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "shell")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let model: ShellModel

        init(model: ShellModel) {
            self.model = model
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            model.receive(body: message.body)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            model.lastError = "Could not load the web app: \(error.localizedDescription)"
            Diagnostics.stderr(model.lastError ?? "")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            model.lastError = "The web app failed: \(error.localizedDescription)"
            Diagnostics.stderr(model.lastError ?? "")
        }

        /// WebKit kills the content process on a crash and leaves a blank view;
        /// reloading is the only sensible recovery for a local app.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Diagnostics.stderr("web content process terminated; reloading")
            webView.reload()
        }
    }
}
