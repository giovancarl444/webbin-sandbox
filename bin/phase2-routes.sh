#!/usr/bin/env bash
# Phase 2 -- route discovery. robots.txt + sitemap.xml -> flat, deduped routes.txt.
# Handles the one level of sitemap nesting that Shopify and most CMSs use.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"

log_phase "Phase 2: route discovery on $TARGET_URL"
mkdir -p .audit-raw

audit_get "$TARGET_URL/robots.txt" -o robots.txt || echo "  (no robots.txt)"
[ -s robots.txt ] && echo "  robots.txt: $(wc -l < robots.txt) lines, $(grep -ci '^disallow' robots.txt || true) Disallow rules"

# Prefer a sitemap advertised by robots.txt over the conventional location.
declared="$(grep -i '^[[:space:]]*sitemap:' robots.txt 2>/dev/null | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || true)"
root_sitemap="${declared:-$TARGET_URL/sitemap.xml}"
echo "  sitemap source: $root_sitemap"

if ! audit_get "$root_sitemap" -o sitemap.xml || [ ! -s sitemap.xml ]; then
  cat >&2 <<EOF
STOP: no usable sitemap at $root_sitemap.

Not adapting silently. The alternative is a shallow link crawl:
    wget --spider -r -l2 -H -D "\$ALLOWED_HOSTS" --wait 0.5 "\$TARGET_URL"
That changes the meaning of routes.txt from "pages the site publishes" to
"pages reachable in 2 hops", which is a different baseline. Confirm before
we proceed on it.
EOF
  exit 3
fi

# Comments must be stripped before deciding what kind of sitemap this is.
# Matching '<sitemapindex' anywhere in the raw bytes treats a flat sitemap that
# merely *mentions* the word in a comment as an index, and then fetches each
# page as though it were a child sitemap.
nocomments() { python3 -c "import re,sys;print(re.sub(r'<!--.*?-->','',open(sys.argv[1],encoding='utf-8',errors='replace').read(),flags=re.S))" "$1"; }
locs() { nocomments "$1" | tr '>' '>\n' | sed -nE 's#.*<loc[^>]*>[[:space:]]*([^<[:space:]]+).*#\1#p' | tr -d '\r'; }

# urlset is checked first: a sitemapindex never contains one, so this settles
# ambiguous files without depending on element ordering.
kind=flat
if ! nocomments sitemap.xml | grep -qi '<urlset'; then
  nocomments sitemap.xml | grep -qi '<sitemapindex' && kind=index
fi

: > .audit-raw/routes.all
if [ "$kind" = index ]; then
  mapfile -t children < <(locs sitemap.xml)
  echo "  nested sitemap index: ${#children[@]} child sitemaps"
  for child in "${children[@]}"; do
    host="$(printf '%s' "$child" | sed -E 's#^[a-z]+://([^/]+).*#\1#')"
    guard_host "$host" || continue
    audit_get "$child" -o .audit-raw/child.xml || { echo "  WARN: unreachable $child"; continue; }
    n="$(locs .audit-raw/child.xml | tee -a .audit-raw/routes.all | wc -l)"
    echo "    $child -> $n urls"
    if nocomments .audit-raw/child.xml | grep -qi '<sitemapindex'; then
      echo "    NOTE: $child is itself an index -- nesting is deeper than one level, not expanded"
    fi
  done
else
  locs sitemap.xml > .audit-raw/routes.all
  echo "  flat sitemap"
fi

# Drop faceted/paginated permutations and off-allowlist hosts, then dedupe
# while preserving order.
# `|| true`: an empty or fully-filtered route list makes grep exit 1, and under
# pipefail that aborts the phase before the gate can report the real problem.
{ grep -vE '[?&](sort_by|filter\.|page|variant|utm_[a-z]+|gclid|fbclid|ref|q)=' .audit-raw/routes.all || true; } \
  | awk -v allow="$ALLOWED_HOSTS" '
      BEGIN { n = split(allow, a, ","); for (i=1;i<=n;i++) ok[a[i]] = 1 }
      { u = $0; sub(/^[a-z]+:\/\//, "", u); sub(/\/.*$/, "", u); if (u in ok && !seen[$0]++) print }
    ' > routes.txt

total="$(wc -l < .audit-raw/routes.all)"; kept="$(wc -l < routes.txt)"
echo "  $total raw locs -> $kept unique in-scope routes"

if [ "$kept" -eq 0 ]; then echo "GATE FAIL: routes.txt is empty" >&2; exit 3; fi
if [ "$kept" -gt "$MAX_ROUTES" ]; then
  echo "STOP: $kept routes exceeds MAX_ROUTES=$MAX_ROUTES. At ${REQ_DELAY_MS}ms/request that is over budget." >&2
  exit 3
fi

# Gate: sample 5 routes and require 200.
echo "  sampling 5 routes:"
bad=0
while read -r u; do
  code="$(audit_get "$u" -o /dev/null -w '%{http_code}')"
  printf '    %-58s %s\n' "$u" "$code"
  [ "$code" = "200" ] || bad=1
done < <(shuf -n 5 routes.txt 2>/dev/null || head -5 routes.txt)

[ "$bad" -eq 0 ] && echo "GATE PASS: $kept routes, sample all 200." || { echo "GATE FAIL: sampled route did not return 200" >&2; exit 3; }
