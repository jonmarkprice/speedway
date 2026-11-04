import AppKit
import SwiftUI

/// The app's one window and its menu commands. Both entry points (the SwiftPM
/// `PerseusShell` executable and the Xcode `Speedway` app) use this as their
/// entire `body`, so they behave identically. SwiftUI owns the window;
/// everything web lives in `WebView`, and `ShellModel` is the single source of
/// truth the sidebar reads.
public struct PerseusShellScene: Scene {
    @StateObject private var model = ShellModel()

    /// Where the built web app lives inside the resource bundle, or the reason
    /// it could not be found. Resolved once at launch so a missing bundle shows
    /// a clear message in the window instead of a blank web view.
    private let webBundle: Result<URL, WebBundle.MissingError>

    public init() {
        do {
            let root = try WebBundle.locate()
            Diagnostics.stderr("serving web bundle from \(root.path)")
            webBundle = .success(root)
        } catch {
            Diagnostics.stderr(error.localizedDescription)
            webBundle = .failure(error)
        }
    }

    public var body: some Scene {
        WindowGroup("Perseus Renderer") {
            ContentView(model: model, webBundle: webBundle)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            // A single-window tool has no use for File > New Window, so Open…
            // and Load Sample take that slot, with the shortcuts users expect.
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Load Sample") { model.loadSample() }
                    .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}

/// The application delegate both entry points install with
/// `@NSApplicationDelegateAdaptor`.
@MainActor
public final class PerseusShellAppDelegate: NSObject, NSApplicationDelegate {
    /// A SwiftPM executable has no app bundle, so without the policy change
    /// the process would run as a faceless background process with its window
    /// buried behind the terminal. Becoming a regular app gives it a Dock icon
    /// and a menu bar. A real .app bundle gets this from Launch Services, so
    /// the workaround only applies to the bare binary.
    private var isBareExecutable: Bool {
        Bundle.main.bundleURL.pathExtension != "app"
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        if isBareExecutable {
            NSApp.setActivationPolicy(.regular)
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if isBareExecutable {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// It is a single-window tool, so closing the window should quit, as the
    /// user would expect from a document-less utility.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
