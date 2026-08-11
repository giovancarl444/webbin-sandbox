#!/usr/bin/env bash
# Console and network errors. This is the BUG list, kept deliberately separate
# from the security findings. Inflating a broken image into a vulnerability
# devalues the report.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"
mkdir -p findings

{
  echo "# Console and network errors (bugs, not security findings)"
  echo
  echo "## JavaScript errors"
  echo
  echo "| Kind | Route | Message |"
  echo "|---|---|---|"
} > findings/errors.md

js=0
if [ -s .audit-raw/console.jsonl ]; then
  js="$(jq -s 'length' .audit-raw/console.jsonl)"
  jq -r '[.kind, .url, (.text | gsub("[|\n\r]"; " ") | .[0:140])] | @tsv' .audit-raw/console.jsonl \
    | sort -u | awk -F'\t' '{ printf "| %s | `%s` | %s |\n", $1, $2, $3 }' >> findings/errors.md
fi
[ "$js" -eq 0 ] && echo "| - | no JavaScript errors | - |" >> findings/errors.md

{
  echo
  echo "## Failed requests (4xx / 5xx)"
  echo
  echo "| Status | Method | URL |"
  echo "|---|---|---|"
} >> findings/errors.md

net="$(jq -r '.log.entries[]
        | select(.response.status >= 400)
        | [(.response.status|tostring), .request.method, .request.url] | @tsv' har/*.har 2>/dev/null \
      | sort -u | tee .audit-raw/http-errors.tsv | wc -l)"
awk -F'\t' '{ printf "| %s | %s | `%s` |\n", $1, $2, $3 }' .audit-raw/http-errors.tsv >> findings/errors.md
[ "$net" -eq 0 ] && echo "| - | no failed requests | - |" >> findings/errors.md

{
  echo
  echo "JavaScript errors: $js. Failed requests: $net."
  echo
  echo "These are correctness and reliability defects. They are listed here so they"
  echo "are not confused with the security findings, and so they are not lost."
} >> findings/errors.md
echo "  js errors=$js failed requests=$net -> findings/errors.md"
