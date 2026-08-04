#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ELM=${SCHELM_ELM:-/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author/result/bin/elm}
HTTP=${SCHELM_HTTP_CLIENT_WORKTREE:-/home/s.dormehl/git/schelm/.worktrees/program-foundation/packages/node-http-client/.worktrees/schelm-node-http-client-v1}
HOME_DIR=$(node "$HTTP/scripts/prepare-overlay.cjs")
PKG="$HOME_DIR/0.19.2/packages/sjalq/schelm-node-child-process/1.0.0"
mkdir -p "$PKG"
cp -R "$ROOT/src" "$PKG/src"
cp "$ROOT/elm.json" "$ROOT/README.md" "$PKG/"
node /home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author/scripts/add-private-fixture-to-registry.cjs "$HOME_DIR/0.19.2/packages/registry.dat" sjalq schelm-node-child-process
cd "$ROOT/fixtures/feasibility"
rm -rf elm-stuff
ELM_HOME="$HOME_DIR" "$ELM" make src/Main.elm --output=debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/Main.elm --optimize --output=optimize.js >/dev/null
node run.cjs debug.js
node run.cjs optimize.js
rm -f debug.js optimize.js
printf '%s\n' FEASIBILITY_OK_DEBUG_OPTIMIZE
