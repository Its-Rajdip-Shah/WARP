#!/bin/bash
set -euo pipefail
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/warp-install.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/config with spaces"
printf '%s\n' '-- User configuration must survive' 'answer = 42' > "$TEST_DIR/config with spaces/init.lua"
cp "$TEST_DIR/config with spaces/init.lua" "$TEST_DIR/original"
bash install.sh --config-dir "$TEST_DIR/config with spaces" >/dev/null
cmp "$TEST_DIR/original" "$TEST_DIR/config with spaces/init.lua"
bash install.sh --install-loader --config-dir "$TEST_DIR/config with spaces" >/dev/null
head -n 2 "$TEST_DIR/config with spaces/init.lua" > "$TEST_DIR/prefix"
cmp "$TEST_DIR/original" "$TEST_DIR/prefix"
cp "$TEST_DIR/config with spaces/init.lua" "$TEST_DIR/installed"
bash install.sh --install-loader --config-dir "$TEST_DIR/config with spaces" >/dev/null
cmp "$TEST_DIR/installed" "$TEST_DIR/config with spaces/init.lua"
[ "$(find "$TEST_DIR/config with spaces" -name 'init.lua.warp-backup.*' | wc -l | tr -d ' ')" = 1 ]
echo 'PASS: installer dry run, preservation, backup, idempotency, spaces'
