#!/usr/bin/env bash
# Start an imported system and wait for it to answer. Separated from
# import-system.sh so the start strategy per stack stays readable.
# usage: import-run.sh <name> <port> <stack> <build_ok>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
NAME="$1"; PORT="$2"; STACK="$3"; BUILD_OK="${4:-true}"
SRC="imports/$NAME"; mkdir -p .audit-raw

bin/import-down.sh "$NAME" >/dev/null 2>&1 || true

pid=""
case "$STACK" in
  static)
    # No build step, no runtime: serve the tree exactly as it would be served
    # by a static host. Faithful for this class of site.
    python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SRC" \
      > ".audit-raw/$NAME-serve.log" 2>&1 &
    pid=$!
    ;;
  node)
    [ "$BUILD_OK" = "true" ] || { echo "  not starting: build did not succeed"; exit 1; }
    # Background the subshell itself, then exec into npm: $! in the parent is
    # then the server. Backgrounding *inside* a subshell leaves $! unset here.
    ( cd "$SRC" && PORT="$PORT" exec npm start ) > ".audit-raw/$NAME-serve.log" 2>&1 &
    pid=$!
    ;;
  python|php|ruby|go)
    echo "  start strategy for '$STACK' not implemented -- reporting rather than guessing"; exit 1 ;;
  *)
    echo "  unknown stack '$STACK'"; exit 1 ;;
esac
[ -n "$pid" ] && echo "$pid" > ".audit-raw/$NAME.pid"

for i in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$PORT/" 2>/dev/null || echo 000)"
  case "$code" in 2*|3*) echo "  responding $code after $((i / 2))s"; exit 0 ;; esac
  sleep 0.5
done
echo "  no healthy response on :$PORT after 30s"; exit 1
