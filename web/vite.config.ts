import react from "@vitejs/plugin-react";
import {defineConfig} from "vite";

// Several Khan Academy packages reference `process.env.NODE_ENV` and a global
// `process` object at runtime. Vite doesn't provide those in the browser, so we
// shim them here.
export default defineConfig({
    // Emit relative asset URLs ("./assets/...") instead of root-absolute ones.
    // The Swift shell serves the built bundle from a custom URL scheme
    // (perseus://app/index.html), and absolute "/assets/..." paths would also
    // work there, but relative paths let the same dist/ be opened from any
    // sub-path or from disk, so it is the safer default for an embedded bundle.
    base: "./",
    plugins: [react()],
    define: {
        "process.env.NODE_ENV": JSON.stringify("development"),
        "process.env": "{}",
        global: "globalThis",
    },
    server: {
        port: 5180,
    },
});
