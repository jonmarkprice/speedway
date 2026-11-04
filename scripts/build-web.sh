#!/usr/bin/env bash
# Builds the React app in the sibling perseus-renderer repo and copies its dist/
# into this package's resources, where the scheme handler serves it from
# perseus://app/. Run this before `swift run`, and again after web changes.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
# Override with PERSEUS_RENDERER_DIR if the web repo lives somewhere else.
web_src="${PERSEUS_RENDERER_DIR:-$here/../perseus-renderer}"
dest="$here/Sources/PerseusShellKit/Resources/Web"

if [[ ! -f "$web_src/package.json" ]]; then
    echo "build-web.sh: no perseus-renderer checkout at $web_src" >&2
    echo "  Set PERSEUS_RENDERER_DIR to the web repo's path." >&2
    exit 1
fi
if [[ ! -d "$web_src/node_modules" ]]; then
    echo "build-web.sh: $web_src has no node_modules; run npm install there first." >&2
    exit 1
fi

echo "build-web.sh: building $web_src"
(cd "$web_src" && npm run build)

# The shell loads perseus://app/index.html and resolves assets relative to it,
# so refuse a bundle whose index.html still uses root-absolute asset paths
# (that means vite.config.ts lost its `base: "./"`).
if grep -Eq '(src|href)="/' "$web_src/dist/index.html"; then
    echo "build-web.sh: dist/index.html has root-absolute asset paths; set base: \"./\" in vite.config.ts" >&2
    exit 1
fi

mkdir -p "$dest"
# --delete keeps stale hashed assets from piling up across builds.
rsync -a --delete "$web_src/dist/" "$dest/"

count="$(find "$dest" -type f | wc -l | tr -d ' ')"
echo "build-web.sh: copied $count files to $dest"
