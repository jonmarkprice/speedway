import Foundation

/// Finds the built web app inside the SwiftPM resource bundle.
enum WebBundle {
    /// Raised when `scripts/build-web.sh` has not been run, so the Resources
    /// directory was copied into the bundle without a `Web/` folder in it.
    struct MissingError: LocalizedError {
        let expectedPath: String

        var errorDescription: String? {
            """
            The web bundle is missing: no index.html at \(expectedPath).
            Run scripts/build-web.sh (which builds ../perseus-renderer and copies \
            its dist/ into Sources/PerseusShellKit/Resources/Web), then build again.
            """
        }
    }

    /// Returns the `Web/` directory, which must contain index.html.
    static func locate() throws(MissingError) -> URL {
        // `.copy("Resources")` in Package.swift places the whole directory in the
        // bundle under its own name, so the web app is at Resources/Web inside
        // the bundle's resource directory. That directory differs by builder:
        // - `swift build` makes a flat bundle, so it is the bundle itself.
        //   (Bundle's `resourceURL` is wrong here: it mistakes the copied
        //   top-level Resources folder for the resource directory.)
        // - Xcode makes a real bundle, so it is Contents/Resources.
        let bundle = Bundle.module.bundleURL
        let candidates = [
            bundle,
            bundle.appendingPathComponent("Contents/Resources", isDirectory: true),
        ].map {
            $0.appendingPathComponent("Resources/Web", isDirectory: true)
        }
        let fileManager = FileManager.default
        guard let web = candidates.first(where: {
            fileManager.fileExists(atPath: $0.appendingPathComponent("index.html").path)
        }) else {
            throw MissingError(expectedPath: candidates.map(\.path).joined(separator: " or "))
        }
        return web
    }
}
