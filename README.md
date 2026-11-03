# Perseus Swift shell

A native macOS shell for the [Perseus renderer](../perseus-renderer) web app.
Swift owns the window, the Open panel, a sidebar of items and the toolbar;
the React app, hosted in a `WKWebView`, keeps doing all of the rendering and
scoring. The two sides talk over a small JavaScript bridge described below.

It is a plain Swift package (no Xcode project) so it builds with just the
command line tools: `swift build` / `swift run` with Swift 6.3 on macOS 14 or
later.

## Build and run

The web bundle is not committed. Build it from the sibling repo first, then run
the app:

```bash
# Once, in ../perseus-renderer: npm install
./scripts/build-web.sh    # npm run build in ../perseus-renderer, rsync dist/ into the package
swift run                 # builds and launches PerseusShell
```

`scripts/build-web.sh` copies `../perseus-renderer/dist/` into
`Sources/PerseusShell/Resources/Web/` (git-ignored). Re-run it after any change
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
| `Package.swift` | One executable target, `PerseusShell`, macOS 14+. Copies the `Resources` directory (which contains `Web/`) into the resource bundle. |
| `scripts/build-web.sh` | Builds the web app and rsyncs `dist/` into `Resources/Web/`. Refuses a bundle whose `index.html` has root-absolute asset paths. |
| `Sources/PerseusShell/PerseusShellApp.swift` | The SwiftUI `App`. Its `AppDelegate` sets the activation policy to `.regular` and activates the app, because a SwiftPM executable has no app bundle and would otherwise start behind the terminal with no Dock icon. |
| `ContentView.swift` | `NavigationSplitView`: sidebar list of items (✓/✗ once scored, score message as tooltip), toolbar with Open… and Load sample, window subtitle with file name and item count. |
| `WebView.swift` | `NSViewRepresentable` around `WKWebView`. Registers the scheme handler and the `shell` message handler, enables the inspector, loads `perseus://app/index.html`. |
| `PerseusSchemeHandler.swift` | `WKURLSchemeHandler` for `perseus://app/<path>`: maps to files in the `Web` folder, sets MIME types, returns a real 404 for anything missing. |
| `ShellModel.swift` | `ObservableObject` holding items, scores, file name and errors; decodes incoming messages; sends `loadJson`, `loadSample`, `scrollToItem` to the page. |
| `WebBundle.swift` | Finds `Resources/Web/index.html` in `Bundle.module` or produces the "run build-web.sh" error. |
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

## Switching to an Xcode project later

Nothing here depends on SwiftPM specifically. If you want an app bundle (icon,
Info.plist, signing, a `.app` to double-click), point the tools at Xcode with
`sudo xcode-select -s /Applications/Xcode.app`, then either open `Package.swift`
directly in Xcode and add an App target that depends on the `PerseusShell`
sources, or generate a project with [xcodegen](https://github.com/yonaskolb/XcodeGen)
from a short `project.yml` listing `Sources/PerseusShell` and the `Resources`
folder. The scheme handler, bridge and model carry over unchanged; the only
thing to drop is the `AppDelegate` activation-policy workaround, which a real
bundle makes unnecessary.
