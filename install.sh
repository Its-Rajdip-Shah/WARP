#!/bin/bash
# Appends one loader only on explicit request. Never replaces an existing init.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${HOME}/.hammerspoon"
INSTALL=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-loader) INSTALL=true; shift ;;
    --config-dir) [ "$#" -ge 2 ] || { echo 'Missing --config-dir argument' >&2; exit 2; }; CONFIG_DIR="$2"; shift 2 ;;
    --help) echo 'Usage: bash install.sh [--install-loader] [--config-dir PATH]'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
# Lua long strings safely represent spaces, quotes, backslashes and dollar signs.
DELIM='='
while [[ "$ROOT/src/init.lua" == *"]${DELIM}]"* ]]; do DELIM="${DELIM}="; done
LOADER="dofile([${DELIM}[$ROOT/src/init.lua]${DELIM}])"
INIT="$CONFIG_DIR/init.lua"
echo 'WARP loader:'
echo "$LOADER"
echo 'Grant Hammerspoon Accessibility in System Settings > Privacy & Security.'
echo 'Allow Automation prompts for Finder/Terminal. Reload Hammerspoon after configuring workflows.'
if ! "$INSTALL"; then
  echo 'No files changed. Use --install-loader to append the loader, or add it manually.'
  exit 0
fi
mkdir -p "$CONFIG_DIR"
if [ -L "$INIT" ]; then echo 'init.lua is a symlink; add the displayed loader manually.' >&2; exit 1; fi
if [ -f "$INIT" ]; then
  if grep -Fq 'WARP repository loader' "$INIT" || grep -Fq "$ROOT/src/init.lua" "$INIT"; then
    echo 'Existing WARP loader found; no changes.'; exit 0
  fi
  # Also recognize the established os.getenv("HOME") .. "/relative/path" bootstrap.
  if [[ "$ROOT" == "$HOME/"* ]] && grep -Fq "${ROOT#"$HOME"}/src/init.lua" "$INIT"; then
    echo 'Existing home-relative WARP loader found; no changes.'; exit 0
  fi
  BACKUP="$(mktemp "$CONFIG_DIR/init.lua.warp-backup.XXXXXX")"
  cp -p "$INIT" "$BACKUP"
  echo "Existing configuration backed up: $BACKUP"
fi
printf '\n-- WARP repository loader\n%s\n' "$LOADER" >> "$INIT"
echo "Loader appended to $INIT. Existing configuration preserved."
