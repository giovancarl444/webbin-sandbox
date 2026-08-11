#!/usr/bin/env bash
# Full engine regression. Run this after any change to a phase or scanner.
#
# Two fixtures, because one is not enough:
#   fixture/site  -- 17 planted defects. Proves the detectors fire.
#   fixture/bare  -- nothing to find. Proves the pipeline survives an empty
#                    result, which is where three phases died against real
#                    systems: grep and rg exit 1 on no matches, and pipefail
#                    turned the most common real-world outcome into a dead phase.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"

bin/fixture-up.sh >/dev/null || { echo "fixtures failed to start" >&2; exit 1; }
fail=0

echo "=== 1/2  negative fixture: empty results must not break the run ==="
if AUDIT_ENV=fixture/bare.env bin/run-audit.sh >/tmp/neg.log 2>&1; then
  echo "  all gates passed with zero findings"
  grep -cE 'GATE PASS' /tmp/neg.log | xargs -I{} echo "  {} gates passed"
else
  echo "  FAILED -- see /tmp/neg.log"; tail -5 /tmp/neg.log | sed 's/^/  /'; fail=1
fi

# Positive last, so the working tree is left holding the baseline artifacts
# that FINDINGS.md actually describes rather than the bare fixture's zeros.
echo "=== 2/2  positive fixture: detectors must fire ==="
if AUDIT_ENV=fixture/fixture.env bin/run-audit.sh >/tmp/pos.log 2>&1; then
  grep -E 'passed, .* failed' /tmp/pos.log | sed 's/^/  /'
else
  echo "  FAILED -- see /tmp/pos.log"; tail -5 /tmp/pos.log | sed 's/^/  /'; fail=1
fi

echo
[ "$fail" -eq 0 ] && echo "ENGINE OK: both fixtures pass." || echo "ENGINE REGRESSION -- do not ship." >&2
exit "$fail"
