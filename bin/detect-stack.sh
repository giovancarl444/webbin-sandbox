#!/usr/bin/env bash
# Detect what a system is, from evidence in the tree. Emits a JSON profile.
#
# Every field is derived from a file that exists, never from a naming
# convention. Where the tree does not say, the field is null and the caller
# must ask -- a wrong guess here silently produces an unfaithful import, which
# is worse than no import at all.
set -euo pipefail
SRC="${1:?usage: detect-stack.sh <path-to-clone>}"
cd "$SRC"

has() { [ -e "$1" ]; }
j() { jq -r "$1 // empty" package.json 2>/dev/null; }

stack=null; framework=null; pm=null; port=null; install=null; build=null; start=null
node_req=null; services='[]'; envs='[]'

if has package.json; then
  stack='"node"'
  # Lockfile decides the package manager. package.json cannot.
  if   has bun.lockb || has bun.lock;   then pm='"bun"'
  elif has pnpm-lock.yaml;              then pm='"pnpm"'
  elif has yarn.lock;                   then pm='"yarn"'
  elif has package-lock.json;           then pm='"npm"'
  else pm=null; fi

  deps="$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys | join(" ")' package.json 2>/dev/null || echo "")"
  case " $deps " in
    *" next "*)    framework='"nextjs"'; port=3000 ;;
    *" nuxt "*)    framework='"nuxt"';   port=3000 ;;
    *" @remix-run/react "*) framework='"remix"'; port=3000 ;;
    *" vite "*)    framework='"vite"';   port=5173 ;;
    *" react-scripts "*) framework='"cra"'; port=3000 ;;
    *" @angular/core "*) framework='"angular"'; port=4200 ;;
    *" express "*|*" fastify "*|*" koa "*) framework='"node-server"'; port=3000 ;;
    *" astro "*)   framework='"astro"';  port=4321 ;;
    *)             framework='"node-other"' ;;
  esac
  [ -n "$(j '.engines.node')" ] && node_req="\"$(j '.engines.node')\""
  [ -n "$(j '.scripts.build')" ] && build='"build"'
  for s in start dev serve; do [ -n "$(j ".scripts.$s")" ] && { start="\"$s\""; break; }; done

elif has requirements.txt || has pyproject.toml || has Pipfile; then
  stack='"python"'
  if   has poetry.lock;   then pm='"poetry"'
  elif has uv.lock;       then pm='"uv"'
  elif has requirements.txt; then pm='"pip"'; fi
  if   has manage.py;     then framework='"django"'; port=8000
  elif rg -qi 'fastapi' . --max-count 1 -g '*.py' 2>/dev/null; then framework='"fastapi"'; port=8000
  elif rg -qi '^from flask|^import flask' . --max-count 1 -g '*.py' 2>/dev/null; then framework='"flask"'; port=5000
  fi

elif has composer.json; then
  stack='"php"'; pm='"composer"'
  has artisan && { framework='"laravel"'; port=8000; }
elif has Gemfile; then
  stack='"ruby"'; pm='"bundler"'
  has config.ru && { framework='"rails"'; port=3000; }
elif has go.mod; then stack='"go"'; port=8080
elif [ -n "$(find . -maxdepth 2 -name '*.html' -not -path './.git/*' -print -quit)" ]; then
  # No manifest and HTML at the root: a static site. Real, and common.
  stack='"static"'; framework='"static"'; port=8080
fi

# Services are read from compose, not inferred from dependency names -- an
# app can import a postgres driver and still talk to a managed instance.
compose="$(ls docker-compose.y*ml compose.y*ml 2>/dev/null | head -1 || true)"
# `|| true` INSIDE the pipeline, not after it. ripgrep exits 1 on no matches;
# a trailing `|| echo '[]'` fires in addition to the pipeline's own empty
# result, concatenating two values into invalid JSON.
if [ -n "$compose" ]; then
  services="$({ rg -o --no-messages '\b(postgres|postgis|mysql|mariadb|redis|mongo|elasticsearch|rabbitmq|kafka|minio|clickhouse)\b' "$compose" || true; } \
              | sort -u | jq -R . | jq -s .)"
fi

# Required env vars, from the example file the repo already ships.
envfile="$(ls .env.example .env.sample .env.template 2>/dev/null | head -1 || true)"
if [ -n "$envfile" ]; then
  envs="$({ grep -oE '^[A-Z][A-Z0-9_]*' "$envfile" || true; } | sort -u | jq -R . | jq -s .)"
fi

jq -n \
  --arg path "$SRC" \
  --arg sha "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
  --arg compose "$compose" --arg envfile "$envfile" \
  --argjson stack "$stack" --argjson framework "$framework" --argjson pm "$pm" \
  --argjson port "${port:-null}" --argjson node_req "$node_req" \
  --argjson build "$build" --argjson start "$start" \
  --argjson services "$services" --argjson envs "$envs" \
  --arg dockerfile "$(ls Dockerfile 2>/dev/null || true)" \
  --arg size_mb "$(du -sm . 2>/dev/null | cut -f1)" \
  --arg files "$(find . -type f -not -path './.git/*' | wc -l)" \
  '{path:$path, sha:$sha, size_mb:($size_mb|tonumber), files:($files|tonumber),
    stack:$stack, framework:$framework, package_manager:$pm, port:$port,
    node_required:$node_req, build_script:$build, start_script:$start,
    has_dockerfile:($dockerfile != ""), compose_file:$compose,
    services:$services, env_file:$envfile, env_required:$envs}'
