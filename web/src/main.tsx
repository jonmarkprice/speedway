import {Dependencies, init} from "@khanacademy/perseus";
import {RenderStateRoot} from "@khanacademy/wonder-blocks-core";
import {createRoot} from "react-dom/client";

import {App} from "./App";
import {dependencies} from "./perseus-deps";

// Wonder Blocks CSS variables — REQUIRED for Wonder Blocks components (used by
// many Perseus widgets) to render with correct borders, spacing, and colors.
import "@khanacademy/wonder-blocks-tokens/styles.css";
// Perseus styles + MathJax styles.
import "@khanacademy/perseus/styles.css";
import "@khanacademy/mathjax-renderer/src/css/mathjax.css";
import "@khanacademy/mathjax-renderer/src/css/safari-hacks.css";
import "@khanacademy/mathjax-renderer/src/css/selectable.css";
import "./styles.css";

// Register all built-in Perseus widgets and provide the global dependencies.
init();
Dependencies.setDependencies(dependencies);

// NOTE: We intentionally don't wrap in <React.StrictMode>. Perseus's internals
// use some legacy patterns (string refs, findDOMNode) that trigger noisy
// StrictMode dev warnings we can't fix from here.
createRoot(document.getElementById("root")!).render(
    <RenderStateRoot>
        <App />
    </RenderStateRoot>,
);
