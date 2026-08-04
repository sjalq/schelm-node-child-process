#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT/scripts/run-feasibility.sh"
ELM=${SCHELM_ELM:-/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author/result/bin/elm}
HTTP=${SCHELM_HTTP_CLIENT_WORKTREE:-/home/s.dormehl/git/schelm/.worktrees/program-foundation/packages/node-http-client/.worktrees/schelm-node-http-client-v1}
HOME_DIR=$(node "$HTTP/scripts/prepare-overlay.cjs")
PKG="$HOME_DIR/0.19.2/packages/sjalq/schelm-node-child-process/1.0.0"
mkdir -p "$PKG"; cp -R "$ROOT/src" "$PKG/src"; cp "$ROOT/elm.json" "$ROOT/README.md" "$PKG/"
node /home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author/scripts/add-private-fixture-to-registry.cjs "$HOME_DIR/0.19.2/packages/registry.dat" sjalq schelm-node-child-process
cd "$ROOT/fixtures/feasibility"; rm -rf elm-stuff
ELM_HOME="$HOME_DIR" "$ELM" make src/BuilderMain.elm --output=/tmp/schelm-child-builder-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/BuilderMain.elm --optimize --output=/tmp/schelm-child-builder-opt.js >/dev/null
node "$ROOT/tests/builders.cjs" /tmp/schelm-child-builder-debug.js
node "$ROOT/tests/builders.cjs" /tmp/schelm-child-builder-opt.js
ELM_HOME="$HOME_DIR" "$ELM" make src/RunMain.elm --output=/tmp/schelm-child-run-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/RunMain.elm --optimize --output=/tmp/schelm-child-run-opt.js >/dev/null
node "$ROOT/tests/run-worker.cjs" /tmp/schelm-child-run-debug.js
node "$ROOT/tests/run-worker.cjs" /tmp/schelm-child-run-opt.js
! grep -nE 'process\.(on|once)\(' "$ROOT/src/Elm/Kernel/SchelmChildProcess.js"
printf 'compiler '; sha256sum "$ELM"
printf 'debug '; sha256sum /tmp/schelm-child-builder-debug.js
printf 'optimize '; sha256sum /tmp/schelm-child-builder-opt.js
