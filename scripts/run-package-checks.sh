#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT/scripts/run-feasibility.sh"
ELM=${SCHELM_ELM:-/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author/result/bin/elm}
HTTP=${SCHELM_HTTP_CLIENT_WORKTREE:-/home/s.dormehl/git/schelm/.worktrees/program-foundation/packages/node-http-client/.worktrees/schelm-node-http-client-v1}
HOME_DIR=$(node "$HTTP/scripts/prepare-overlay.cjs")
PKG="$HOME_DIR/0.19.2/packages/sjalq/schelm-node-child-process/1.1.0"
ELM_HOME="$HOME_DIR" "$ELM" make --docs=/tmp/schelm-child-docs.json >/dev/null
test -s /tmp/schelm-child-docs.json
mkdir -p "$PKG"; cp -R "$ROOT/src" "$PKG/src"; cp "$ROOT/elm.json" "$ROOT/README.md" "$PKG/"
node "$ROOT/scripts/add-private-v1-1-to-registry.cjs" "$HOME_DIR/0.19.2/packages/registry.dat" sjalq schelm-node-child-process
cd "$ROOT/fixtures/feasibility"; rm -rf elm-stuff
ELM_HOME="$HOME_DIR" "$ELM" make src/BuilderMain.elm --output=/tmp/schelm-child-builder-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/BuilderMain.elm --optimize --output=/tmp/schelm-child-builder-opt.js >/dev/null
node "$ROOT/tests/builders.cjs" /tmp/schelm-child-builder-debug.js
node "$ROOT/tests/builders.cjs" /tmp/schelm-child-builder-opt.js
ELM_HOME="$HOME_DIR" "$ELM" make src/RunMain.elm --output=/tmp/schelm-child-run-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/RunMain.elm --optimize --output=/tmp/schelm-child-run-opt.js >/dev/null
node "$ROOT/tests/run-worker.cjs" /tmp/schelm-child-run-debug.js
node "$ROOT/tests/run-worker.cjs" /tmp/schelm-child-run-opt.js
ELM_HOME="$HOME_DIR" "$ELM" make src/DemandMain.elm --output=/tmp/schelm-child-demand-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/DemandMain.elm --optimize --output=/tmp/schelm-child-demand-opt.js >/dev/null
node "$ROOT/tests/demand-worker.cjs" /tmp/schelm-child-demand-debug.js
node "$ROOT/tests/demand-worker.cjs" /tmp/schelm-child-demand-opt.js
ELM_HOME="$HOME_DIR" "$ELM" make src/ConformanceMain.elm --output=/tmp/schelm-child-conformance-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/ConformanceMain.elm --optimize --output=/tmp/schelm-child-conformance-opt.js >/dev/null
node "$ROOT/tests/conformance-worker.cjs" /tmp/schelm-child-conformance-debug.js
node "$ROOT/tests/conformance-worker.cjs" /tmp/schelm-child-conformance-opt.js
ELM_HOME="$HOME_DIR" "$ELM" make src/StdinRaceMain.elm --output=/tmp/schelm-child-stdin-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/StdinRaceMain.elm --optimize --output=/tmp/schelm-child-stdin-opt.js >/dev/null
for artifact in /tmp/schelm-child-stdin-debug.js /tmp/schelm-child-stdin-opt.js; do
  node "$ROOT/tests/stdin-race-worker.cjs" "$artifact" drain
  node "$ROOT/tests/stdin-race-worker.cjs" "$artifact" error
  node "$ROOT/tests/stdin-race-worker.cjs" "$artifact" close
done
ELM_HOME="$HOME_DIR" "$ELM" make src/RunFailureMain.elm --output=/tmp/schelm-child-runfailure-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/RunFailureMain.elm --optimize --output=/tmp/schelm-child-runfailure-opt.js >/dev/null
for artifact in /tmp/schelm-child-runfailure-debug.js /tmp/schelm-child-runfailure-opt.js; do
  node "$ROOT/tests/run-failure-worker.cjs" "$artifact" input
  node "$ROOT/tests/run-failure-worker.cjs" "$artifact" process
done
ELM_HOME="$HOME_DIR" "$ELM" make src/ScaleMain.elm --output=/tmp/schelm-child-scale-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/ScaleMain.elm --optimize --output=/tmp/schelm-child-scale-opt.js >/dev/null
node "$ROOT/tests/scale-worker.cjs" /tmp/schelm-child-scale-debug.js
node "$ROOT/tests/scale-worker.cjs" /tmp/schelm-child-scale-opt.js
node "$ROOT/tests/model/generated-model.test.cjs"
node "$ROOT/tests/model/parent-adapter.test.cjs"
ELM_HOME="$HOME_DIR" "$ELM" make src/ParentedMain.elm --output=/tmp/schelm-child-parented-debug.js >/dev/null
ELM_HOME="$HOME_DIR" "$ELM" make src/ParentedMain.elm --optimize --output=/tmp/schelm-child-parented-opt.js >/dev/null
node "$ROOT/tests/parented-worker.cjs" /tmp/schelm-child-parented-debug.js
node "$ROOT/tests/parented-worker.cjs" /tmp/schelm-child-parented-opt.js
node "$ROOT/tests/node/cleanup-oracle.test.cjs"
node "$ROOT/tests/node/process-groups.test.cjs"
! grep -nE 'process\.(on|once)\(' "$ROOT/src/Elm/Kernel/SchelmChildProcess.js"
printf 'compiler '; sha256sum "$ELM"
printf 'debug '; sha256sum /tmp/schelm-child-builder-debug.js
printf 'optimize '; sha256sum /tmp/schelm-child-builder-opt.js

cd "$ROOT"
SCHELM_ELM="$ELM" node tests/artifact-gate.cjs
node scripts/archive-gate.cjs
! grep -nE 'result\.\$|\.\$ === .(Err|Ok|Just|Nothing)' "$ROOT/src/Elm/Kernel/SchelmChildProcess.js"
