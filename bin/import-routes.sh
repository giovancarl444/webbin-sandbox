#!/usr/bin/env bash
# Enumerate routes from an imported system's SOURCE TREE, not from its sitemap.
#
# This is the reason importing beats crawling. A sitemap lists what the site
# advertises; the source lists what it actually serves -- including unlinked
# pages, staging routes, and backend API handlers that no amount of passive
# crawling will reveal. Those handlers are the step-3 handoff.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
NAME="${1:?usage: import-routes.sh <name>}"
SRC="imports/$NAME"; META="imports/_meta"
port="$(jq -r '.port' "$META/$NAME.json")"
fw="$(jq -r '.profile.framework // "unknown"' "$META/$NAME.json")"
base="http://127.0.0.1:$port"

pages="$META/$NAME-routes.txt"; api="$META/$NAME-api-source.txt"
: > "$pages"; : > "$api"

case "$fw" in
  static)
    # Every served .html is a route, including ones nothing links to.
    find "$SRC" -name '*.html' -not -path '*/.git/*' -printf '%P\n' \
      | sed "s#^#$base/#" | sort -u > "$pages"
    ;;
  nextjs)
    # App Router: page.tsx -> a page route, route.ts -> an API handler.
    # Route groups (auth) and parallel segments @slot do not appear in URLs.
    for d in "$SRC/src/app" "$SRC/app"; do
      [ -d "$d" ] || continue
      find "$d" -name 'page.tsx' -o -name 'page.jsx' -o -name 'page.js' 2>/dev/null \
        | sed -E "s#^$d##; s#/page\.(tsx|jsx|js)\$##; s#/\([^)]*\)##g; s#/@[^/]*##g" \
        | sed -E 's#^$#/#' | sed "s#^#$base#" >> "$pages"
      find "$d" -name 'route.ts' -o -name 'route.js' 2>/dev/null \
        | sed -E "s#^$d##; s#/route\.(ts|js)\$##; s#/\([^)]*\)##g" \
        | while read -r r; do
            # Method comes from the exported handler names, not from guessing.
            f="$(find "$d$r" -maxdepth 1 -name 'route.*' 2>/dev/null | head -1)"
            for m in GET POST PUT PATCH DELETE HEAD OPTIONS; do
              rg -q "export\s+(async\s+)?function\s+$m\b|export\s+const\s+$m\b" "$f" 2>/dev/null \
                && echo "$m $base$r" >> "$api"
            done
          done
    done
    # Pages Router, if present alongside.
    for d in "$SRC/src/pages" "$SRC/pages"; do
      [ -d "$d" ] || continue
      find "$d" -name '*.tsx' -o -name '*.jsx' 2>/dev/null | grep -v '/_' \
        | sed -E "s#^$d##; s#\.(tsx|jsx)\$##; s#/index\$##" | sed "s#^#$base#" >> "$pages"
    done
    ;;
  *)
    echo "route enumeration for framework '$fw' not implemented -- reporting rather than guessing" >&2
    exit 3 ;;
esac

sort -u -o "$pages" "$pages"; sort -u -o "$api" "$api"
# Dynamic segments cannot be fetched without knowing real ids. Separate them
# rather than emitting URLs that will 404 and pollute the error findings.
dyn="$(grep -cE '\[[^]]+\]' "$pages" || true)"
grep -vE '\[[^]]+\]' "$pages" > "$pages.static" && mv "$pages.static" "$pages"

echo "  $NAME [$fw]: $(wc -l < "$pages") static page routes, $dyn dynamic (skipped), $(wc -l < "$api") API handlers"
echo "    pages -> $pages"
[ -s "$api" ] && { echo "    api   -> $api"; sed 's/^/      /' "$api"; }
exit 0
