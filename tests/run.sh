#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/warp-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
if command -v lua >/dev/null 2>&1; then
  LUA_BIN="$(command -v lua)"
else
  FRAMEWORK='/Applications/Hammerspoon.app/Contents/Frameworks'
  clang -I "$FRAMEWORK/LuaSkin.framework/Headers" -F "$FRAMEWORK" \
    -framework LuaSkin -Wl,-rpath,"$FRAMEWORK" tests/lua-runner.c -o "$BUILD_DIR/lua"
  LUA_BIN="$BUILD_DIR/lua"
fi
"$LUA_BIN" tests/syntax.lua
"$LUA_BIN" tests/unit.lua
"$LUA_BIN" tests/finder_global.lua
"$LUA_BIN" tests/safari_debug.lua
"$LUA_BIN" tests/safari_ax.lua
"$LUA_BIN" tests/vscode.lua
"$LUA_BIN" tests/cold.lua
bash -n install.sh tests/run.sh tests/install.sh
bash tests/install.sh
if command -v node >/dev/null 2>&1; then
  node --check extras/vscode-companion/extension.js
  node tests/companion.cjs
else
  echo 'SKIP: companion JavaScript checks (Node unavailable)'
fi
