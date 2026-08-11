#!/usr/bin/env bash
# Import a client system into the sandbox and stand it up.
#
# usage: import-system.sh <name> [git-url] [port]
#
# Records what it substituted as it goes. An import that runs but silently
# differs from production is worse than one that fails loudly, because every
# downstream finding inherits the difference without saying so.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
NAME="${1:?usage: import-system.sh <name> [git-url] [port]}"
URL="${2:-}"; SRC="imports/$NAME"; META="imports/_meta"
mkdir -p "$META" "$ROOT/.audit-raw"
notes=(); t0=$(date +%s); stage() { printf '  [%3ds] %s\n' "$(( $(date +%s) - t0 ))" "$*"; }

# --- acquire ---------------------------------------------------------------
if [ ! -d "$SRC/.git" ] && [ -n "$URL" ]; then
  stage "cloning $URL"
  git clone --depth 1 --quiet "$URL" "$SRC"
fi
[ -d "$SRC" ] || { echo "no source at $SRC and no git-url given" >&2; exit 2; }
t_acquire=$(( $(date +%s) - t0 ))

# --- detect ----------------------------------------------------------------
profile="$(bin/detect-stack.sh "$SRC")"
stack=$(jq -r '.stack // "unknown"' <<<"$profile")
fw=$(jq -r '.framework // "unknown"' <<<"$profile")
PORT="${3:-$(jq -r '.port // 8080' <<<"$profile")}"
stage "detected: stack=$stack framework=$fw port=$PORT"

# --- preflight: runtime parity --------------------------------------------
# The single most common cause of a fake-successful import. Caught before
# install so we never claim a clean build on the wrong runtime.
node_req="$(jq -r '.node_required // empty' <<<"$profile")"
runtime_ok=true
if [ -n "$node_req" ]; then
  need="$(grep -oE '[0-9]+' <<<"$node_req" | head -1)"
  have="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$have" -lt "$need" ]; then
    runtime_ok=false
    notes+=("RUNTIME MISMATCH: repo requires node $node_req, sandbox has $have. Findings that depend on build output are NOT transferable until this is reconciled.")
    stage "PREFLIGHT WARN: node $have < required $need"
  fi
fi

# --- provision: env --------------------------------------------------------
envfile="$(jq -r '.env_file // empty' <<<"$profile")"
subs=0
if [ -n "$envfile" ] && [ ! -f "$SRC/.env" ]; then
  # Placeholders, never real secrets. Each substitution is a known divergence
  # from production and is recorded as one.
  sed -E 's/=.*/=SANDBOX_PLACEHOLDER/' "$SRC/$envfile" > "$SRC/.env"
  subs="$(grep -c 'SANDBOX_PLACEHOLDER' "$SRC/.env" || true)"
  notes+=("$subs env values replaced with placeholders; any behaviour gated on real credentials is unexercised.")
  stage "provisioned .env with $subs placeholders"
fi

# --- provision: services ---------------------------------------------------
svcs="$(jq -r '.services[]?' <<<"$profile" | tr '\n' ' ')"
if [ -n "${svcs// /}" ]; then
  if docker info >/dev/null 2>&1; then
    stage "starting services: $svcs"
    (cd "$SRC" && docker compose up -d $svcs >/dev/null 2>&1) \
      || notes+=("Service startup failed for: $svcs. Data-layer behaviour unexercised.")
  else
    notes+=("Services declared ($svcs) but docker unavailable; data layer NOT provisioned.")
  fi
fi
t_provision=$(( $(date +%s) - t0 ))

# --- install + build -------------------------------------------------------
# A runtime mismatch is recorded, not treated as a stop. Many apps run fine
# below their declared engines floor, and refusing to try teaches us nothing.
# What matters is that success on the wrong runtime is never reported as
# faithful -- the divergence rides along with every downstream claim.
build_ok=true; t_install=0; t_build=0
if [ "$stack" = "node" ]; then
  s=$(date +%s); stage "installing dependencies"
  (cd "$SRC" && npm ci --no-audit --no-fund >"$ROOT/.audit-raw/$NAME-install.log" 2>&1) \
    || { build_ok=false; notes+=("npm ci failed -- see .audit-raw/$NAME-install.log"); }
  t_install=$(( $(date +%s) - s ))
  if [ "$build_ok" = true ] && [ "$(jq -r '.build_script // empty' <<<"$profile")" != "" ]; then
    s=$(date +%s); stage "building"
    (cd "$SRC" && npm run build >"$ROOT/.audit-raw/$NAME-build.log" 2>&1) \
      || { build_ok=false; notes+=("build failed -- see .audit-raw/$NAME-build.log"); }
    t_build=$(( $(date +%s) - s ))
  fi
fi

# --- run + health check ----------------------------------------------------
s=$(date +%s); health="not_started"
bin/import-run.sh "$NAME" "$PORT" "$stack" "$build_ok" && health="healthy" || health="unhealthy"
t_start=$(( $(date +%s) - s ))
stage "health: $health on :$PORT"

jq -n --argjson p "$profile" --arg name "$NAME" --arg url "${URL:-local}" \
   --arg health "$health" --argjson port "$PORT" \
   --argjson runtime_ok "$runtime_ok" --argjson build_ok "$build_ok" \
   --argjson subs "${subs:-0}" \
   --argjson t "$(jq -n --argjson a $t_acquire --argjson pr $t_provision --argjson i $t_install \
                    --argjson b $t_build --argjson s $t_start --argjson tot $(( $(date +%s) - t0 )) \
                    '{acquire:$a, provision:$pr, install:$i, build:$b, start:$s, total:$tot}')" \
   --argjson notes "$(printf '%s\n' "${notes[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
   '{name:$name, source:$url, profile:$p, port:$port, runtime_ok:$runtime_ok,
     build_ok:$build_ok, env_placeholders:$subs, health:$health,
     timings_sec:$t, divergences:$notes}' > "$META/$NAME.json"

stage "total ${t_acquire}s acquire / $(jq -r .timings_sec.total "$META/$NAME.json")s overall -> $META/$NAME.json"
[ "$health" = "healthy" ] || exit 1
