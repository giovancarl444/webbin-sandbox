#!/usr/bin/env bash
# Run the audit engine against an imported system rather than a live site.
#
# The target is our own sandbox copy on loopback, so the politeness budget that
# governs a client's production origin does not apply -- that is the point of
# importing. Routes come from the source tree, so coverage is not limited to
# what a sitemap happens to advertise.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
NAME="${1:?usage: audit-import.sh <name>}"
META="imports/_meta"
[ -f "$META/$NAME.json" ] || { echo "no import named '$NAME' -- run import-system.sh first" >&2; exit 2; }

port="$(jq -r '.port' "$META/$NAME.json")"
env_file=".audit-raw/import-$NAME.env"
cat > "$env_file" <<EOF
TARGET_URL="http://127.0.0.1:$port"
TARGET_HOST="127.0.0.1:$port"
EXTRA_HOSTS=""
OWNERSHIP="imported sandbox copy of $NAME (loopback)"
AUDIT_CONTACT="sandbox@localhost"
AUDIT_UA="Webbin-Audit/1.0 (internal; imported sandbox copy)"
REQ_DELAY_MS=10
CONCURRENCY=2
MAX_ROUTES=2000
PHASE_TIMEOUT_SEC=900
PAGE_TIMEOUT_MS=45000
FULL_PAGE_SHOTS=0
EOF

cp "$META/$NAME-routes.txt" routes.txt
echo "=== auditing import '$NAME' on :$port ($(wc -l < routes.txt) source-derived routes) ==="

AUDIT_ENV="$env_file" bin/phase3-mirror.sh
AUDIT_ENV="$env_file" bin/phase4-crawl.sh
set +e; AUDIT_ENV="$env_file" bin/phase5-analyze.sh; p5=$?; set -e

# Merge the source-derived backend surface into the handoff document. Passive
# observation only sees endpoints the browser happened to call; the source
# lists every handler that exists.
if [ -s "$META/$NAME-api-source.txt" ]; then
  sort -u "$META/$NAME-api-source.txt" api-surface.txt -o api-surface.txt
  echo "  merged $(wc -l < "$META/$NAME-api-source.txt") source-derived API handlers into api-surface.txt"
fi

cp -r findings "$META/$NAME-findings" 2>/dev/null && rm -rf "$META/$NAME-findings.old" || true
bin/import-ledger.sh "$NAME"
exit "$p5"
