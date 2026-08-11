#!/usr/bin/env bash
# Phase 5 -- analysis driver.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
printf '\n=== Phase 5: analysis ===\n'
mkdir -p findings

# Secrets runs LAST on purpose. It is the only scanner that halts, and halting
# it first would throw away every other check. The phase still stops -- the
# non-zero exit propagates and Phase 6 never runs -- but the operator gets the
# complete picture alongside the CRITICAL rather than instead of it.
secret_rc=0
for s in sourcemaps deps headers thirdparty sri-csp sinks errors secrets; do
  "bin/scan-$s.sh" || { rc=$?; [ "$s" = secrets ] && secret_rc=$rc || {
      echo "  scan-$s.sh failed (exit $rc)" >&2; exit "$rc"; }; }
done

echo
missing=0
for f in sourcemaps.md dependencies.md headers.md third-party.md sri-csp.md dom-sinks.md errors.md secrets.md; do
  if [ -s "findings/$f" ]; then printf '  %-20s %s bytes\n' "$f" "$(wc -c < "findings/$f")"
  else echo "  $f MISSING"; missing=1; fi
done

[ "$missing" -eq 0 ] || { echo "GATE FAIL: findings/ incomplete" >&2; exit 3; }
if [ "$secret_rc" -ne 0 ]; then
  echo
  echo "GATE HALT: CRITICAL credential material found. See findings/SECRETS.md." >&2
  echo "Rotate before anything else. Phase 6 will not run." >&2
  exit "$secret_rc"
fi
echo "GATE PASS: findings/ complete, no CRITICAL secrets."
