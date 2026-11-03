import {
    KeypadContext,
    StatefulKeypadContextProvider,
} from "@khanacademy/keypad-context";
import {MobileKeypad} from "@khanacademy/math-input";
import {
    PerseusI18nContextProvider,
    ServerItemRenderer,
} from "@khanacademy/perseus";
import {mockStrings} from "@khanacademy/perseus/strings";
import {scorePerseusItem} from "@khanacademy/perseus-score";
import * as React from "react";

import {dependenciesV2} from "./perseus-deps";
import {postToShell} from "./shell";

import type {PerseusItem, PerseusScore} from "@khanacademy/perseus-core";

type Props = {
    item: PerseusItem;
    // Position in the loaded list, so the shell can match scores to items.
    index: number;
    // Bumped by the parent on each new render to force a fresh renderer.
    renderKey: number;
};

function scoreText(score: PerseusScore): {text: string; ok: boolean} {
    if (score.type === "invalid") {
        return {text: score.message || "Answer is not complete.", ok: false};
    }
    const ok = score.earned >= score.total;
    return {
        text: ok
            ? "Correct! 🎉"
            : `Not quite — ${score.earned}/${score.total} points.`,
        ok,
    };
}

export function PerseusItemRenderer({
    item,
    index,
    renderKey,
}: Props): React.ReactElement {
    const ref = React.useRef<any>(null);
    const [score, setScore] = React.useState<PerseusScore | null>(null);
    const [showSolutions, setShowSolutions] = React.useState<
        "none" | "all" | "selected"
    >("none");

    // Reset transient state whenever a new item is rendered.
    React.useEffect(() => {
        setScore(null);
        setShowSolutions("none");
    }, [renderKey]);

    const handleCheck = () => {
        const userInput = ref.current?.getUserInput();
        const result = scorePerseusItem(item.question, userInput, "en");
        setScore(result);
        if (result.type === "points") {
            setShowSolutions("selected");
        }
        // Mirror the on-screen verdict to the shell so its sidebar can mark
        // the item. "invalid" means the answer was incomplete, not wrong.
        const {text, ok} = scoreText(result);
        postToShell({
            type: "score",
            index,
            result:
                result.type === "invalid"
                    ? "invalid"
                    : ok
                      ? "correct"
                      : "incorrect",
            earned: result.type === "points" ? result.earned : 0,
            total: result.type === "points" ? result.total : 0,
            message: text,
        });
    };

    const handleReset = () => {
        setScore(null);
        setShowSolutions("none");
        postToShell({type: "reset", index});
    };

    const summary = score ? scoreText(score) : null;

    return (
        <PerseusI18nContextProvider strings={mockStrings} locale="en">
        <StatefulKeypadContextProvider>
            <KeypadContext.Consumer>
                {({keypadElement, setKeypadElement, renderer}) => (
                    <div>
                        <div className="framework-perseus">
                            <ServerItemRenderer
                                key={renderKey}
                                ref={ref}
                                problemNum={0}
                                item={item}
                                dependencies={dependenciesV2}
                                apiOptions={{
                                    isMobile: false,
                                    showSolutions,
                                }}
                                keypadElement={keypadElement}
                                showSolutions={showSolutions}
                            />
                        </div>

                        <div className="controls">
                            <button
                                type="button"
                                className="btn btn-primary"
                                onClick={handleCheck}
                            >
                                Check answer
                            </button>
                            <button
                                type="button"
                                className="btn"
                                onClick={handleReset}
                            >
                                Reset
                            </button>
                            {summary && (
                                <span
                                    className={
                                        summary.ok
                                            ? "score score-ok"
                                            : "score score-bad"
                                    }
                                >
                                    {summary.text}
                                </span>
                            )}
                        </div>

                        <MobileKeypad
                            onElementMounted={setKeypadElement}
                            onDismiss={() => renderer?.blur()}
                            onAnalyticsEvent={async () => {}}
                        />
                    </div>
                )}
            </KeypadContext.Consumer>
        </StatefulKeypadContextProvider>
        </PerseusI18nContextProvider>
    );
}
