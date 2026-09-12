# WARP implementation report

## Current decision: Finder is GLOBAL

Finder is entirely unmanaged, like ChatGPT. Live testing exposed fragile window identity and adoption across Spaces. The previous left/right adoption design and subsequent AppleScript identity patch are retired. They are available in Git history, not current behavior or acceptance criteria.

WARP performs no Finder discovery, directory navigation, Downloads reset, window creation/closure, minimize, resize, display/Space move, checkpoint, restore, ownership assignment, primary focus, or Space registration. Finder cannot contribute a restore failure. Its state stays under the user's manual control in ACTIVE, WARM and COLD workflows, including reload and shutdown.

## Changes by file

| File | Change |
|---|---|
| `src/warp/adapters/finder.lua` | Deleted the adapter, AppleScript enumeration/parser/creation/navigation, correlation, role assignment, state capture and diagnostics. |
| `src/warp/windows.lua` | Removed Finder evidence collection; unknown/unmanaged adapters return no windows before any app query. |
| `src/warp/ownership.lua` | Removed Finder from the managed bundle allowlist, also excluding it from the window filter. |
| `src/warp/manager.lua` | Removed Finder factory, checkpoint special case, restore outcome plumbing used by Finder, and diagnostic request lifecycle. |
| `src/warp/spaces.lua` | Removed Finder-specific focus handling. `primary = 'none'` returns successfully without focus or `gotoSpace`. |
| `src/init.lua` | Removed `WARP.debugFinder()`. Existing loader and other API methods remain. |
| `src/warp/config.lua` | Normalizes obsolete Finder fields with warnings and supports no-primary activation. |
| `src/warp/state.lua` | Drops obsolete Finder state while preserving other workflow data. |
| `config/workflows.lua` | Replaces Finder-only ELEC3609/SOFT2412 definitions with minimal no-primary entries. |
| `tests/finder.lua` | Deleted obsolete adoption regression suite. |
| `tests/finder_global.lua` | Adds config, state, discovery/filter exclusion and lifecycle non-interference regressions. |
| `tests/unit.lua` | Removes Finder factory and obsolete failure test; retains unrelated behavioral coverage. |
| `tests/run.sh`, `tests/syntax.lua` | Runs the replacement suite, removes obsolete Finder AppleScript compilation. |
| `README.md`, `docs/workflow-manager.md`, this report | Updates current policy, migration, configuration and acceptance expectations. |

No unrelated adapter, wheel, lifecycle implementation or installer was redesigned. No live Finder operation or edit to `~/.hammerspoon/init.lua` was performed.

## Configuration

Configuration remains declarative Lua in `config/workflows.lua`, keyed by stable lowercase IDs. Each entry requires `label` and a unique numeric string `key`. Optional fields:

| Field | Meaning |
|---|---|
| `safari` | `tabGroup`; optional exact localized `menuPath` array. |
| `vscode` | `allowedRoots`; optional `openRoots` beneath allowed roots and `cliPath`. Roots cannot overlap across workflow owners. |
| `terminal` | Unique safe `tmuxSession`; optional absolute/tilde `root` and `tmuxPath`. Root defaults to home. |
| `apps` | Array of `figma`/`docker` declarations, optional matching `name`, `preferredFullscreen`, `warm='preserve'`, `cold='preserve'` or `'resource_aware'`. |
| `primary` | Configured adapter ID, `'desktop'` (default), or `'none'`. None suppresses activation focus/navigation; adapters still restore if configured. |
| `spaceOrder` | Unique ordered roles from desktop, safari, figma, vscode, terminal, docker. |
| `coldAfterMinutes`, `pinned` | Positive timeout (default 30 minutes) and optional pin. |

Legacy `finder` values, even malformed blocks, are ignored. Legacy `primary='finder'` becomes `'none'`; Finder entries are removed from `spaceOrder`. Any combination produces one clear warning per affected workflow per config load, exposed in the normalized config's `warnings` and logged by the loader. Input tables are not mutated. Other invalid config still fails validation.

If Terminal previously inherited `finder.leftRoot`, set `terminal.root` explicitly to retain that working directory. No Finder path is read or validated now.

Exact current ELEC3609/SOFT2412 config (formatting aside):

```lua
return {
  elec3609 = { label = 'ELEC3609', key = '1', primary = 'none' },
  soft2412 = { label = 'SOFT2412', key = '2', primary = 'none' },
}
```

These entries preserve the user's current minimal testing scope. They select workflow metadata without launching managed apps or navigating to a primary Space. Add other adapters and real paths deliberately using the README example. There is no Finder replacement directory setting.

Settings retain `stateDirectory`, `notifications` and optional navigation hotkeys (`navigation=false` disables them). The default state path is `~/.workflow-manager/state.json`.

## Persisted state migration

Schema version **1** remains compatible: this removes optional data, not the format. The loader copies unrelated shared metadata, drops `shared.finder`, skips window records keyed `finder`/`finder:*` or tagged `adapter='finder'` before validating them, and removes Finder retention reasons. Workflow-local Finder fields are not copied. Thus malformed obsolete Finder records cannot disable persistence for otherwise valid state.

Other window records, saved geometry, active workflow, lifecycle, last-active time, pins, Safari metadata and terminal commands retain their existing handling. Runtime window/process/Space IDs remain untrusted and are cleared; Space entries are rebuilt. Finder contributes no entries. The general desktop fallback still exists for ordinary navigation; it is not discovered through Finder.

The raw input is not modified. The next normal atomic save persists sanitized data. Unreadable JSON or invalid unrelated state still disables writes to preserve the original file. No state file was manually deleted or rewritten during implementation.

## Remaining adapter behavior and limits

- Safari remains shared and uses verified sidebar Accessibility selection or an explicitly configured menu path. Hidden/ambiguous UI can report a partial failure; no fabricated Tab Group scripting API is used.
- VS Code ownership uses the explicit `[WARP:${rootPath}]` title marker and path boundaries. Multiple distinct projects work; ambiguous duplicate-root windows and unmarked windows remain unmanaged. Reopening needs the CLI. Unsaved editors are not closed.
- Terminal uses a dedicated tmux session/viewer marker and records pane commands. Viewer ownership can become ambiguous; sessions, shells and foreground processes are retained.
- Exclusive Figma and Docker UI can restore layout and minimize on WARM. Shared UI is unmanaged. Native document restoration remains app-dependent; Docker containers/backend are never stopped.
- Normal managed windows minimize on WARM; native fullscreen windows survive. COLD records policy and retains resources when safe destruction is unproven. It does not currently guarantee RAM reduction.
- Dynamic layouts and Spaces use live discovery and normalized display geometry. Fullscreen display migration exits fullscreen only when needed and discovers the new Space. Missing screens fall back safely. Hammerspoon Space navigation is experimental and may animate; windows on unvisited Spaces can remain unavailable.
- New requests cancel WARP timers/helpers and invalidate stale callbacks. Already-delivered OS commands cannot be recalled. Adapter failures remain isolated and appear in status/console.

## Automated validation

`bash tests/run.sh` passes:

- Syntax checks for **23 Lua files** and shell scripts.
- **24 core behavioral tests**, including rapid-switch cancellation, non-Finder failure continuation, ownership, atomic/corrupt-state handling, fullscreen migration, wheel behavior, and lifecycle/start-stop cleanup.
- **5 Finder-global regression tests** covering malformed legacy config and one warning, no-primary migration, state preservation, Finder filter/discovery exclusion, zero Finder operations through activation/checkpoint/WARM/COLD/reload, no Finder issue or primary Space jump, and continued calls to all five remaining adapters.
- Installer dry-run, preservation, backup, idempotency and paths-with-spaces checks.

Tests use mocks and a temporary Lua host if needed. No live GUI actions or Finder AppleScript execution are part of this run. Passing them does not claim live macOS acceptance.

## Manual acceptance

1. Keep the existing Hammerspoon loader. Reload WARP after this checkout is updated. With the shipped config, switch ELEC3609 → SOFT2412 → ELEC3609 using the wheel and confirm status changes with zero restore issues.
2. Before switching, manually arrange Finder windows in arbitrary directories, including a non-Downloads folder. Confirm count, directories, size, position, minimized/fullscreen state and display remain unchanged through switches, checkpoint and COLD of the inactive workflow. Repeat with zero Finder windows: none should open.
3. Reload and repeat. No Finder diagnostics or ownership messages should appear. Legacy config, if tested in a temporary copy, produces one deprecation warning per workflow on load and no Finder restore issue. Restore the clean config afterward.
4. Enable other adapters one at a time with valid local resources. Verify their existing restore/WARM behavior and workflow navigation while Finder remains untouched. Other configured apps can focus themselves as part of their normal restore; no Finder-specific focus action exists.
5. Wheel-only preview remains available through `WARP.previewWheel(true)`; return to normal selection with `false`. Existing letter shortcuts should pass through and modifier release/Escape should dismiss the wheel.

Manual live acceptance remains for the owner. Do not rerun installation if the existing loader already works.
