import type {
    PerseusDependencies,
    PerseusDependenciesV2,
} from "@khanacademy/perseus";

import {TeX} from "./tex";

// The "V1" dependencies are registered globally via Dependencies.setDependencies().
// This mirrors Perseus's own `testing/test-dependencies.tsx`, but wires in a real
// MathJax-backed TeX component and a pass-through staticUrl so CDN images resolve.
export const dependencies: PerseusDependencies = {
    JIPT: {useJIPT: false},
    graphieMovablesJiptLabels: {addLabel: () => {}},
    svgImageJiptLabels: {addLabel: () => {}},
    rendererTranslationComponents: {
        addComponent: () => -1,
        removeComponentAtIndex: () => {},
    },

    TeX,

    // Perseus content references assets like "web+graphie://ka-perseus-graphie/…"
    // and "https://cdn.kastatic.org/…". We pass URLs through unchanged.
    staticUrl: ((str?: string | null) => str ?? "") as any,

    useVideo: () => ({status: "loading"}),

    InitialRequestUrl: {
        origin: "https://www.khanacademy.org",
        host: "www.khanacademy.org",
        protocol: "https",
    },

    isDevServer: true,
    kaLocale: "en",

    Log: {log: () => {}, error: () => {}},
};

// The "V2" dependencies are passed directly to <ServerItemRenderer dependencies={…} />.
export const dependenciesV2: PerseusDependenciesV2 = {
    analytics: {onAnalyticsEvent: async () => {}},
    generateUrl: (args) => args.url,
    useVideo: () => ({status: "success", data: {video: null}}),
};
