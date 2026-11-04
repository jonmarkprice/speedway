/**
 * The bridge between this web app and a native shell that hosts it in a
 * WKWebView (the Swift package at the root of this repo).
 *
 * Direction 1, Swift to JavaScript: the shell calls the functions it finds on
 * `window.perseusShell` via `evaluateJavaScript`. The React app registers its
 * real implementations in an effect once it has mounted.
 *
 * Direction 2, JavaScript to Swift: we post plain JSON objects to the
 * `webkit.messageHandlers.shell` handler. Every message carries a `type` so the
 * Swift side can switch on it.
 *
 * In a plain browser neither side exists, so every function here is a no-op
 * and the app behaves exactly as before.
 */

export type ShellItemSummary = {index: number; label: string};

export type ShellMessage =
    | {type: "ready"}
    | {type: "loaded"; name: string; items: ShellItemSummary[]}
    | {type: "error"; message: string}
    | {
          type: "score";
          index: number;
          result: "correct" | "incorrect" | "invalid";
          earned: number;
          total: number;
          message: string;
      }
    | {type: "reset"; index: number};

// The API the shell may call. All functions are optional until the app has
// registered them, so the shell can probe safely.
export type PerseusShellAPI = {
    loadJson: (raw: string, name: string) => void;
    loadSample: () => void;
    scrollToItem: (index: number) => void;
};

declare global {
    interface Window {
        webkit?: {
            messageHandlers?: {
                shell?: {postMessage: (message: unknown) => void};
            };
        };
        perseusShell?: Partial<PerseusShellAPI>;
    }
}

/** True when running inside the Swift shell rather than a plain browser. */
export function isHostedInShell(): boolean {
    return typeof window !== "undefined" &&
        !!window.webkit?.messageHandlers?.shell;
}

/** Posts a message to the shell. Silently does nothing in a browser. */
export function postToShell(message: ShellMessage): void {
    const handler = window.webkit?.messageHandlers?.shell;
    if (!handler) {
        return;
    }
    try {
        handler.postMessage(message);
    } catch (e) {
        // A failed post should never break rendering; the shell is optional.
        console.warn("perseusShell: postMessage failed", e);
    }
}

/**
 * Registers (or updates) the functions the shell can call. The app calls this
 * from an effect so the callbacks always close over current state. Returns an
 * unregister function for effect cleanup.
 */
export function registerShellAPI(api: Partial<PerseusShellAPI>): () => void {
    window.perseusShell = {...window.perseusShell, ...api};
    return () => {
        if (!window.perseusShell) {
            return;
        }
        for (const key of Object.keys(api) as (keyof PerseusShellAPI)[]) {
            delete window.perseusShell[key];
        }
    };
}

/** The DOM id the app gives each item card so `scrollToItem` can find it. */
export function itemElementId(index: number): string {
    return `perseus-item-${index}`;
}

/** Scrolls the card for the item at `index` into view, if it exists. */
export function scrollToItem(index: number): void {
    document
        .getElementById(itemElementId(index))
        ?.scrollIntoView({behavior: "smooth", block: "start"});
}
