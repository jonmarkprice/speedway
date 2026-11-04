# Perseus Swift shell

A native macOS shell for the [Perseus renderer](../perseus-renderer) web app.
Swift owns the window, the Open panel, a sidebar of items and the toolbar;
the React app, hosted in a `WKWebView`, keeps doing all of the rendering and
scoring. The two sides talk over a small JavaScript bridge described below.

Day to day it is a plain Swift package: `swift build` / `swift run` with Swift
6.3 on macOS 14 or later, no Xcode project needed. A thin Xcode project in
`App/` wraps the same code as a signed, notarized `Speedway.app` for sharing;
see [Distributing Speedway.app](#distributing-speedwayapp).

## Build and run

The web bundle is not committed. Build it from the sibling repo first, then run
the app:

```bash
# Once, in ../perseus-renderer: npm install
./scripts/build-web.sh    # npm run build in ../perseus-renderer, rsync dist/ into the package
swift run                 # builds and launches PerseusShell
```

`scripts/build-web.sh` copies `../perseus-renderer/dist/` into
`Sources/PerseusShellKit/Resources/Web/` (git-ignored). Re-run it after any change
to the web app; `swift run` picks the new files up on the next build. If the
web repo lives elsewhere, set `PERSEUS_RENDERER_DIR=/path/to/perseus-renderer`.

If you forget the script the app still launches, but the detail pane shows a
"Web bundle not found" message with the expected path (also printed to stderr)
instead of a blank web view.

Right-click in the page and choose Inspect Element to open Web Inspector; it is
enabled on the web view. Set `PERSEUS_SHELL_LOG_REQUESTS=1` to log every file
the scheme handler serves, which is the quickest way to debug a missing asset.

## What is where

| File | Role |
|------|------|
| `Package.swift` | macOS 14+. A `PerseusShellKit` library with all the app code, which copies the `Resources` directory (which contains `Web/`) into its resource bundle, and a `PerseusShell` executable for `swift run`. |
| `scripts/build-web.sh` | Builds the web app and rsyncs `dist/` into `Resources/Web/`. Refuses a bundle whose `index.html` has root-absolute asset paths. |
| `scripts/package-app.sh` | Archives, signs, notarizes and zips `Speedway.app`. See [Distributing Speedway.app](#distributing-speedwayapp). |
| `Sources/PerseusShell/PerseusShellApp.swift` | The `swift run` entry point: a `@main` App whose body is `PerseusShellScene`. |
| `App/Speedway.xcodeproj`, `App/Speedway/` | The `Speedway.app` target: an identical `@main` App (`SpeedwayApp.swift`), entitlements, and signing settings. It links `PerseusShellKit` from the package at `..`. |

Under `Sources/PerseusShellKit/`:

| File | Role |
|------|------|
| `PerseusShellScene.swift` | The window and menu commands, shared by both entry points. Its `PerseusShellAppDelegate` quits when the window closes and, only when running as a bare binary, sets the activation policy to `.regular` and activates the app, because a SwiftPM executable has no app bundle and would otherwise start behind the terminal with no Dock icon. |
| `ContentView.swift` | `NavigationSplitView`: sidebar list of items (✓/✗ once scored, score message as tooltip), toolbar with Open… and Load sample, window subtitle with file name and item count. |
| `WebView.swift` | `NSViewRepresentable` around `WKWebView`. Registers the scheme handler and the `shell` message handler, enables the inspector, loads `perseus://app/index.html`. |
| `PerseusSchemeHandler.swift` | `WKURLSchemeHandler` for `perseus://app/<path>`: maps to files in the `Web` folder, sets MIME types, returns a real 404 for anything missing. |
| `ShellModel.swift` | `ObservableObject` holding items, scores, file name and errors; decodes incoming messages; sends `loadJson`, `loadSample`, `scrollToItem` to the page. |
| `WebBundle.swift` | Finds `Resources/Web/index.html` in `Bundle.module` (flat when built by SwiftPM, `Contents/Resources` when built by Xcode) or produces the "run build-web.sh" error. |
| `Diagnostics.swift` | Unbuffered stdout/stderr logging so lines survive the process being killed. |

## How the bridge works

The page is served from the custom origin `perseus://app/`. Serving from a
scheme handler rather than `loadFileURL` gives the page a real origin, so the
Vite module script, `fetch("items.json")` and relative font URLs behave as
they would on a web server. The web app detects the shell by the presence of
`window.webkit.messageHandlers.shell` and, when hosted, hides its own
Choose/Load sample buttons because the toolbar provides them.

### Swift → JavaScript

`ShellModel` runs `window.perseusShell.<fn>(...)` through `evaluateJavaScript`.
Arguments are encoded as JSON literals (a JSON string is a valid JavaScript
string literal), so file contents can never break out of the call. The script
returns `"unavailable"` if the page has not registered the API yet, which
surfaces as an error in the sidebar rather than a JavaScript exception.

| Call | Effect in the page |
|------|--------------------|
| `perseusShell.loadJson(raw, name)` | Parses `raw` as a Perseus item, an array of items, or a KA exercise export and renders it. Replies with `loaded` or `error`. |
| `perseusShell.loadSample()` | Fetches `items.json` from the bundle and loads it. |
| `perseusShell.scrollToItem(index)` | Smooth-scrolls the card with id `perseus-item-<index>` into view. |

### JavaScript → Swift

The page posts plain objects with `webkit.messageHandlers.shell.postMessage`.
Each one is printed to stdout as a single line (`bridge <- {...}`) before it is
decoded, so you can verify the whole stack without the UI:

```bash
./scripts/build-web.sh && swift build
.build/debug/PerseusShell & sleep 8; kill %1
# expected on stdout:
# bridge <- {"type":"ready"}
# bridge <- {"items":[{"index":0,"label":""},...],"name":"items.json (sample)","type":"loaded"}
```

| Message | When | Fields |
|---------|------|--------|
| `{type: "ready"}` | Once, after the React app mounts and has registered `window.perseusShell`. | |
| `{type: "loaded", name, items}` | After every successful load. `items` is `[{index, label}]`; `label` is the exercise-export item name or `""`. The sidebar shows the label or "Item N". | |
| `{type: "error", message}` | A load failed (bad JSON, no items, unreadable file, sample fetch failed). | |
| `{type: "score", index, result, earned, total, message}` | Check answer was clicked. `result` is `"correct"`, `"incorrect"` or `"invalid"` (incomplete answer); `message` is the text the page shows and becomes the sidebar tooltip. | |
| `{type: "reset", index}` | Reset was clicked; the sidebar clears that item's mark. | |

The TypeScript side of this contract is `src/shell.ts` in perseus-renderer.

## Fonts work offline

MathJax renders math as HTML+CSS and loads its fonts from a URL. The web app
points that URL at `./fonts/mathjax`, and ships the 23 TeX `.woff` files (copied
from `mathjax-full`) in its `public/` folder, so the fonts travel with the
bundle and the shell needs no network at all. Perseus content that references
images on the Khan Academy CDN still needs a connection for those images.

## Distributing Speedway.app

`scripts/package-app.sh` produces `build/Speedway-<version>.zip`: a universal
(Apple silicon and Intel) `Speedway.app`, signed with the team's Developer ID
certificate, notarized by Apple and stapled, so coworkers can unzip it and open
it with no Gatekeeper warning. It runs entirely from the command line:

1. `scripts/build-web.sh`, so the app never ships stale web assets.
2. `xcodebuild archive` of the `Speedway` scheme with automatic signing.
3. `xcodebuild -exportArchive` with the `developer-id` method, which re-signs
   with the Developer ID Application certificate.
4. `xcrun notarytool submit --wait`, then `stapler staple`, then a fresh zip.

Pass `--skip-notarize` to stop after signing.

### Without an Apple account: `--ad-hoc`

`scripts/package-app.sh --ad-hoc` skips Developer ID signing and notarization
and signs the app ad hoc instead. That needs no Apple account, team
membership, certificate or provisioning profile. It writes
`build/Speedway-<version>-adhoc.zip`.

The catch is on the recipient's side: Gatekeeper rejects the app, so the first
time they open each build they must go to System Settings > Privacy & Security
and click **Open Anyway**, then enter their password. Every new build you send
needs this again, and managed Macs may not allow it at all.

The app is identified as `org.khanacademy.speedway.swiftui` on team
`T79C3JU3NR`. It runs in the App Sandbox with Hardened Runtime, and its
entitlements (`App/Speedway/Speedway.entitlements`) allow outgoing network
connections (Khan Academy CDN images) and reading files the user picks in the
Open panel.

### One-time setup

1. Use the full Xcode, not the command line tools:
   `sudo xcode-select -s /Applications/Xcode-26.6.0.app`, or set `DEVELOPER_DIR`.
2. In Xcode > Settings > Accounts, sign in with an Apple ID on the team. Your
   role must allow Developer ID signing (Account Holder, or an Admin granted
   access to Developer ID certificates).
3. Store notarization credentials in the keychain. This needs an app-specific
   password from [account.apple.com](https://account.apple.com):

   ```bash
   xcrun notarytool store-credentials speedway-notary --apple-id you@khanacademy.org --team-id T79C3JU3NR
   ```

   Set `NOTARY_PROFILE` if you stored it under a different name.

### Building or running from Xcode

`App/Speedway.xcodeproj` also opens in Xcode, where Run builds and launches the
real app bundle. Its app target contains only the entry point and
entitlements; all code lives in `PerseusShellKit`, so edits there show up in
both `swift run` and Xcode builds.
