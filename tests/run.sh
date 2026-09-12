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
WARP_TEST_ARTIFACT_DIR="$BUILD_DIR" "$LUA_BIN" tests/finder.lua
if command -v osacompile >/dev/null 2>&1; then
  for SOURCE in "$BUILD_DIR"/*.applescript; do
    osacompile -o "$SOURCE.scpt" "$SOURCE"
  done
  echo 'PASS: Finder enumeration/reuse/creation AppleScript compile (not executed)'
fi
bash -n install.sh tests/run.sh tests/install.sh
bash tests/install.sh
