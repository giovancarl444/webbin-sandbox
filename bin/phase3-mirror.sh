#!/usr/bin/env bash
# Phase 3 -- static mirror into mirror-raw/.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"

log_phase "Phase 3: static mirror of $TARGET_URL"
[ -s routes.txt ] || { echo "GATE FAIL: routes.txt missing; run phase 2" >&2; exit 3; }

# Faceted parameters generate factorial URL permutations of identical pages.
# Report what the site actually uses before rejecting, so the pattern is
# justified by evidence rather than assumed from a template.
echo "  observed query parameters on discovered pages:"
{ cat .audit-raw/routes.all 2>/dev/null
  while read -r u; do audit_get "$u" || true; done < <(head -3 routes.txt)
} | grep -oE '[?&][a-zA-Z_.][a-zA-Z0-9_.]*=' | tr -d '?&=' | sort | uniq -c | sort -rn | head -12 | sed 's/^/    /'

# Note the two alternations. Namespaced params (filter.asset, filter.price)
# must match on the prefix alone -- requiring '=' immediately after "filter."
# never matches, because the real parameter name continues past the dot.
REJECT='([?&](sort_by|page|variant|utm_[a-z_]+|gclid|fbclid|ref|q|orderby|paged|s)=|[?&]filter\.)'
echo "  reject-regex: $REJECT"
echo "  (matches faceting, pagination, and ad-tracking params. --reject-regex is"
echo "   required here: wget's -R matches filename suffixes, not query strings.)"

# wget's -D takes hostnames without ports.
DOMAINS="$(printf '%s' "$ALLOWED_HOSTS" | tr ',' '\n' | cut -d: -f1 | sort -u | paste -sd,)"
WAIT="$(awk "BEGIN{printf \"%.3f\", $REQ_DELAY_MS/1000}")"
echo "  span-hosts: $DOMAINS   wait: ${WAIT}s"

rm -rf mirror-raw; mkdir -p mirror-raw
# -k (--convert-links) is deliberately NOT used: it rewrites URLs inside the
# mirrored files, so the bytes no longer match what the server served. That
# breaks third-party origin attribution and makes re-run diffs noisy, because
# rewriting depends on which files happened to download.
set +e
timeout "$PHASE_TIMEOUT_SEC" wget \
  --input-file=routes.txt --recursive --level=5 --page-requisites --adjust-extension \
  --no-parent --span-hosts --domains="$DOMAINS" \
  --reject-regex="$REJECT" --regex-type=posix \
  --user-agent="$AUDIT_UA" --wait="$WAIT" --tries=2 --timeout=30 \
  --directory-prefix=mirror-raw --no-verbose --output-file=wget.log
rc=$?
set -e
[ "$rc" -eq 124 ] && echo "  STOP: mirror hit PHASE_TIMEOUT_SEC=${PHASE_TIMEOUT_SEC}s" >&2 && exit 3

# Back off rather than retry harder, per engagement rules.
if grep -qE 'ERROR (429|503)' wget.log; then
  echo "GATE FAIL: server returned 429/503 -- backing off, not retrying. Investigate before re-running." >&2
  grep -E 'ERROR (429|503)' wget.log | head -5 >&2; exit 3
fi

echo
echo "  size:  $(du -sh mirror-raw | cut -f1)"
echo "  files: $(find mirror-raw -type f | wc -l) total, $(find mirror-raw -name '*.js' | wc -l) js, $(find mirror-raw -name '*.css' | wc -l) css"
# wget -nv does not log rejections, so counting them from the log is not
# possible. Assert on the outcome instead: no faceted URL may reach the disk.
faceted="$(find mirror-raw -type f -name '*[?]*' | grep -E 'sort_by|filter\.|page=|variant=|utm_' || true)"
echo "  parameterised files on disk: $(find mirror-raw -type f -name '*[?]*' | wc -l)"
# A per-host robots.txt 404 is wget's own politeness probe, not a site error.
echo "  errors: $(grep -E 'ERROR [0-9]+' wget.log | wc -l) ($(grep -B1 'ERROR 404' wget.log | grep -c 'robots.txt:' || true) are robots.txt probes)"

echo "  top 10 largest assets:"
find mirror-raw -type f -printf '%s\t%p\n' | sort -rn | head -10 \
  | awk -F'\t' '{printf "    %8.1f KB  %s\n", $1/1024, $2}'

# Committed in place of the bytes: re-run diffing works on hashes, and no
# client-confidential content or credential material enters a public repo.
find mirror-raw -type f -exec sha256sum {} + | sort -k2 > mirror-manifest.txt
echo "  manifest: $(wc -l < mirror-manifest.txt) entries -> mirror-manifest.txt"

js=$(find mirror-raw -name '*.js' | wc -l); css=$(find mirror-raw -name '*.css' | wc -l)
if [ "$js" -eq 0 ] || [ "$css" -eq 0 ]; then
  echo "GATE FAIL: expected JS and CSS in the mirror (js=$js css=$css)" >&2; exit 3
fi
if [ -n "$faceted" ]; then
  echo "GATE FAIL: reject-regex leaked -- faceted URLs reached the mirror:" >&2
  printf '  %s\n' $faceted >&2
  echo "  Fix REJECT before re-running; these permutations are what turn a mirror into an infinite crawl." >&2
  exit 3
fi
echo "GATE PASS: mirror populated, js=$js css=$css, no faceted URLs on disk, no 429/503."
