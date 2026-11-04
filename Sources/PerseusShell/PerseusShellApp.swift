import PerseusShellKit
import SwiftUI

/// The `swift run` entry point. The app itself lives in `PerseusShellKit`;
/// App/Speedway/SpeedwayApp.swift is the identical entry point for the
/// Xcode-built Speedway.app.
@main
struct PerseusShellApp: App {
    @NSApplicationDelegateAdaptor(PerseusShellAppDelegate.self) private var appDelegate

    var body: some Scene {
        PerseusShellScene()
    }
}
