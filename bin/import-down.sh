#!/usr/bin/env bash
# Stop an imported system and any services it brought up.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
NAME="${1:?usage: import-down.sh <name>}"

port="$(jq -r '.port // empty' "imports/_meta/$NAME.json" 2>/dev/null || true)"
if [ -n "$port" ]; then
  pids="$(ss -lptnH "sport = :$port" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | sort -u || true)"
  for p in $pids; do kill "$p" 2>/dev/null && echo "stopped pid $p on :$port" || true; done
fi
[ -f ".audit-raw/$NAME.pid" ] && { kill "$(cat ".audit-raw/$NAME.pid")" 2>/dev/null || true; rm -f ".audit-raw/$NAME.pid"; }

if [ -f "imports/$NAME/docker-compose.yml" ] && docker info >/dev/null 2>&1; then
  (cd "imports/$NAME" && docker compose down >/dev/null 2>&1) || true
fi
exit 0
