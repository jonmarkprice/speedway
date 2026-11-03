import AppKit
import SwiftUI

/// The app entry point. SwiftUI owns the window; everything web lives in
/// `WebView`, and `ShellModel` is the single source of truth the sidebar reads.
@main
struct PerseusShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ShellModel()

    /// Where the built web app lives inside the resource bundle, or the reason
    /// it could not be found. Resolved once at launch so a missing bundle shows
    /// a clear message in the window instead of a blank web view.
    private let webBundle: Result<URL, WebBundle.MissingError>

    init() {
        do {
            let root = try WebBundle.locate()
            Diagnostics.stderr("serving web bundle from \(root.path)")
            webBundle = .success(root)
        } catch {
            Diagnostics.stderr(error.localizedDescription)
            webBundle = .failure(error)
        }
    }

    var body: some Scene {
        WindowGroup("Perseus Renderer") {
            ContentView(model: model, webBundle: webBundle)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 860)
    }
}

/// A SwiftPM executable has no app bundle, so without this the process would
/// run as a faceless background process with its window buried behind the
/// terminal. Becoming a regular app gives it a Dock icon and a menu bar, and
/// activating brings the window to the front.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// It is a single-window tool, so closing the window should quit, as the
    /// user would expect from a document-less utility.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
