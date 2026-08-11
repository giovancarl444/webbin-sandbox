#!/usr/bin/env bash
# Sourced by every phase script. Loads config and enforces rules of engagement
# BEFORE any network call. This is deliberately code rather than documentation:
# a rule that lives only in a README gets skipped at 2am.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1090
source "${AUDIT_ENV:-audit.env}"
: "${TARGET_URL:?}" "${TARGET_HOST:?}" "${REQ_DELAY_MS:?}"
export TARGET_URL TARGET_HOST EXTRA_HOSTS AUDIT_UA REQ_DELAY_MS CONCURRENCY \
       MAX_ROUTES PAGE_TIMEOUT_MS FULL_PAGE_SHOTS

is_loopback() {
  case "${1%%:*}" in localhost|127.0.0.1|::1|0.0.0.0) return 0 ;; *) return 1 ;; esac
}

# --- Interlock 1: authorization ---------------------------------------------
# Loopback fixtures are self-evidently ours. Everything else needs a written
# attestation, per the engagement rules.
if ! is_loopback "$TARGET_HOST" && [ -z "${OWNERSHIP:-}" ]; then
  cat >&2 <<EOF
REFUSED: OWNERSHIP is empty and target '$TARGET_HOST' is not loopback.

Passive or not, we do not fetch another party's site without a written basis.
Set OWNERSHIP in ${AUDIT_ENV:-audit.env} to one of:
  "we own and operate this site"
  "written authorization from <party>, dated <date>"
EOF
  exit 78
fi

# --- Interlock 2: honest contact ---------------------------------------------
if ! is_loopback "$TARGET_HOST" && [[ "${AUDIT_CONTACT:-}" == "SET_ME"* ]]; then
  echo "REFUSED: AUDIT_CONTACT unset. The UA lands in the target's logs; it must name a real monitored inbox." >&2
  exit 78
fi

# --- Interlock 3: host allowlist ---------------------------------------------
# Every fetch in the pipeline routes through this. There is no bypass.
ALLOWED_HOSTS="$TARGET_HOST${EXTRA_HOSTS:+,$EXTRA_HOSTS}"
export ALLOWED_HOSTS

guard_host() {
  local host="$1"
  local IFS=','
  for allowed in $ALLOWED_HOSTS; do
    [ "$host" = "$allowed" ] && return 0
  done
  echo "REFUSED: host '$host' is not in the declared allowlist ($ALLOWED_HOSTS)" >&2
  return 1
}

# Polite GET. The only network primitive any phase script may use.
# No -X, no -d: this function is physically incapable of a write request.
audit_get() {
  local url="$1"; shift
  local host; host="$(printf '%s' "$url" | sed -E 's#^[a-z]+://([^/]+).*#\1#')"
  guard_host "$host" || return 1
  sleep "$(awk "BEGIN{printf \"%.3f\", $REQ_DELAY_MS/1000}")"
  curl -sS --compressed --get \
       --user-agent "$AUDIT_UA" \
       --max-time 30 --retry 0 \
       --proto '=http,https' --location --max-redirs 5 \
       "$@" "$url"
}

log_phase() { printf '\n=== %s ===\n' "$*"; }
export -f guard_host is_loopback
