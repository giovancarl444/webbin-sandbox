#!/usr/bin/env bash
# Fidelity ledger: what in this sandbox copy is faithful to production, and
# what is not.
#
# This is what lets us claim results without hedging. A finding from an
# imported system is only a claim about the client's production system to the
# extent the copy matches it. Anything we substituted is recorded here, so a
# finding that depends on a substitution can be labelled instead of asserted.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
NAME="${1:?usage: import-ledger.sh <name>}"
META="imports/_meta"; M="$META/$NAME.json"
OUT="$META/$NAME-ledger.md"
[ -f "$M" ] || { echo "no import metadata for '$NAME'" >&2; exit 2; }

q() { jq -r "$1" "$M"; }
src_routes=$( [ -f "$META/$NAME-routes.txt" ] && wc -l < "$META/$NAME-routes.txt" || echo 0 )
crawled=$( [ -f crawl.log ] && grep -c '^OK' crawl.log || echo 0 )

{
  echo "# Fidelity ledger — $NAME"
  echo
  echo "Source: \`$(q .source)\` at commit \`$(q .profile.sha)\`"
  echo
  echo "| Dimension | State | Claims derived from it |"
  echo "|---|---|---|"

  # Commit pinning is what makes a finding re-checkable months later.
  echo "| Source revision | pinned \`$(q '.profile.sha' | cut -c1-12)\` | **Transferable** — exact tree is reproducible |"

  if [ "$(q .runtime_ok)" = "true" ]; then
    echo "| Runtime | matches declared \`$(q '.profile.node_required // "unconstrained"')\` | **Transferable** |"
  else
    echo "| Runtime | **DIVERGENT** — repo declares \`$(q .profile.node_required)\`, sandbox ran node $(node -p 'process.versions.node') | **Not transferable** for build-output findings (bundle contents, dependency tree) |"
  fi

  if [ "$(q .env_placeholders)" = "0" ]; then
    echo "| Configuration | no substitutions | **Transferable** |"
  else
    echo "| Configuration | **$(q .env_placeholders) values replaced with placeholders** | **Not transferable** for anything gated on real credentials or third-party integrations |"
  fi

  svc="$(q '.profile.services | join(", ")')"
  if [ -z "$svc" ]; then
    echo "| Data layer | none declared | n/a |"
  else
    echo "| Data layer | declared: $svc | Verify provisioning before claiming backend results |"
  fi

  echo "| Build | $( [ "$(q .build_ok)" = "true" ] && echo "succeeded" || echo "**FAILED**" ) | $( [ "$(q .build_ok)" = "true" ] && echo "Frontend findings valid for this build" || echo "**No frontend claim is valid**" ) |"
  echo "| Route coverage | $crawled of $src_routes source routes crawled | Findings cover only crawled routes |"
  echo "| Origin | loopback sandbox copy | Network-layer findings (TLS, CDN, edge headers) **do not transfer** — they belong to the client's edge, not this copy |"

  # Discovered from a real run: the sandbox's egress proxy reset connections to
  # a CDN the page depends on, producing console errors that belong to our
  # network, not the client's code. Without this row those get reported as
  # client bugs -- precisely the inconsistency this ledger exists to prevent.
  egress_fail=0
  [ -f .audit-raw/console.jsonl ] && egress_fail="$(jq -r 'select(.text | test("net::ERR_|Failed to load resource")) | .text' \
      .audit-raw/console.jsonl 2>/dev/null | wc -l || echo 0)"
  ext_origins="$( [ -d har ] && jq -r '.log.entries[].request.url' har/*.har 2>/dev/null \
      | sed -E 's#^([a-z]+://[^/]+).*#\1#' | grep -v '127.0.0.1\|localhost' | sort -u | wc -l || echo 0)"
  if [ "${egress_fail:-0}" -gt 0 ]; then
    echo "| External egress | **RESTRICTED** — $egress_fail failed third-party loads across $ext_origins external origin(s) | Console and network-error findings are **contaminated**: failures caused by this sandbox's proxy, not by client code. Re-confirm against production before reporting any of them as bugs |"
  elif [ "${ext_origins:-0}" -gt 0 ]; then
    echo "| External egress | reachable ($ext_origins external origin(s)) | **Transferable** |"
  else
    echo "| External egress | no external dependencies | n/a |"
  fi

  echo
  echo "## Recorded divergences"
  echo
  n="$(jq -r '.divergences | length' "$M")"
  if [ "$n" = "0" ]; then echo "None. Every dimension above is faithful."
  else jq -r '.divergences[] | "- " + .' "$M"; fi

  echo
  echo "## Setup cost"
  echo
  echo "| Stage | Seconds |"
  echo "|---|---|"
  jq -r '.timings_sec | to_entries[] | "| \(.key) | \(.value) |"' "$M"

  echo
  echo "## How to read this"
  echo
  echo "A finding produced against this copy is a claim about the client's production"
  echo "system **only** on dimensions marked Transferable. Where a dimension is"
  echo "divergent, the finding still matters — it is real in the code — but it must be"
  echo "confirmed against production before it goes in a client report."
  echo
  echo "Headers, TLS and CDN behaviour are the clearest case: this copy is served by a"
  echo "local process, so their absence here says nothing about the client's edge. Those"
  echo "must come from a passive pass against the live origin (\`bin/run-audit.sh\`)."
} > "$OUT"

echo "  ledger -> $OUT"
# Count every caveat phrasing, not just one. `|| true` because zero matches is
# grep exit 1, and a fully faithful import is the good outcome, not an error.
flagged="$({ grep -cE 'Not transferable|do not transfer|contaminated' "$OUT" || true; })"
echo "  $flagged dimension(s) carry a transferability caveat"
exit 0
