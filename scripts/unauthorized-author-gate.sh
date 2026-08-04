#!/bin/sh
set -eu
ELM=${SCHELM_ELM:-/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author/result/bin/elm}
COMPILER_ROOT=${SCHELM_COMPILER_ROOT:-/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author}
HTTP=${SCHELM_HTTP_CLIENT_WORKTREE:-/home/s.dormehl/git/schelm/.worktrees/program-foundation/packages/node-http-client/.worktrees/schelm-node-http-client-v1}
HOME_DIR=$(node "$HTTP/scripts/prepare-overlay.cjs")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -R "$COMPILER_ROOT/fixtures/kernel-authorization/unauthorized-author" "$WORK/fixture"
for mode in debug optimize; do
  args=
  test "$mode" = optimize && args=--optimize
  if (cd "$WORK/fixture" && ELM_HOME="$HOME_DIR" "$ELM" make src/Unauthorized/KernelFixture.elm $args --output="$WORK/$mode.js") >"$WORK/$mode.out" 2>"$WORK/$mode.err"; then
    echo "unauthorized author unexpectedly compiled in $mode" >&2
    exit 1
  fi
  grep -q 'Elm.Kernel.UnauthorizedFixture' "$WORK/$mode.out" "$WORK/$mode.err"
  echo "PASS_UNAUTHORIZED_AUTHOR_$mode"
done
