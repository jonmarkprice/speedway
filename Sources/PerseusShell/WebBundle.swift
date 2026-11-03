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
            its dist/ into Sources/PerseusShell/Resources/Web), then build again.
            """
        }
    }

    /// Returns the `Web/` directory, which must contain index.html.
    static func locate() throws(MissingError) -> URL {
        // `.copy("Resources")` in Package.swift places the whole directory in the
        // bundle under its own name, so the web app is at Resources/Web.
        let web = Bundle.module.bundleURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Web", isDirectory: true)
        let index = web.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: index.path) else {
            throw MissingError(expectedPath: web.path)
        }
        return web
    }
}
