// swift-tools-version: 6.0
import PackageDescription

// Two ways to run the same app share one library:
// - `swift run` builds the `PerseusShell` executable, a bare binary for fast
//   local iteration.
// - App/Speedway.xcodeproj links `PerseusShellKit` into a signed, notarizable
//   Speedway.app (see scripts/package-app.sh).
// Everything except the `@main` entry point lives in `PerseusShellKit`.
let package = Package(
    name: "PerseusShell",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerseusShellKit", targets: ["PerseusShellKit"]),
        .executable(name: "PerseusShell", targets: ["PerseusShell"]),
    ],
    targets: [
        .target(
            name: "PerseusShellKit",
            // The whole Resources directory is copied into the resource bundle.
            // The built web app lives at Resources/Web, which scripts/build-web.sh
            // produces and git ignores. Declaring the parent directory (which is
            // always present) rather than Web itself means a missing bundle is a
            // clear runtime message instead of a SwiftPM build failure.
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "PerseusShell",
            dependencies: ["PerseusShellKit"]
        ),
    ]
)
