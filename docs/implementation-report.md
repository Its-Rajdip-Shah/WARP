# Current Safari timing: one unresolved hop at a time

This targeted Safari revision supersedes the earlier three-second polling and immediate-transition descriptions below. Focus and the keyboard sequence are unchanged, as are all other subsystems.

After each Cmd+Shift+Down, the shared normal/debug core polls a new `sqlite3 -readonly` process about every **100 ms**, for up to **six seconds**. A changed `(window_id, active_tab_group_id)` starts a **400 ms stability interval**. Fresh reads must keep reporting that identity throughout the interval. A different observed ID resets the interval; reverting to baseline clears the candidate. Titles come from the latest confirming read.

Only after stability is confirmed does the core evaluate the target. Success returns immediately without scheduling another hop. Otherwise the existing cycle checks run, and only then can the next hop start. Initial discovery uses the same timing and confirmation; the row is bound after its stable transition and remains bound throughout the transaction.

A full six seconds with no observed transition permits the existing bounded refocus/retry (two retries, all counted toward eight keyboard attempts). If a transition occurred but remained unstable or reverted, timeout aborts instead of issuing another potentially overlapping hop. The outer transaction deadline is now **90 seconds**, replacing 25 seconds so multiple legitimate delayed hops are possible. It remains a hard limit; there are no blind six-second sleeps or idle polling. All stability/poll timers remain owned by the existing cancellable request.

Logs now identify `keyboard hop N sent`, `waiting for DB transition...`, `DB changed after ...ms` with both group IDs/titles, `confirming stable state...`, `stable after ...ms`, and then either `reached <target>` or the next hop. No-transition timeouts log actual elapsed milliseconds after the six-second window.

Files changed: `src/warp/safari_debug.lua`, `tests/safari_debug.lua`, `README.md`, `docs/workflow-manager.md`, and this report. No focus, keyboard, Code, COLD, Finder or other-subsystem code changed. Work remains uncommitted on `debug/safari-tab-groups`; no checkout/reset/stash/commit/merge/push was performed.

Regression validation: **24 core, 5 Finder, 27 Safari, 15 Code and 12 COLD tests (83 Lua tests)** pass, plus companion transport checks, 29 Lua syntax checks, JavaScript/shell syntax and installer checks. New coverage includes a 4.5-second delayed commit, stable confirmation before success, transient target/intermediate states, unstable/reverted transitions aborting without extra hops, true six-second retry intervals and six delayed hops on row 21 exceeding the old outer cutoff. The existing companion test requires native watcher access but uses only a temporary directory and mocked Code APIs. No live Safari GUI success is claimed.

Live test:

```lua
WARP.reload()
```

Put Safari on **17 Tabs**, then run **only**:

```lua
WARP.debugSafariSwitch("SOFT2412")
```

Watch the changed/stable logs and verify Safari stops visibly on SOFT2412 without another keyboard hop. The expected live group order is 17 Tabs → SOFT2201 → ENGG3112 → ELEC2602 → SOFT2412, with commit delays as needed. Only after this succeeds, test `WARP.debugSafariSwitch("ELEC3609")`, followed by normal `WARP.switchTo("soft2412")` and `WARP.switchTo("elec3609")`.

A 400 ms quiet observation window is a bounded stability check, not proof that Safari can never commit another update later. Missing/ambiguous rows, failure to stabilize by the deadline, or targets beyond eight hops still fail safely. Live verification remains necessary.

---

# Safari DB polling correction

The current shared Safari core polls fresh `sqlite3 -readonly` reads every 100 ms for up to **three seconds after each keyboard hop**, stopping immediately on an observed group-ID transition. Focus, keyboard input, discovery binding, retry count and unrelated modules are unchanged.

Trace findings: every existing poll already launched a new sqlite process and parsed a new snapshot. There was no cached output or object-identity comparison. The old cutoff was only two seconds, after which WARP could send another hop before a delayed commit was observed. A deterministic 2.8-second commit now succeeds with one hop. The supplied manual evidence does not measure the live commit delay, so it does not conclusively establish that this cutoff alone explains the live failure; elapsed-time logs now make that verifiable.

The old comparison included both group ID and title, so duplicate `Local` titles were not by themselves a missed-progress bug. The corrected authoritative identity is now `(window_id, active_tab_group_id)`: title-only renames cannot create false progress, and different IDs with identical titles do count. Both snapshots retain titles for logging. The exact supplied rows correctly identify window 21 changing `44997/Local -> 46183/SOFT2201`.

Logs now include `before={19:39936/Local,21:44997/Local}`, `waiting for DB progress...`, `DB progress after <elapsed>ms`, ID/title transitions when binding, and `no DB mutation after <elapsed>ms` only after the full settle timeout. No fixed three-second sleep was added. Each read finishes before another poll or keyboard retry starts. The existing 25-second transaction limit can still terminate slow exceptional transactions without sending additional keys.

Files changed for this correction: `src/warp/safari_debug.lua`, `tests/safari_debug.lua`, `README.md`, `docs/workflow-manager.md`, and this report. Documentation edits outside this note only correct the Safari settle duration. All previous local work remains intact; no commits/pushes or live GUI actions were performed.

Validation: **24 core + 5 Finder + 23 Safari + 15 Code + 12 COLD = 79 Lua tests**, companion transport/guard checks, 29 Lua syntax checks, JavaScript/shell syntax and installer checks pass. New regressions cover duplicate Local titles, ID-only transitions, title-only non-transitions, fresh process reads, 850 ms and 2.8-second delayed commits without extra hops, prompt early completion and full three-second no-progress intervals before retries. Native watcher access was needed only for the existing temporary companion test. GUI success remains unverified.

Live test: run `WARP.reload()`, then put Safari on the ungrouped **17 Tabs** state. Run each command separately, waiting for completion:

```lua
WARP.debugSafariSwitch("SOFT2412")
WARP.debugSafariSwitch("ELEC3609")
WARP.switchTo("soft2412")
WARP.switchTo("elec3609")
```

Inspect the initial IDs, measured DB progress delay and `bound db window=21 44997/Local -> 46183/SOFT2201` (actual group/order may vary), then `reached <target>`. If no mutation appears within three seconds, the timeout log provides the next live evidence without implying a focus/keyboard redesign is needed.

---

# Current Safari revision: focus, actuate, observe, bind

This Safari-only revision supersedes the earlier preselected-window and already-active shortcut descriptions below. All Code/COLD/Finder/other-adapter implementation remains unchanged.

## Safari files changed in this revision

- `src/warp/safari_debug.lua`: shared normal/debug core now discovers the controlled DB row after keyboard actuation.
- `tests/safari_debug.lua`: replaces obsolete preselection tests with 20 deterministic focus/discovery/regression tests.
- `README.md`, `docs/workflow-manager.md`, this report: current Safari policy, bounds and live-test steps.

The normal adapter and debug API continue to use the same `manager.safari.switcher` instance; no second strategy was added. No source outside the Safari core changed in this revision. Existing uncommitted work is preserved on `debug/safari-tab-groups`. No checkout, reset, stash, commit, merge or push was performed.

## Existing hotkey behavior reused

Read-only inspection of `~/.hammerspoon/init.lua` found the app launcher at lines 144–170: `hyper = {"ctrl", "alt", "cmd"}`, `appMap.s = "Safari"`, and the callback calls `hs.application.launchOrFocus(appName)`. WARP now invokes **`hs.application.launchOrFocus("Safari")` directly**. It does not simulate hyper+S or edit/import the user's init file.

## Exact Safari algorithm

1. Launch/focus Safari using that helper. Confirm its bundle ID is frontmost with temporary 50 ms checks. Allow one second per focus attempt and two attempts before graceful failure.
2. Read all open DB window rows using the existing fixed SELECT and `/usr/bin/sqlite3 -readonly`. No row is preselected by title, Local/Root status or array position.
3. Always send plain `hs.eventtap.keyStroke({"cmd"}, "l")`, wait asynchronously for 150 ms, then plain `hs.eventtap.keyStroke({"cmd", "shift"}, "down")`. If focus is lost during that delay, reacquire and restart Cmd+L, bounded to two interruptions.
4. Poll DB snapshots every 100 ms for up to two seconds, stopping on progress. Exactly one changed row binds the transaction to that window. Multiple changes, row creation/removal or a later change in a different row abort as ambiguous.
5. If the bound row's title is the target, finish. Otherwise ensure Safari is frontmost, reacquiring if necessary, then repeat. Zero progress allows two refocus/retries; they count toward the total eight keyboard-hop cap. Full/repeated cycles abort if they do not reach the target.
6. Cancel timers/tasks on success, failure, parent cancellation, stop or reload. A 25-second outer deadline bounds exceptional focus/DB delays; there is no background focus or DB monitor. The sqlite helper retains its three-second timeout.

An already-active target is intentionally not detected before discovery: Safari can cycle away and back. A target shown in some other DB row cannot short-circuit success. The old `select()`/preselected-window logic, already-active shortcut and immediate `Safari lost focus` failure are removed. All production/debug logging now uses `[WARP][SAFARI]`, with `before={...}`, `discovery hop`, `bound db window=...`, progress, retries and reached/ABORT messages.

## Safari checks and limitations

The complete suite passes: 24 core, 5 Finder, **20 Safari**, 15 dynamic Code and 12 COLD tests, plus companion transport/command-guard checks, 29 Lua syntax checks, JavaScript/shell syntax and installer checks. The existing companion test needs native filesystem-watcher access; it remains mocked and confined to a temporary directory. No live Safari switching was executed by the agent. Passing tests does not establish GUI success.

Safari requires readable native DB state (Full Disk Access on this Mac), functional keyboard switching and a unique changed row. Concurrent user/app changes can make a transaction ambiguous. One-group/no-progress cases fail after bounded retries. More than eight required keyboard hops cannot reach the target in one transaction. Foreground may be actively reacquired during the short transaction, but never indefinitely. An already-delivered OS activation/key event cannot be recalled by cancellation. Finder and all tab contents/session files remain untouched by this code.

## Exact Safari live test

1. Open Safari manually.
2. Put it on **ELEC3609**.
3. Run `WARP.reload()`.
4. Run `WARP.debugSafariSwitch("SOFT2412")`; expect Safari visibly reaches SOFT2412.
5. Run `WARP.debugSafariSwitch("ELEC3609")`; expect Safari visibly reaches ELEC3609.
6. Run `WARP.switchTo("soft2412")`; expect Safari reaches SOFT2412 and Code target visibility continues working.
7. Run `WARP.switchTo("elec3609")`; expect Safari reaches ELEC3609.

Wait for each transaction to finish before starting the next. Expect logs identifying the actual changed row (which may be 19 rather than 21), followed by `reached <target>`. If a test fails, the explicit ABORT reason and before/bound/hop logs identify the stage; no alternate sidebar strategy is attempted.

---

## Previous MVP notes (Safari preselection descriptions superseded above)

# Current MVP: Safari convergence, Code visibility and guarded COLD restore

This section is the current implementation report. The prior notes below are historical milestones; their debug-only Safari, live-window-only Code restore, and source-only warm descriptions are superseded here.

## Architecture implemented

Normal Safari restore and `WARP.debugSafariSwitch()` share the existing `safari_debug.lua` core and the same instance. The old sidebar AX traversal/selection is removed. Safari must already be running. A fixed SELECT through `/usr/bin/sqlite3 -readonly` observes native group state; Cmd+L then Cmd+Shift+Down actuates it. The selected database row stays fixed, Local is valid during cycling, and errors/cycles/repeats/ambiguity stop safely. Eight hops and a 12-second overall bound apply. Stop, reload and replacement requests cancel the helper. No database writes, tab reconstruction, URL navigation or tab closure is used. Safari failure is reported but later adapters still run. Legacy `menuPath` is ignored with a deprecation warning.

Code retains the live-tested six-consecutive-ten-second focus qualification and additive owners. Activation now converges **all** live normal Code windows to the target: owners restore/show, every non-owner minimizes, including unowned windows. Reselecting the same workflow repairs visibility drift. Source warming no longer acts on Code, eliminating shared-window minimize/restore flicker. Per-window restore errors are isolated so later windows and adapters continue. Existing fullscreen behavior is retained; a non-target fullscreen Code window reports that it cannot safely minimize instead of forcing a new Space migration.

Runtime membership stays separate from persistent logical COLD records. The manager gives the adapter access to the store for write-ahead close/reopen intent. Lifecycle still uses its existing 30-minute WARM threshold and minute tick; COLD starts guarded asynchronous close work. No permanent Code polling loop was introduced.

## How descriptors are learned

Read-only investigation of the installed Code sources and native storage found that represented filename is the **active editor file**, while `windowsState` contains folder/workspace entries without a trustworthy Hammerspoon window mapping. Neither a title, active editor file, cached geometry nor that saved list is used to guess a project.

The bundled `extras/vscode-companion` extension reads actual `vscode.workspace.workspaceFile` or the single local `workspaceFolders` URI. It supports saved local workspaces and local folders, with no folder configuration. It rejects remote, untitled and untrusted workspaces. Each Code window gets a random companion session. A fresh nonce request/response, one focused companion and unchanged Hammerspoon native focus bind that session to the runtime window after qualification. A later COLD inspection refreshes the descriptor from the same verified session, so changing folders does not make an old root authoritative.

The companion uses a private local filesystem transport at `~/.workflow-manager/vscode-bridge`, independent of the configured persistence directory. It watches requests with `fs.watch`; WARP polls only during bounded requests (two seconds), never when idle. Requests expire and session-targeted close commands revalidate the descriptor. No network, resident external Node service, title marker, configured roots, telemetry or process-killing helper is added.

**One-time companion installation is required for real COLD reclamation.** The repository includes its source and a dependency-free local VSIX builder. It has been packaged, not installed into the user's live Code. Without it, Safari/Code visibility and membership work normally, while COLD logs that no verified descriptor exists and preserves the window. There is no per-project setup.

## COLD state and safeguards

For each live owned window, another ACTIVE or WARM owner prevents closure. Missing verification, dirty text/notebook documents, any integrated terminal, changed session, inaccessible persistence or unsafe descriptor also preserves it. Before requesting closure, WARP atomically saves `close_requested`, the descriptor, logical owners and available geometry. The companion rechecks the current workspace and dirty/terminal conditions and invokes the native `workbench.action.closeWindow` command in that window. It never force-quits Code, clicks Discard, kills processes or closes a shared window still needed by a live workflow.

Only observed destruction following that intent becomes `warp_cold_closed`. A veto, timeout, cancellation or uncertain reply stays `close_uncertain`/`close_requested` and does not authorize automatic reopening. User closure without WARP intent never creates a restore record; normal checkpoint cleanup removes the runtime owner. Pending close markers are cleared on cancellation so a later unrelated user closure cannot be misclassified.

Activation reuses an existing verified matching session when possible. Otherwise only a confirmed WARP-closed record may launch `code --new-window <learned folder or saved workspace file>`. VS Code distinguishes folder paths from saved workspace files itself. A write-ahead `reopen_pending` state prevents duplicate relaunch after cancellation/reload. The new focused native window must be absent from the prelaunch set and its nonce-verified companion descriptor must match before runtime membership is rebound to all logical owners. Available normal geometry then uses the existing window restore helper. Native Code owns editor restoration.

If an unmapped existing window might already contain the project, companion inventory must account for all enumerated live windows and exclude the target before launch. A matching-but-unbound or otherwise ambiguous window defers reopening. Failed verification leaves the record pending for manual inspection, never repeated blind launching. Version 1 persistence remains compatible; runtime IDs are stripped, while explicit COLD records/descriptors/owners survive reload. Live, non-closed memberships still require relearning after reload.

## Files changed in this MVP task

- `src/warp/adapters/safari.lua`, `src/warp/safari_debug.lua`: shared production/debug switching core; removes sidebar path.
- `src/warp/adapters/vscode.lua`: target visibility, isolated restore failures, COLD/descriptor integration.
- `src/warp/vscode_bridge.lua`, `src/warp/vscode_cold.lua`: companion transport, safe close/reopen and logical records.
- `src/warp/manager.lua`, `src/init.lua`: shared Safari instance, cancellation, store integration and COLD ordering.
- `src/warp/state.lua`, `src/warp/request.lua`, `src/warp/config.lua`: persistent intents, cleanup hooks and obsolete Safari config migration.
- `extras/vscode-companion/package.json`, `extension.js`, `package.py`: companion and local VSIX packaging.
- `tests/safari_debug.lua`, `tests/vscode.lua`, `tests/cold.lua`, `tests/companion.cjs`, `tests/run.sh`, `tests/syntax.lua`: regression and transport checks.
- `README.md`, `docs/workflow-manager.md`, this report: current setup, policy and limitations.

Earlier local edits to workflow config, ownership, Finder tests and core tests remain intact. Finder, ChatGPT, Terminal, Figma, Docker, wheel, generic window/Space helpers and the lifecycle timer implementation were not changed by this task. `~/.hammerspoon/init.lua` was not modified. Branch remains `debug/safari-tab-groups`; nothing was committed, merged or pushed.

## Validation and limits

The full suite passes: **24 core tests, 5 Finder tests, 12 Safari tests, 15 Code membership/visibility tests, 12 COLD tests**, plus a companion filesystem/command-guard test, **29 Lua syntax checks**, JavaScript/shell syntax and installer checks. The VSIX builder succeeds without npm downloads. The companion test uses a real temporary filesystem watcher and mocked VS Code APIs. It initially failed inside the restricted watcher sandbox, then passed with native watcher access. No live Code windows were closed/reopened, Safari groups switched, or companion installed by the agent.

The user's prior live evidence establishes qualification and Safari core behavior, but the integrated path and new companion require live acceptance. Normal switches should usually fit the 10–15-second goal; cold launches, unavailable apps and multiple restores can exceed it within their individual bounds. Safari DB IDs still do not establish native keyboard-window identity, so the intended Safari window must be frontmost within Safari. Non-target fullscreen Code, unavailable companion, remote/untrusted/untitled workspaces, integrated terminals and ambiguous close/reopen outcomes remain conservative limitations. Cancel cannot recall an OS close/launch command already delivered.

## Exact live acceptance sequence

1. Install the companion once from the repository root:
   ```sh
   python3 extras/vscode-companion/package.py
   "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --install-extension /tmp/warp-companion-0.1.0.vsix
   ```
   Reload existing Code windows so the companion activates. Keep the existing Hammerspoon loader. No folder settings are needed.
2. Run `WARP.reload()`. Put the intended Safari workflow window frontmost within Safari, then run `WARP.switchTo("soft2412")`. Expect `[WARP][SAFARI] SOFT2412 -> reached SOFT2412`, with no sidebar-row error. Unknown Code windows should minimize. Finder stays untouched.
3. Manually restore/focus a Code window and work continuously for over 60 seconds. Expect six qualification logs, `ADOPT`, then `restore descriptor learned` shortly afterward. Inspect `WARP.debugVSCodeOwnership()` for runtime owners and the learned folder/workspace descriptor.
4. Qualify that same window under ELEC3609. Switch both ways: shared target windows remain visible, while unowned and other-workflow-only windows minimize. Manually unminimize an unowned window, then reselect the current workflow: it should minimize again.
5. Use a second normal window belonging only to SOFT2412 for COLD testing. It must have a verified descriptor, no dirty text/notebook documents and no integrated terminals. Switch to ELEC3609, then run `WARP.makeCold("soft2412")` (or wait roughly 30 minutes). Expect a persisted logical close intent and `cold-close ... confirmed`. The ACTIVE/WARM-shared window must remain alive.
6. Run `WARP.switchTo("soft2412")`. Expect `reopen logical=...`, a verified new native window, `rebound ... id=...`, restored ownership and geometry. The new ID may differ. Check native editor restoration manually.
7. Separately close an owned test window yourself, checkpoint its owner and switch away/back. It must not reopen. Repeat COLD with dirty work, an integrated terminal, a missing companion or a WARM co-owner: preserve logs and no close are expected.
8. Confirm `WARP.debugSafariSwitch("ELEC3609")` still uses the same mechanism while no switch is running. Test stop/reload during qualification and pending work: old checks/helpers must stop. Inspect any pending/uncertain logical record before manual recovery; do not delete it or repeatedly trigger blind relaunches.

---

## Historical implementation notes (superseded where noted above)

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
| `vscode` | `true` or `{}` enables additive focus-learned membership. Legacy root/CLI fields are ignored with a warning. |
| `terminal` | Unique safe `tmuxSession`; optional absolute/tilde `root` and `tmuxPath`. Root defaults to home. |
| `apps` | Array of `figma`/`docker` declarations, optional matching `name`, `preferredFullscreen`, `warm='preserve'`, `cold='preserve'` or `'resource_aware'`. |
| `primary` | Configured adapter ID, `'desktop'` (default), or `'none'`. None suppresses activation focus/navigation; adapters still restore if configured. |
| `spaceOrder` | Unique ordered roles from desktop, safari, figma, vscode, terminal, docker. |
| `coldAfterMinutes`, `pinned` | Positive timeout (default 30 minutes) and optional pin. |

Legacy `finder` values, even malformed blocks, are ignored. Legacy `primary='finder'` becomes `'none'`; Finder entries are removed from `spaceOrder`. Any combination produces one clear warning per affected workflow per config load, exposed in the normalized config's `warnings` and logged by the loader. Input tables are not mutated. Other invalid config still fails validation.

If Terminal previously inherited `finder.leftRoot`, set `terminal.root` explicitly to retain that working directory. No Finder path is read or validated now.

Historical minimal config from the Finder-global change (current local config also opts into Safari and VS Code):

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
- VS Code uses additive runtime window membership learned by six consecutive ten-second focus checks. No title/path matching or project reopening remains. See the dynamic membership section below.
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

## Temporary Safari Tab Group debug experiment

`WARP.debugSafariSwitch("SOFT2412")` is an opt-in debug experiment, **not wired into normal workflow switching**. The existing Safari adapter is unchanged. The user empirically verified native group changes with Cmd+L followed by Cmd+Shift+Down on this Mac; `selectMenuItem()` was rejected for this experiment because it returned true without changing groups. This path uses neither menus nor AX sidebar clicking and does not require the sidebar.

The helper invokes `/usr/bin/sqlite3 -readonly -batch` asynchronously against `~/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db`. Its sole SQL statement is a fixed SELECT joining open `windows` to `bookmarks`. Titles are hex-encoded for safe row parsing; the target is compared only in Lua, never inserted into SQL. There are no writes, schema changes, attachment commands or tab-content operations.

Initially exactly one non-empty, non-Local, non-Root group row must identify the candidate window. Ambiguity aborts. The selected `window_id` is logged and pinned for the entire invocation, including when its group becomes Local. This DB selection does **not** establish an AX/native keyboard-window identity. Before testing, make the intended Safari window the frontmost window within Safari; leave other Safari windows unchanged. An observed change in another DB window aborts further shortcuts, but cannot undo a shortcut already delivered. No undocumented window blob matching or window rearrangement is attempted.

The operation requires Safari already running. If the selected group already matches, no activation or keys occur. Otherwise Safari activates and receives Cmd+L, then Cmd+Shift+Down after an asynchronous 150 ms delay. Each hop waits 350 ms before reading, then polls unchanged state every 250 ms for up to two seconds. Read/process/parse failure, lost Safari focus, secure input, missing selected window, repeated state, full cycle, or eight attempts stops safely. A three-second helper timeout and 45-second overall timeout bound the operation. Local is valid during a cycle. There is no attempt to restore tabs, focus or any other state after completion/failure.

Only one debug operation runs at once; another call is rejected. `WARP.stop()` and `WARP.reload()` cancel its owned timers/tasks, including reload calls that subsequently fail config validation. This debug helper creates no event taps. Do not start normal workflow switches or manually change Safari groups during the experiment.

Changed files for this experiment: `src/warp/safari_debug.lua` (new), `src/init.lua` (API/cleanup only), `tests/safari_debug.lua` (new), `tests/run.sh`, `tests/syntax.lua`, and this report. Existing local `config/workflows.lua` edits were preserved.

Validation: the full suite passes **25 Lua syntax checks**, **24 core tests**, **5 Finder-global tests**, **10 Safari debug logic/orchestration tests**, shell syntax and installer checks. Safari tests cover row parsing, selection/ambiguity, already-at-target, hops, repeated states, full cycles, the hop limit, read failure, concurrency and cancellation. These are pure/mock tests, **not proof of live Safari GUI automation**. No live Safari DB read or switching test was run by the agent.

Live test: reload WARP, ensure the intended Safari window is frontmost within Safari, then run in the Hammerspoon console:

```lua
WARP.debugSafariSwitch("SOFT2412")
```

Expected console progression (IDs/titles depend on actual state):

```text
[WARP][SAFARI-TEST] target=SOFT2412
[WARP][SAFARI-TEST] selected window_id=21
[WARP][SAFARI-TEST] start=ELEC3609 [id=46105]
[WARP][SAFARI-TEST] hop 1 -> Local [id=44997]
[WARP][SAFARI-TEST] hop 2 -> ELEC2602 [id=46152]
[WARP][SAFARI-TEST] hop 3 -> SOFT2412 [id=...]
[WARP][SAFARI-TEST] SUCCESS target reached
```

Alternatively expect `SUCCESS target already active` or an explicit `ABORT` reason. The immediate Lua return indicates acceptance of the asynchronous request, not successful group selection. `WARP.debugSafariSwitch("ELEC3609")` runs the reverse experiment once the first operation finishes. Live verification remains required.

## Dynamic VS Code membership (current local implementation)

VS Code (`Code`, `com.microsoft.VSCode`) now opts in with `vscode = true` or `{}`. Membership is additive and sticky, keyed by process ID plus real runtime window ID; neither titles nor folders are authority. The old root matcher, title-marker parser and CLI project reconstruction were removed. `allowedRoots`, `openRoots` and `cliPath` remain accepted only for migration, emit one warning per affected workflow and are discarded. Both current workflow entries now contain `vscode = true`; their existing Safari settings were preserved.

The VS Code adapter owns a private `hs.window.filter` subscribed to focus, unfocus and destruction events. Focus starts one chain of six `doAfter(10, ...)` checks if the active workflow does not already own that window. Every check verifies the focused window/app/process and active workflow. Unfocus, destruction, workflow switching or stop cancels immediately; a failed check also cancels. Partial time never accumulates. Successful qualification adds an owner without removing any others. An idle adapter has no qualification timer or polling loop. Start and settled workflow activation also inspect focus once so an already-focused window can qualify without requiring an artificial focus change. No typing/keystroke surveillance is used: sustained focus is the activity proxy.

Checkpoint enumerates existing Code windows but does not treat enumeration absence as closure. Stored window handles retain hidden/minimized/off-Space windows. A destruction event, invalid window ID or changed runtime process/window identity supplies closure/replacement evidence; uncertain AX access preserves membership. Cleanup removes only the checkpointed workflow's membership and saved runtime layout. Destruction marks the old identity unusable immediately for discovery/restore; other owners are pruned at their checkpoints. Observed ID reuse requires fresh qualification, drops old memberships, and avoids restoring an old layout to the replacement.

The manager's outgoing warm set excludes Code windows also owned by the destination. Source-only windows retain generic warm behavior; destination windows use the existing capture/restore helpers. No launch, folder reopen, editor closure, new fullscreen algorithm or new Space policy was added. With zero learned windows, the adapter succeeds without doing anything.

Membership tables stay in the adapter, never JSON. Runtime Code window layouts and Code Space entries are removed from the serialization copy without altering the live state or unrelated adapters' records. Version 1 state loading drops obsolete Code records before validating their old shape; other state remains supported. Reload creates a fresh adapter and relearns ownership; no cross-reload title/PID/window-ID matching is claimed. Existing Safari debug code and its tests are preserved. Manager stop cancels qualification, unsubscribes/pauses the private filter and clears runtime membership.

Files changed for this task:

- `src/warp/adapters/vscode.lua`: dynamic membership, events, checkpoint/restore, debug output.
- `src/warp/manager.lua`: start/stop/cancel integration, checkpoint cleanup and shared-window warm exclusion.
- `src/warp/ownership.lua`: removes obsolete VS Code root/title helpers.
- `src/warp/config.lua`, `src/warp/state.lua`: opt-in migration and runtime-only persistence.
- `src/init.lua`: adds `WARP.debugVSCodeOwnership()` alongside the existing Safari API.
- `config/workflows.lua`: adds the opt-in to both current workflows, preserving Safari config.
- `tests/vscode.lua`: deterministic event/timer, ownership, migration, restore and manager integration tests.
- `tests/unit.lua`, `tests/finder_global.lua`: replace obsolete fixed-root expectations and use Terminal records for unrelated state-preservation tests.
- `tests/run.sh`, `tests/syntax.lua`: include the new suite.
- `README.md`, this report: current setup and manual test instructions.

Validation: all **24 core**, **5 Finder-global**, **10 Safari debug**, and **14 dynamic VS Code** tests pass, with **26 Lua syntax checks**, shell syntax and installer checks. New tests cover qualification, failure at each check, focus/app/workflow changes, sticky and multi-owner membership, definitive/uncertain closure, replacement IDs, shared warm exclusion, source-only warm, destination restore, cleanup and obsolete config/state. Tests use mocks and deterministic timers; they do not establish live GUI compatibility. No live workflows were activated by the agent.

Limitations: ownership/layout must be relearned on reload. Continuous focus is the sole activity signal. Missed destruction events combined with stale-but-valid native handles may retain uncertain membership until closure can be established; missing enumeration alone will not disown a window. Current acceptance targets normal non-fullscreen windows. Generic existing fullscreen behavior remains unexpanded. Normal workflow Safari behavior and the separate Safari debug experiment are unchanged.

### Exact live test

1. Run `WARP.reload()` in the Hammerspoon console. Existing loader installation needs no changes. Ownership starts empty.
2. Run `WARP.switchTo("soft2412")`; wait for switching to finish. Manually focus your Code window 142 (use its current ID if macOS has recreated it) for more than 60 seconds. Expect `candidate`, `qualification 1/6` through `6/6`, then `ADOPT id=142 workflow=soft2412` under `[WARP][VSCODE]`.
3. Run `WARP.debugVSCodeOwnership()`. Expect `id=142 ... owners={soft2412}`. The function also returns a table. Opening the console changes focus but does not remove completed membership.
4. Briefly use Safari/Terminal, return to Code, and inspect again. Ownership remains; no new qualification is needed for an already-owned window. Changing editor tabs, folder/workspace title or minimizing must not remove it.
5. Run `WARP.switchTo("elec3609")`, wait for completion, then manually return to the same Code window and focus it continuously for more than 60 seconds. Inspect again: expect `owners={elec3609,soft2412}` (sorted order).
6. Switch both ways using `WARP.switchTo("soft2412")` and `WARP.switchTo("elec3609")`. Shared 142 must not minimize on departure. Other existing adapter behavior can still run because your Safari fields remain configured.
7. Under just one workflow, qualify a second normal Code window. Switching away should minimize that source-only window; switching back should restore it.
8. Close that second window manually when appropriate, then run `WARP.checkpoint()` while its owner is active, or switch away. Debug output should no longer list the closed window; the checkpoint removes its owner membership.
9. To test cancellation, focus an unowned window for 30 seconds, leave it, then return for 30 seconds. It must not adopt. A full new 60-second sequence is required. Stop/reload during qualification must leave no old checks firing.

Work remains local on `debug/safari-tab-groups`. Nothing was committed or pushed for this task.
