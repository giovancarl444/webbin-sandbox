#!/usr/bin/env bash
# Phase 1 -- environment. Every tool the pipeline depends on must print a
# version here. Anything missing is reported, never worked around silently.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
check() { # label, command...
  local label="$1"; shift
  local out
  if out="$("$@" 2>&1 | head -1)"; then
    printf '  %-24s %s\n' "$label" "$out"
  else
    printf '  %-24s MISSING (%s)\n' "$label" "$*"; fail=1
  fi
}

echo "System tools:"
check wget      wget --version
check curl      curl --version
check jq        jq --version
check ripgrep   rg --version
check node      node --version
check python3   python3 --version

echo "Pipeline dependencies (local, not global):"
check playwright npx --no-install playwright --version
check retire     npx --no-install retire --version

echo "Browser:"
if [ -x "${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}/chromium" ]; then
  printf '  %-24s %s\n' "chromium" \
    "$("${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}/chromium" --version 2>&1 | head -1)"
else
  printf '  %-24s MISSING\n' "chromium"; fail=1
fi
node -e 'require("playwright").chromium.launch({headless:true})
  .then(async b => { console.log("  launch check             ok, chromium " + b.version()); await b.close(); })
  .catch(e => { console.log("  launch check             FAILED: " + e.message); process.exit(1); })' || fail=1

# Node >= 20 is a hard requirement (crawl.js uses modern syntax).
major="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$major" -lt 20 ]; then echo "  node $major is below the required 20"; fail=1; fi

echo
if [ "$fail" -eq 0 ]; then echo "GATE PASS: all tools present."; else echo "GATE FAIL: see MISSING above." >&2; fi
exit "$fail"
