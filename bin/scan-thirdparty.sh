#!/usr/bin/env bash
# Third-party inventory from the HARs. Every external origin is inherited
# supply-chain risk: whoever controls it can execute in our users' sessions.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"
mkdir -p findings

{
  echo "# Third-party inventory"
  echo
  echo "Origins the site loaded during the rendered crawl, by request count."
  echo
  echo "| Requests | Origin | First-party? | Blocking script |"
  echo "|---|---|---|---|"
} > findings/third-party.md

# The page loads its own subresources unimpeded -- that is what a passive
# observation of a real visit means. The host allowlist governs what WE choose
# to fetch, not what the site chooses to include.
jq -r '.log.entries[].request.url' har/*.har 2>/dev/null \
  | sed -E 's#^([a-z]+://[^/]+).*#\1#' | sort | uniq -c | sort -rn \
  | while read -r count origin; do
      host="${origin#*://}"
      first=no; case ",$ALLOWED_HOSTS," in *",$host,"*) first=yes ;; esac
      # ripgrep exits 1 on zero matches, which under `pipefail` aborts the
      # script. Counting absence is a normal outcome here, not an error.
      esc="$(printf '%s' "$origin" | sed 's/[.[\*^$()+?{|]/\\&/g')"
      tags="$({ rg --no-messages -o "<script[^>]*src=\"$esc[^\"]*\"[^>]*>" rendered 2>/dev/null || true; })"
      total_tags="$(printf '%s' "$tags" | grep -c . || true)"
      deferred="$(printf '%s' "$tags" | grep -cE 'async|defer' || true)"
      # A blocking script halts parsing and executes before content paints:
      # the highest-privilege position on the page.
      if [ "${total_tags:-0}" -gt "${deferred:-0}" ]; then mark="**yes**"; else mark="no"; fi
      printf '| %s | `%s` | %s | %s |\n' "$count" "$origin" "$first" "$mark"
    done >> findings/third-party.md

ext=$(jq -r '.log.entries[].request.url' har/*.har 2>/dev/null \
      | sed -E 's#^[a-z]+://([^/]+).*#\1#' | sort -u \
      | awk -v allow="$ALLOWED_HOSTS" 'BEGIN{n=split(allow,a,","); for(i=1;i<=n;i++) ok[a[i]]=1} !($0 in ok)' | wc -l)
{
  echo
  echo "External origins outside the declared allowlist: **$ext**."
  echo
  echo "Each one executes with full access to the page: DOM, cookies not marked"
  echo "HttpOnly, and anything typed into a form. For a trading or wallet frontend"
  echo "this is the single highest-leverage compromise path -- the attacker does not"
  echo "need our infrastructure, only one of theirs."
} >> findings/third-party.md
echo "  third-party origins outside allowlist=$ext -> findings/third-party.md"
