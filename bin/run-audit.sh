#!/usr/bin/env bash
# End-to-end pipeline. Each phase gates the next: a failed gate stops the run
# rather than letting later phases build on a broken baseline.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
export AUDIT_ENV="${AUDIT_ENV:-audit.env}"

started=$(date +%s)
echo "Webbin audit pipeline -- config: $AUDIT_ENV"

bin/phase1-env.sh
bin/phase2-routes.sh
bin/phase3-mirror.sh
bin/phase4-crawl.sh
set +e; bin/phase5-analyze.sh; p5=$?; set -e

if [ "$AUDIT_ENV" = "fixture/fixture.env" ]; then
  # The fixture plants a CRITICAL secret deliberately, so the phase-5 halt is
  # the expected result here and must not prevent the self-test from running.
  # On a real target there is no answer key -- which is the whole reason the
  # fixture exists.
  bin/verify-fixture.sh
  [ "$p5" -eq 2 ] && echo "  (phase 5 halted on the planted CRITICAL, as designed)"
elif [ "$p5" -ne 0 ]; then
  exit "$p5"
fi

printf '\nAll gates passed in %ds. Write up findings in FINDINGS.md.\n' "$(( $(date +%s) - started ))"
