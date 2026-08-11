#!/usr/bin/env bash
# Sourcemaps. A reachable .map hands over the original source: internal module
# names, comments, dead code paths, and any logic assumed hidden by minification.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"
mkdir -p findings sourcemaps

SCHEME="${TARGET_URL%%://*}"
{
  echo "# Sourcemaps"
  echo
  echo "| Status | Map URL | Referenced by |"
  echo "|---|---|---|"
} > findings/sourcemaps.md

found=0; exposed=0; inline=0
# Tab-separated via rg --json, not colon-separated: mirror paths contain the
# host:port ("mirror-raw/localhost:8080/..."), so splitting on ':' shreds them.
while IFS=$'\t' read -r file line ref; do
  [ -z "${ref:-}" ] && continue
  found=$((found + 1))
  ref="$(printf '%s' "$ref" | tr -d '\r' | sed 's/[[:space:]]*\*\/.*$//' | tr -d ' ')"

  if [[ "$ref" == data:* ]]; then
    inline=$((inline + 1))
    echo "| INLINE | (base64 data: URI, embedded in the bundle) | \`$file\` |" >> findings/sourcemaps.md
    continue
  fi

  # mirror-raw/<host>/<path> -> <scheme>://<host>/<path>
  rel="${file#mirror-raw/}"; host="${rel%%/*}"; dir="$(dirname "${rel#"$host"}")"
  case "$ref" in
    http*) url="$ref" ;;
    /*)    url="$SCHEME://$host$ref" ;;
    *)     url="$SCHEME://$host$dir/$ref" ;;
  esac

  code="$(audit_get "$url" -o /dev/null -w '%{http_code}' 2>/dev/null || echo "000")"
  if [ "$code" = "200" ]; then
    exposed=$((exposed + 1))
    out="sourcemaps/$(printf '%s' "$url" | sed 's#^[a-z]*://##; s#[^A-Za-z0-9._-]#_#g')"
    audit_get "$url" -o "$out" || true
    srcs="$(jq -r '(.sources // []) | length' "$out" 2>/dev/null || echo '?')"
    echo "| **EXPOSED ($code)** | \`$url\` ($srcs original sources) | \`$file:$line\` |" >> findings/sourcemaps.md
  else
    echo "| not reachable ($code) | \`$url\` | \`$file:$line\` |" >> findings/sourcemaps.md
  fi
done < <(rg --json --no-messages -g '!*.map' -e 'sourceMappingURL=\S+' mirror-raw 2>/dev/null \
         | jq -r 'select(.type == "match") | .data as $d | $d.submatches[]
                  | [$d.path.text, ($d.line_number | tostring),
                     (.match.text | sub("^sourceMappingURL="; ""))] | @tsv' || true)

{
  echo
  echo "References found: $found. Publicly reachable: **$exposed**. Inline: $inline."
  [ "$exposed" -eq 0 ] && echo && echo "No exposed sourcemaps."
  [ "$exposed" -gt 0 ] && echo && echo "Downloaded copies are in \`sourcemaps/\` (gitignored -- they contain our original source)."
} >> findings/sourcemaps.md
echo "  sourcemap refs=$found exposed=$exposed inline=$inline -> findings/sourcemaps.md"
