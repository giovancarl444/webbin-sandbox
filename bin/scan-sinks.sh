#!/usr/bin/env bash
# Risky DOM sinks. These are leads for review, not findings on their own:
# minified code produces heavy false positives and reachability is unproven
# without dynamic analysis. Reporting them as vulnerabilities would be wrong.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"
mkdir -p findings

{
  echo "# DOM sinks (review leads, not confirmed findings)"
  echo
  echo "Static matches in first-party JavaScript. Exploitability depends on whether"
  echo "attacker-controlled input reaches the sink, which this passive pass cannot"
  echo "establish. Triage before treating any row as a vulnerability."
  echo
  echo "| Sink | Occurrences | Example location |"
  echo "|---|---|---|"
} > findings/dom-sinks.md

scan() { # label, regex
  # `|| true` throughout: zero matches is ripgrep exit 1, and under pipefail
  # that would abort on the most common outcome.
  local n loc
  n="$({ rg --no-messages -o -g '*.js' -g '*.html' -e "$2" mirror-raw 2>/dev/null || true; } | grep -c . || true)"
  loc="$({ rg --json --no-messages -g '*.js' -g '*.html' -e "$2" mirror-raw 2>/dev/null || true; } \
        | jq -r 'select(.type=="match") | "\(.data.path.text):\(.data.line_number)"' 2>/dev/null | head -1 || true)"
  [ "${n:-0}" -gt 0 ] && printf '| `%s` | %s | `%s` |\n' "$1" "$n" "${loc:--}" >> findings/dom-sinks.md
  echo "${n:-0}"
}

total=0
for pair in "innerHTML:\.innerHTML\s*=" \
            "outerHTML:\.outerHTML\s*=" \
            "document.write:document\.write(ln)?\s*\(" \
            "eval:\beval\s*\(" \
            "new Function:new\s+Function\s*\(" \
            "insertAdjacentHTML:insertAdjacentHTML\s*\(" \
            "dangerouslySetInnerHTML:dangerouslySetInnerHTML" \
            "postMessage listener:addEventListener\s*\(\s*[\"']message[\"']"; do
  n="$(scan "${pair%%:*}" "${pair#*:}")"
  total=$((total + n))
done

# A message listener that never checks event.origin accepts instructions from
# any frame that can reach the page.
unchecked=0
if rg -q --no-messages -g '*.js' "addEventListener\s*\(\s*[\"']message[\"']" mirror-raw 2>/dev/null; then
  rg -q --no-messages -g '*.js' '\.origin\s*(===?|!==?)' mirror-raw 2>/dev/null || unchecked=1
fi

{
  echo
  [ "$total" -eq 0 ] && echo "No sink patterns matched."
  [ "$unchecked" -eq 1 ] && {
    echo "**postMessage listener with no \`event.origin\` comparison anywhere in the"
    echo "bundle.** Any page that can obtain a handle to this window can send it"
    echo "messages. Where the handler writes to the DOM, that is a direct injection path."
  }
  echo
  echo "Total sink occurrences: $total."
} >> findings/dom-sinks.md
echo "  dom sink occurrences=$total unchecked-postMessage=$unchecked -> findings/dom-sinks.md"
