import {MathJaxRenderer} from "@khanacademy/mathjax-renderer";
import * as React from "react";

// A single shared renderer instance. Adapted from Perseus's own
// `testing/test-mathjax.tsx` harness.
//
// The MathJax TeX fonts are copied from mathjax-full into public/fonts/mathjax
// (see the README) so math renders offline, which matters for the Swift shell.
// The path is relative to the document so it works both from the dev server
// and from the shell's perseus://app/ origin.
const renderer = new MathJaxRenderer({
    shouldFixUnicodeLayout: true,
    fontURL: "./fonts/mathjax",
    locale: "en",
});

type Props = {
    children: React.ReactNode;
    onRender?: (root?: any) => unknown;
};

/**
 * The `TeX` dependency Perseus uses to render math. Perseus passes the raw TeX
 * string as `children`, which we hand to the MathJax renderer.
 */
export function TeX({children, onRender}: Props): React.ReactElement {
    const tex = typeof children === "string" ? children : "";
    const ref = React.useRef<HTMLSpanElement>(null);

    const {domElement} = React.useMemo(() => renderer.render(tex), [tex]);

    React.useLayoutEffect(() => {
        if (ref.current) {
            ref.current.innerHTML = "";
            ref.current.appendChild(domElement);
        }
    }, [domElement]);

    React.useEffect(() => {
        renderer.updateStyles();
        onRender?.();
    }, [tex, onRender]);

    return <span ref={ref} />;
}
