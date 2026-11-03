// swift-tools-version: 6.0
import PackageDescription

// A plain SwiftPM executable rather than an Xcode project, because the machine's
// xcode-select points at the command line tools. `swift run` is enough to build
// and launch the app; the README describes moving to Xcode later if wanted.
let package = Package(
    name: "PerseusShell",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PerseusShell",
            // The whole Resources directory is copied into the resource bundle.
            // The built web app lives at Resources/Web, which scripts/build-web.sh
            // produces and git ignores. Declaring the parent directory (which is
            // always present) rather than Web itself means a missing bundle is a
            // clear runtime message instead of a SwiftPM build failure.
            resources: [.copy("Resources")]
        ),
    ]
)
