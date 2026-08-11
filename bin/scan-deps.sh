#!/usr/bin/env bash
# Vulnerable dependencies via retire.js against the mirrored bundles.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/guard.sh"
mkdir -p findings

npx --no-install retire --path ./mirror-raw --outputformat json \
    --outputpath findings/retire.json >/dev/null 2>&1 || true
[ -s findings/retire.json ] || echo '[]' > findings/retire.json

{
  echo "# Vulnerable dependencies"
  echo
  echo "| Severity | Component | Version | Identifiers | File |"
  echo "|---|---|---|---|---|"
  jq -r '(if type == "object" then (.data // []) else . end)[]
         | (.file // "?") as $f
         | (.results // [])[]
         | (.component // "?") as $c | (.version // "?") as $v
         | (.vulnerabilities // [])[]
         | [ (.severity // "unknown"),
             $c, $v,
             # identifiers.CVE is an array but .issue is a bare string, so
             # normalise to an array before joining rather than assuming shape.
             ((.identifiers.CVE // .identifiers.githubID // .identifiers.issue
               // .identifiers.summary // "-")
              | (if type == "array" then . else [.] end) | join(", ") | .[0:80]),
             $f ] | @tsv' findings/retire.json 2>/dev/null \
    | sort -u | awk -F'\t' '{ printf "| %s | %s | %s | %s | `%s` |\n", toupper($1), $2, $3, $4, $5 }'
} > findings/dependencies.md

n=$(grep -c '^| ' findings/dependencies.md || true); n=$((n > 0 ? n - 1 : 0))
{
  echo
  if [ "$n" -eq 0 ]; then
    echo "No findings."
  fi
  echo
  echo "## Confidence note"
  echo
  echo "retire.js fingerprints known library files by filename and version banner."
  echo "Recall against webpacked or rolled-up vendor chunks is weak: a bundled copy"
  echo "of a vulnerable library frequently carries neither. Treat this as a floor,"
  echo "not a ceiling -- a clean result here is not evidence of a clean dependency"
  echo "posture. Passive audit has no lockfile, so proper SCA needs the build repo."
} >> findings/dependencies.md
echo "  dependency findings=$n -> findings/dependencies.md"
