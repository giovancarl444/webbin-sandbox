#!/usr/bin/env bash
# Prove the sandbox copy matches production.
#
# usage: OWNERSHIP="..." bin/parity-check.sh <import-name> <production-url>
#
# This is what turns "we imported it" into "we imported it and here is the
# proof it matches". Without it, every finding from the sandbox is an
# assertion about a copy whose relationship to production is unexamined.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
NAME="${1:?usage: parity-check.sh <import-name> <production-url>}"
PROD="${2:?production URL required}"; PROD="${PROD%/}"
META="imports/_meta"; M="$META/$NAME.json"
[ -f "$M" ] || { echo "no import '$NAME' -- run import-system.sh first" >&2; exit 2; }
port="$(jq -r .port "$M")"

mkenv() { # file, url, host, ownership
  cat > "$1" <<EOF
TARGET_URL="$2"
TARGET_HOST="$3"
EXTRA_HOSTS=""
OWNERSHIP="$4"
AUDIT_CONTACT="${AUDIT_CONTACT:-sandbox@localhost}"
AUDIT_UA="Webbin-Audit/1.0 (internal parity check; contact ${AUDIT_CONTACT:-sandbox@localhost})"
REQ_DELAY_MS=${5:-500}
CONCURRENCY=2
MAX_ROUTES=2000
PHASE_TIMEOUT_SEC=1800
PAGE_TIMEOUT_MS=45000
FULL_PAGE_SHOTS=0
EOF
}

# Same logical routes against both origins -- that is the comparison that
# means something. Rebasing the source-derived route list onto production also
# catches routes the client's sitemap never advertised.
snapshot() { # routes-file, env-file, out-manifest, host
  cp "$1" routes.txt
  AUDIT_ENV="$2" bin/phase3-mirror.sh > "$ROOT/.audit-raw/parity-$3.log" 2>&1 \
    || { echo "  snapshot failed for $3 -- see .audit-raw/parity-$3.log" >&2; return 1; }
  # Restrict to the target origin before stripping it. wget's -D is port-blind,
  # so a loopback asset host lands inside one side's scope and outside the
  # other's, and the two sides stop being comparable. Third-party assets are
  # deliberately out of scope here -- they are not ours to reproduce, and
  # scan-thirdparty.sh inventories them separately.
  grep -F "  mirror-raw/$4/" mirror-manifest.txt \
    | sed -E "s#  mirror-raw/$4/#  #" | sort -k2 > "$META/$NAME-$3.manifest"
  wc -l < "$META/$NAME-$3.manifest"
}

echo "=== parity: sandbox :$port  vs  production $PROD ==="
mkenv .audit-raw/parity-sandbox.env "http://127.0.0.1:$port" "127.0.0.1:$port" "imported sandbox copy" 10
n_sb=$(snapshot "$META/$NAME-routes.txt" .audit-raw/parity-sandbox.env sandbox "127.0.0.1:$port")

prod_host="${PROD#*://}"; prod_host="${prod_host%%/*}"
sed -E "s#^https?://[^/]+#$PROD#" "$META/$NAME-routes.txt" > .audit-raw/parity-prod-routes.txt
mkenv .audit-raw/parity-prod.env "$PROD" "$prod_host" "${OWNERSHIP:-}" 500
n_pd=$(snapshot .audit-raw/parity-prod-routes.txt .audit-raw/parity-prod.env prod "$prod_host")
echo "  sandbox: $n_sb assets   production: $n_pd assets"

# --- join ------------------------------------------------------------------
awk '{print $2"\t"$1}' "$META/$NAME-sandbox.manifest" | sort > .audit-raw/sb.tsv
awk '{print $2"\t"$1}' "$META/$NAME-prod.manifest"    | sort > .audit-raw/pd.tsv
same=$(join -t$'\t' .audit-raw/sb.tsv .audit-raw/pd.tsv | awk -F'\t' '$2==$3' | wc -l)
diff=$(join -t$'\t' .audit-raw/sb.tsv .audit-raw/pd.tsv | awk -F'\t' '$2!=$3' | wc -l)
sb_only=$(join -t$'\t' -v1 .audit-raw/sb.tsv .audit-raw/pd.tsv | wc -l)
pd_only=$(join -t$'\t' -v2 .audit-raw/sb.tsv .audit-raw/pd.tsv | wc -l)

# Content parity ignores filenames. Hashed-chunk builds (Next.js, Vite) rename
# every asset per build, so path parity alone reports total mismatch even when
# the bytes are identical. This measures what actually shipped.
cut -f2 .audit-raw/sb.tsv | sort -u > .audit-raw/sb.hashes
matched=$(cut -f2 .audit-raw/pd.tsv | sort -u | grep -Fxf .audit-raw/sb.hashes | wc -l || true)
total_pd=$(cut -f2 .audit-raw/pd.tsv | sort -u | wc -l)
pct=$( [ "$total_pd" -gt 0 ] && echo $(( matched * 100 / total_pd )) || echo 0 )

OUT="$META/$NAME-parity.md"
{
  echo "# Production parity — $NAME"
  echo
  echo "Sandbox \`http://127.0.0.1:$port\` vs production \`$PROD\`, same $(wc -l < "$META/$NAME-routes.txt") source-derived routes."
  echo
  echo "| Result | Count |"
  echo "|---|---|"
  echo "| Same path, identical bytes | $same |"
  echo "| Same path, **different bytes** | $diff |"
  echo "| Sandbox only (not served by production) | $sb_only |"
  echo "| Production only (missing from sandbox) | $pd_only |"
  echo
  echo "**Content parity: $pct%** ($matched of $total_pd production assets exist byte-identical in the sandbox, regardless of filename)."
  echo
  if [ "$diff" -gt 0 ]; then
    echo "## Same path, different bytes"; echo
    join -t$'\t' .audit-raw/sb.tsv .audit-raw/pd.tsv | awk -F'\t' '$2!=$3 {print "- `" $1 "`"}' | head -25
    echo
  fi
  if [ "$pd_only" -gt 0 ]; then
    echo "## Served by production, absent from the sandbox"; echo
    echo "Each of these is a gap in the import. Findings cannot cover them."; echo
    join -t$'\t' -v2 .audit-raw/sb.tsv .audit-raw/pd.tsv | awk -F'\t' '{print "- `" $1 "`"}' | head -25
    echo
  fi
  echo "## What this licenses us to claim"; echo
  if [ "$pct" -ge 95 ] && [ "$pd_only" -eq 0 ]; then
    echo "- Bundle-level findings (secrets, sourcemaps, vulnerable dependencies, DOM sinks)"
    echo "  **transfer to production**: the bytes we analysed are the bytes production serves."
  else
    echo "- Bundle-level findings are **sandbox-only** until parity improves. At $pct% content"
    echo "  parity with $pd_only production asset(s) missing, some of what production serves"
    echo "  was never analysed."
  fi
  echo "- Header, TLS and CDN findings **never** come from this comparison. They belong to"
  echo "  the client's edge and must come from a passive pass against the live origin."
  echo
  echo "Re-run after any fix: \`OWNERSHIP=\"...\" bin/parity-check.sh $NAME $PROD\`"
} > "$OUT"

echo "  same=$same differing=$diff sandbox-only=$sb_only prod-only=$pd_only  content-parity=${pct}%"
echo "  report -> $OUT"
