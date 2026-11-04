import PerseusShellKit
import SwiftUI

/// The Speedway.app entry point, built by App/Speedway.xcodeproj. The app itself
/// lives in the `PerseusShellKit` package library; Sources/PerseusShell is the
/// identical entry point for `swift run`.
@main
struct SpeedwayApp: App {
    @NSApplicationDelegateAdaptor(PerseusShellAppDelegate.self) private var appDelegate

    var body: some Scene {
        PerseusShellScene()
    }
}
