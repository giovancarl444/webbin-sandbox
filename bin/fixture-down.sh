#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
for name in site cdn; do
  pidfile=".audit-raw/$name.pid"
  [ -f "$pidfile" ] || continue
  pid="$(cat "$pidfile")"
  kill "$pid" 2>/dev/null && echo "stopped $name (pid $pid)" || echo "$name not running"
  rm -f "$pidfile"
done
