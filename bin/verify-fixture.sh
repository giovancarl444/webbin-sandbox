#!/usr/bin/env bash
# Asserts the pipeline detected every defect planted in the fixture.
#
# This is the check that gives the rest of the pipeline meaning. Without it,
# "no findings" and "the scanner silently broke" produce identical output --
# and three scanners in this repo have already failed exactly that way during
# development while still reporting a passing gate.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"

printf '\n=== Fixture verification (detector self-test) ===\n'
pass=0; fail=0
while IFS=$'\t' read -r id file needle desc; do
  case "${id:-}" in ''|\#*) continue ;; esac
  if [ -f "$file" ] && grep -qF -- "$needle" "$file"; then
    printf '  PASS  %-8s %s\n' "$id" "$desc"; pass=$((pass + 1))
  else
    printf '  FAIL  %-8s %s\n' "$id" "$desc"
    printf '        expected %s to contain %s\n' "$file" "$needle"; fail=$((fail + 1))
  fi
done < fixture/expected.tsv

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ] || { echo "GATE FAIL: the pipeline missed planted defects -- detectors are broken." >&2; exit 3; }
echo "GATE PASS: every planted defect was detected."
