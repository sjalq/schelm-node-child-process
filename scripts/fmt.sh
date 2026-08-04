#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FORMAT=${SCHELM_ELM_FORMAT:-}
if test -z "$FORMAT"; then FORMAT=$(command -v elm-format || true); fi
if test -z "$FORMAT"; then echo "elm-format not found; set SCHELM_ELM_FORMAT" >&2; exit 127; fi
# Frozen differential callers intentionally retain their audited 1.0 bytes.
TARGETS="$ROOT/fixtures/unauthorized-author/src/Unauthorized"
if test "${1:-}" = --validate; then exec "$FORMAT" --validate $TARGETS; fi
exec "$FORMAT" --yes $TARGETS
