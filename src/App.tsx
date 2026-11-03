import * as React from "react";

import {PerseusItemRenderer} from "./PerseusItemRenderer";
import {
    isHostedInShell,
    itemElementId,
    postToShell,
    registerShellAPI,
    scrollToItem,
} from "./shell";

import type {PerseusItem} from "@khanacademy/perseus-core";

// An item plus an optional human-readable label to show in its card header.
type LabeledItem = {item: PerseusItem; label?: string};

// Accepts either a full PerseusItem ({question, hints, answerArea}) or a bare
// PerseusRenderer ({content, widgets, images}) and normalizes to a PerseusItem.
function normalize(parsed: any): PerseusItem {
    if (parsed && parsed.question) {
        return {
            answerArea: parsed.answerArea ?? null,
            hints: parsed.hints ?? [],
            itemDataVersion: parsed.itemDataVersion ?? {major: 0, minor: 1},
            ...parsed,
        };
    }
    // Treat the input as a bare renderer (just the "question" part).
    return {
        question: parsed,
        answerArea: null,
        hints: [],
        itemDataVersion: {major: 0, minor: 1},
    };
}

// A Khan Academy exercise export wraps the Perseus items in a top-level
// `items` array, where each entry carries the actual item under `item_data`
// (and a friendly `name`). Detect that shape.
function isExerciseExport(parsed: any): boolean {
    return (
        parsed &&
        Array.isArray(parsed.items) &&
        parsed.items.some((it: any) => it && it.item_data)
    );
}

// A file may contain: a full KA exercise export, a single item, or an array of
// items. Normalize any of those into a list of labeled items.
function toItems(parsed: any): LabeledItem[] {
    if (isExerciseExport(parsed)) {
        return parsed.items
            .filter((it: any) => it && it.item_data)
            .map((it: any) => ({
                item: normalize(it.item_data),
                label: it.name,
            }));
    }
    const list = Array.isArray(parsed) ? parsed : [parsed];
    return list.map((p) => ({item: normalize(p)}));
}

// Whether a native shell is hosting us. This cannot change during a page's
// lifetime, so it is computed once rather than kept in state.
const hosted = isHostedInShell();

export function App(): React.ReactElement {
    const [items, setItems] = React.useState<LabeledItem[]>([]);
    const [error, setError] = React.useState<string | null>(null);
    const [fileName, setFileName] = React.useState<string | null>(null);
    // Bumped on every load so each renderer resets its transient state.
    const [loadKey, setLoadKey] = React.useState(0);
    const fileInputRef = React.useRef<HTMLInputElement>(null);

    // Every failure path goes through here so the shell hears about it too.
    const fail = React.useCallback((message: string) => {
        setError(message);
        postToShell({type: "error", message});
    }, []);

    const loadJson = React.useCallback(
        (raw: string, name: string) => {
            try {
                const parsed = JSON.parse(raw);
                const parsedItems = toItems(parsed);
                if (parsedItems.length === 0) {
                    fail("The file did not contain any Perseus items.");
                    return;
                }
                setItems(parsedItems);
                setFileName(name);
                setError(null);
                setLoadKey((k) => k + 1);
                postToShell({
                    type: "loaded",
                    name,
                    items: parsedItems.map((it, index) => ({
                        index,
                        label: it.label ?? "",
                    })),
                });
            } catch (e: any) {
                fail(`Invalid JSON: ${e.message}`);
            }
        },
        [fail],
    );

    const handleFile = React.useCallback(
        (e: React.ChangeEvent<HTMLInputElement>) => {
            const file = e.target.files?.[0];
            if (!file) {
                return;
            }
            const reader = new FileReader();
            reader.onload = () => loadJson(String(reader.result), file.name);
            reader.onerror = () => fail(`Could not read file: ${file.name}`);
            reader.readAsText(file);
        },
        [loadJson, fail],
    );

    const loadSample = React.useCallback(() => {
        fetch("items.json")
            .then((r) => r.text())
            .then((raw) => loadJson(raw, "items.json (sample)"))
            .catch((e) => fail(`Could not load sample: ${e.message}`));
    }, [loadJson, fail]);

    // Expose the loaders to the native shell. Registered in an effect so the
    // functions exist only while the app is mounted, and re-registered if the
    // callbacks ever change identity.
    React.useEffect(
        () => registerShellAPI({loadJson, loadSample, scrollToItem}),
        [loadJson, loadSample],
    );

    // Tell the shell we are mounted. This runs after the registration effect
    // above (effects run in declaration order), so by the time the shell sees
    // "ready" the API is in place. Harmless in a browser.
    React.useEffect(() => {
        postToShell({type: "ready"});
    }, []);

    // Load the bundled sample on first mount so the grid isn't empty.
    React.useEffect(() => {
        loadSample();
    }, [loadSample]);

    return (
        <div className="app">
            <header className="app-header">
                <h1>Perseus Renderer</h1>
                <p>
                    Load a <code>.json</code> file containing a Perseus item or
                    an array of items, and interact with them below.
                </p>
            </header>

            <div className="toolbar">
                {/* The native shell has its own Open and Load sample buttons,
                    so the web ones only appear in a plain browser. */}
                {!hosted && (
                    <>
                        <button
                            type="button"
                            className="btn btn-primary"
                            onClick={() => fileInputRef.current?.click()}
                        >
                            Choose .json file…
                        </button>
                        <button
                            type="button"
                            className="btn"
                            onClick={loadSample}
                        >
                            Load sample
                        </button>
                        <input
                            ref={fileInputRef}
                            type="file"
                            accept=".json,application/json"
                            onChange={handleFile}
                            style={{display: "none"}}
                        />
                    </>
                )}
                {fileName && (
                    <span className="file-name">
                        {fileName} — {items.length}{" "}
                        {items.length === 1 ? "item" : "items"}
                    </span>
                )}
            </div>

            {error && <div className="error">{error}</div>}

            {items.length === 0 && !error ? (
                <p className="empty">Nothing loaded yet.</p>
            ) : (
                <div className="item-grid">
                    {items.map(({item, label}, i) => (
                        <section
                            className="item-card"
                            key={`${loadKey}-${i}`}
                            id={itemElementId(i)}
                        >
                            <div className="item-card-header">
                                Item {i + 1}
                                {label && (
                                    <span className="item-card-label">
                                        {" "}
                                        · {label}
                                    </span>
                                )}
                            </div>
                            <div className="item-card-body">
                                <PerseusItemRenderer
                                    item={item}
                                    index={i}
                                    renderKey={loadKey}
                                />
                            </div>
                        </section>
                    ))}
                </div>
            )}
        </div>
    );
}
