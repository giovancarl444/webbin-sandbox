#!/usr/bin/env bash
# Security headers on the root and one deep page. A GET with headers dumped,
# not a HEAD: origins and CDNs routinely handle HEAD differently.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"
mkdir -p findings

deep="$(tail -1 routes.txt)"
: > findings/headers.md
echo "# Security headers" >> findings/headers.md

check_url() {
  local url="$1" h=.audit-raw/headers.txt
  audit_get "$url" -o /dev/null -D "$h" || { echo "  unreachable: $url"; return 0; }
  {
    echo
    echo "## \`$url\`"
    echo
    echo "| Header | Status | Value |"
    echo "|---|---|---|"
  } >> findings/headers.md

  for hdr in Content-Security-Policy Strict-Transport-Security X-Content-Type-Options \
             Referrer-Policy Permissions-Policy X-Frame-Options; do
    val="$(grep -i "^$hdr:" "$h" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ *//' || true)"
    if [ -n "$val" ]; then
      echo "| $hdr | present | \`$(printf '%s' "$val" | cut -c1-90)\` |" >> findings/headers.md
    else
      echo "| $hdr | **MISSING** | - |" >> findings/headers.md
    fi
  done

  # Cookie flags. Missing HttpOnly on a session cookie means any XSS reads it.
  if grep -qi '^set-cookie:' "$h"; then
    while read -r c; do
      name="$(printf '%s' "$c" | sed -E 's/^[Ss]et-[Cc]ookie:[[:space:]]*([^=]+)=.*/\1/')"
      miss=""
      for flag in Secure HttpOnly SameSite; do
        printf '%s' "$c" | grep -qi "$flag" || miss="$miss $flag"
      done
      [ -z "$miss" ] && miss=" none"
      echo "| Set-Cookie \`$name\` | missing:$miss | - |" >> findings/headers.md
    done < <(grep -i '^set-cookie:' "$h")
  else
    echo "| Set-Cookie | none set | - |" >> findings/headers.md
  fi

  # HSTS is meaningless over plaintext; say why rather than reporting a bare miss.
  case "$url" in http://*)
    echo "| _note_ | served over HTTP | HSTS cannot apply; the transport itself is the finding |" >> findings/headers.md ;;
  esac
}

check_url "$TARGET_URL/"
[ -n "$deep" ] && check_url "$deep"
echo "  headers checked on root + $deep -> findings/headers.md"
