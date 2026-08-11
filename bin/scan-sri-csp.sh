#!/usr/bin/env bash
# Subresource integrity and CSP quality. These are the two controls that decide
# whether a compromised third-party script can execute.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"
mkdir -p findings

{
  echo "# Subresource integrity and CSP"
  echo
  echo "## Cross-origin subresources without integrity"
  echo
  echo "| Tag | URL | Referenced in |"
  echo "|---|---|---|"
} > findings/sri-csp.md

# Cross-origin script/stylesheet tags, minus any carrying an integrity attribute.
missing=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  file="${line%%:*}"; tag="${line#*:}"
  printf '%s' "$tag" | grep -qi 'integrity=' && continue
  url="$(printf '%s' "$tag" | grep -oE '(src|href)="[^"]+"' | head -1 | cut -d'"' -f2)"
  case "$url" in http*) ;; *) continue ;; esac
  kind=script; printf '%s' "$tag" | grep -qi '<link' && kind=stylesheet
  printf '| %s | `%s` | `%s` |\n' "$kind" "$url" "$file" >> findings/sri-csp.md
  missing=$((missing + 1))
done < <(rg --json --no-messages -e '<(script|link)[^>]+(src|href)="https?://[^"]+"[^>]*>' rendered 2>/dev/null \
         | jq -r 'select(.type=="match") | .data as $d | $d.submatches[]
                  | "\($d.path.text):\(.match.text)"' 2>/dev/null || true)

[ "$missing" -eq 0 ] && echo "| - | no cross-origin subresources found | - |" >> findings/sri-csp.md

# CSP quality, not just presence. A policy with unsafe-inline is close to none.
csp="$(grep -i '^content-security-policy:' .audit-raw/headers.txt 2>/dev/null | cut -d: -f2- | tr -d '\r' || true)"
{
  echo
  echo "## CSP"
  echo
  if [ -z "$csp" ]; then
    echo "**No Content-Security-Policy header.** Nothing constrains which origins may"
    echo "execute script, so SRI is the only remaining control and it is absent above."
  else
    echo "Policy: \`$(printf '%s' "$csp" | cut -c1-200)\`"
    echo
    for weak in "unsafe-inline" "unsafe-eval" "script-src \*" "default-src \*"; do
      printf '%s' "$csp" | grep -qi -- "$weak" && echo "- Weakened by \`$weak\`"
    done
    printf '%s' "$csp" | grep -qi 'frame-ancestors' || \
      echo "- No \`frame-ancestors\`: page can be framed, enabling clickjacking of any in-page action"
  fi
  echo
  echo "Missing integrity on $missing cross-origin subresource(s)."
} >> findings/sri-csp.md
echo "  cross-origin subresources without SRI=$missing -> findings/sri-csp.md"
