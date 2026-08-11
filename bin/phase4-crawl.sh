#!/usr/bin/env bash
# Phase 4 -- rendered crawl, then derive the backend handoff document.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"

log_phase "Phase 4: rendered crawl of $(wc -l < routes.txt) routes"
rm -rf rendered har; rm -f .audit-raw/websockets.txt .audit-raw/console.jsonl
timeout "$PHASE_TIMEOUT_SEC" node crawl.js || { echo "GATE FAIL: crawl.js exited non-zero" >&2; exit 3; }

routes=$(wc -l < routes.txt); html=$(find rendered -name '*.html' | wc -l)
png=$(find rendered -name '*.png' | wc -l); har=$(find har -name '*.har' | wc -l)
echo "  rendered html=$html png=$png har=$har for $routes routes"

# --- api-surface.txt: unique METHOD URL, static assets excluded -------------
# Playwright 1.56 does NOT emit _resourceType in HAR entries (verified: entry
# keys are request/response/timings/_securityDetails/_serverPort/_wasContinued
# /cache/pageref/serverIPAddress/startedDateTime/time). So every request is
# classified explicitly and anything unclassified is a gate failure -- an
# endpoint must never be dropped silently.
jq -r '.log.entries[] | "\(.request.method)\t\(.request.url)"' har/*.har 2>/dev/null \
  | sort -u > .audit-raw/har-requests.tsv

ASSET_RE='\.(js|mjs|css|png|jpe?g|gif|svg|ico|webp|avif|woff2?|ttf|eot|otf|mp4|webm|mp3|map)([?#]|$)'
awk -F'\t' -v assets="$ASSET_RE" -v cdn="${EXTRA_HOSTS:-}" '
  FNR==NR { nav[$0]=1; next }                       # routes.txt = navigations
  {
    url=$2; host=url; sub(/^[a-z]+:\/\//,"",host); sub(/\/.*$/,"",host)
    n=split(cdn,c,","); isCdn=0; for(i=1;i<=n;i++) if(c[i]!="" && host==c[i]) isCdn=1
    if (url ~ assets)      { a++; next }             # static asset
    if (url in nav)        { d++; next }             # page navigation
    if (isCdn)             { x++; next }             # third-party asset host
    print $1, url > "/tmp/.api"; k++
  }
  END { printf "  classified: %d asset, %d navigation, %d cdn, %d api\n", a, d, x, k }
' routes.txt .audit-raw/har-requests.tsv

{ cat /tmp/.api 2>/dev/null
  # WebSockets never appear in HAR, but a price feed is part of the surface.
  [ -s .audit-raw/websockets.txt ] && cut -f2 .audit-raw/websockets.txt | sed 's/^/WS /'
} | sort -u > api-surface.txt
rm -f /tmp/.api

echo "  api-surface.txt: $(wc -l < api-surface.txt) endpoints"
sed 's/^/    /' api-surface.txt

# Completeness check: every HAR request must land in exactly one bucket.
total=$(wc -l < .audit-raw/har-requests.tsv)
[ "$total" -gt 0 ] || { echo "GATE FAIL: HARs contain no requests" >&2; exit 3; }

# --- gates ------------------------------------------------------------------
[ "$html" -eq "$routes" ] || { echo "GATE FAIL: rendered html $html != routes $routes" >&2; exit 3; }
[ "$har" -eq "$routes" ] || { echo "GATE FAIL: har count $har != routes $routes" >&2; exit 3; }
[ -s api-surface.txt ] || { echo "GATE FAIL: api-surface.txt is empty" >&2; exit 3; }
if grep -qEi '\.(js|css|png|jpe?g|svg|woff2?)(\?|$)' api-surface.txt; then
  echo "GATE FAIL: static assets leaked into api-surface.txt" >&2; exit 3
fi
echo "GATE PASS: $html/$routes rendered, $har HARs, $(wc -l < api-surface.txt) endpoints, no static assets."
