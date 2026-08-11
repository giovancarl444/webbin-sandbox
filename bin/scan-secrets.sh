#!/usr/bin/env bash
# Secret scan. Redaction happens in-process: the raw matched value is never
# printed, never written to a file, and never reaches a log. Only a short
# identifying prefix plus path:line survives, which is enough for a human to
# open the (gitignored) mirror and confirm.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"
mkdir -p findings

OUT=findings/secrets.md
TARGETS=(mirror-raw rendered)
echo "  scanning ${TARGETS[*]} against $(grep -vc '^#' patterns/secrets.tsv) patterns"

hits=.audit-raw/secret-hits.tsv
: > "$hits"
while IFS=$'\t' read -r sev label re; do
  [ -z "${sev:-}" ] && continue
  case "$sev" in \#*) continue ;; esac
  rg --json --no-messages -g '!*.png' -g '!*.har' -e "$re" "${TARGETS[@]}" 2>/dev/null \
    | jq -r --arg sev "$sev" --arg lab "$label" '
        select(.type == "match") | .data as $d | $d.submatches[] | .match.text as $m
        | ($m | length) as $n
        # Truncation scales with length so short values never leak a usable
        # fraction of themselves.
        | (if $n < 12 then $m[0:4] + "…"
           elif $n < 24 then $m[0:8] + "…"
           else $m[0:10] + "…" + $m[-4:] end) as $red
        | [$sev, $lab, $d.path.text, ($d.line_number | tostring), $red] | @tsv' \
    >> "$hits" || true
done < patterns/secrets.tsv

sort -u -o "$hits" "$hits"
crit=$(awk -F'\t' '$1=="CRITICAL"' "$hits" | wc -l)
high=$(awk -F'\t' '$1=="HIGH"'     "$hits" | wc -l)
med=$(awk  -F'\t' '$1=="MEDIUM"'   "$hits" | wc -l)
info=$(awk -F'\t' '$1=="INFO"'     "$hits" | wc -l)

{
  echo "# Secrets scan"
  echo
  echo "Values are redacted at the point of detection. To confirm a hit, open the"
  echo "cited path:line in the local (gitignored) mirror -- never paste the value."
  echo
  echo "| Severity | Pattern | Evidence (path:line) | Redacted |"
  echo "|---|---|---|---|"
  for s in CRITICAL HIGH MEDIUM INFO; do
    awk -F'\t' -v s="$s" '$1==s { printf "| %s | %s | `%s:%s` | `%s` |\n", $1, $2, $3, $4, $5 }' "$hits"
  done
  echo
  echo "Totals: CRITICAL=$crit HIGH=$high MEDIUM=$med INFO=$info"
  echo
  echo "## Triage notes"
  echo
  echo "- INFO rows are **not** findings. Publishable keys, Sentry DSNs and Firebase"
  echo "  web config are designed to ship in client code. Reporting them as leaks"
  echo "  buries the findings that matter."
  echo "- MEDIUM is a generic assignment pattern with a deliberately high"
  echo "  false-positive rate; each row needs a human look."
  echo "- A CRITICAL hit means rotate first, then report. Anything shipped to a"
  echo "  browser must be assumed already harvested."
} > "$OUT"

echo "  CRITICAL=$crit HIGH=$high MEDIUM=$med INFO=$info -> $OUT"

# Halt protocol: a live-credential class hit stops this phase.
if [ "$crit" -gt 0 ]; then
  {
    echo "# CRITICAL: credential material in publicly served files"
    echo
    echo "Detected $crit high-confidence credential(s) in files any anonymous"
    echo "visitor can download. Values below are redacted."
    echo
    echo "| Pattern | Evidence (path:line) | Redacted |"
    echo "|---|---|---|"
    awk -F'\t' '$1=="CRITICAL" { printf "| %s | `%s:%s` | `%s` |\n", $2, $3, $4, $5 }' "$hits"
    echo
    echo "## Required actions, in order"
    echo "1. **Rotate the credential now.** It has been publicly served; assume harvested."
    echo "2. Audit the provider's access logs for use from unexpected addresses."
    echo "3. Remove it from the build output; move it behind a server-side call."
    echo "4. Only then re-run this pipeline to confirm."
  } > findings/SECRETS.md
  echo "  HALT: $crit CRITICAL hit(s). See findings/SECRETS.md" >&2
  exit 2
fi
