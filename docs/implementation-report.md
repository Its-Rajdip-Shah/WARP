# WARP v1 implementation report

Date: 12 September 2026. Audience: owner and engineering auditor.

This report describes the code in this repository, not every aspirational capability in the design. **Finder follow-up:** the owner subsequently reproduced duplicate-window creation on the live Mac. The targeted patch, diagnosis, and retest procedure are documented in section 19; the patched Finder behavior has mocked and compile-only verification, not a new live acceptance result. The original `docs/workflow-manager.md` was read and preserved. The user’s newer radial-wheel and repository-isolation requirements override that document’s older chooser and installation examples.

## 1. Executive summary

Implemented a repository-local Hammerspoon/Lua workflow manager with declarative validation, versioned JSON persistence, a native radial selector, independent adapters, request generation cancellation, ACTIVE/WARM/COLD lifecycle, pinning, normalized layouts, display fallback, native full-screen restoration, and workflow-local Space navigation. Added an append-only optional installer, README, and automated checks.

The implementation and automated checks completed successfully. No dependency installation, live app switching, Hammerspoon reload, container action, or modification of the owner’s Hammerspoon init was performed. There was no Lua executable on PATH; tests ran successfully using a temporary C executable linked against the installed Hammerspoon LuaSkin framework. That is a development test host, not a deployed WARP component.

What is established by testing: Lua syntax/module imports, configuration invariants, path ownership, persistence failure protection, timer cancellation, mocked wheel behavior, mocked display/full-screen transitions, mocked partial adapter failure, lifecycle transitions, and installer preservation/idempotency.

What is **not** established: live Safari AX compatibility, AppleScript permission prompts/window identity matching, actual Space navigation, cross-Space discovery completeness, full-screen animation timing, or application-native document restore. These require the staged manual tests below.

Deliberate incomplete features:

- COLD records conservative retention; it does not close apps, reclaim Docker resources, or promise memory savings.
- Safari requires an accessible exact sidebar row or a user-supplied actual menu path. It can fail independently.
- VS Code requires an explicit full-path title marker. No guessed ownership or deep editor serialization.
- Figma document reopening relies on the application’s own restoration. Multiple ambiguous app documents are not reconstructed.
- OS commands already delivered cannot be rolled back by a newer generation. WARP cancels its own pending work, but a late native launch can still appear.

## 2. File-by-file changes

All paths below are repository-relative. The initial config/state/wheel files and installer were empty; manager/init contained only the bootstrap.

| File | Change, purpose, important entry points |
|---|---|
| `.gitignore` | New; excludes `.DS_Store`, temporary state files, and installer backup names. Existing `.DS_Store` was left alone. |
| `README.md` | New; user-facing installation, configuration, capabilities, limitations, diagnostics, and safety. |
| `config/workflows.lua` | Implemented; data-only example ELEC3609/SOFT2412 definitions, stable IDs and numeric keys. Contains no dynamic window state. |
| `config/settings.lua` | New; state directory, optional navigation shortcuts, notification setting. |
| `install.sh` | Implemented; derives root, defaults to print-only mode, optional backup plus append, duplicate-loader detection, symlink refusal. |
| `src/init.lua` | Replaced hardcoded root bootstrap; derives root from source file, validates config, stops prior WARP instance, clears only WARP require cache, exposes console API. |
| `src/warp/util.lua` | New; deep copy, lexical absolute-path normalization, ownership boundary helper, shell/AppleScript quoting, filesystem checks, logging/error containment. |
| `src/warp/config.lua` | Implemented; `load`, `validate`; config loaded in an empty environment, schema validation and deterministic wheel ordering. |
| `src/warp/state.lua` | Implemented; `sanitize`, `new`, store `save`; versioned recovery, one-active repair, runtime-ID invalidation, atomic replacement, corruption preservation. |
| `src/warp/request.lua` | New; `valid`, `guard`, `after`, `wait`, `task`, `script`, `cancel`; owns all switch timers and short-lived helpers. |
| `src/warp/ownership.lua` | New; fixed bundle IDs, VS Code path ownership, app-owner counting, `[WARP:…]` project identity extraction. |
| `src/warp/screens.lua` | New; UUID lookup, normalized frame capture, clamped frame restoration, display fallback. |
| `src/warp/windows.lua` | New; owned filter lifecycle, cross-Space/AX discovery, record capture, minimize, asynchronous normal/full-screen restore. |
| `src/warp/spaces.lua` | New; runtime registry rebuilding, deduplication, logical role ordering, primary and next/previous navigation. |
| `src/warp/wheel.lua` | Implemented; modifier detection, dynamic native canvas, temporary number/Escape tap, dismissal, test-only preview mode. |
| `src/warp/lifecycle.lua` | New; pure `due` rule and one 60-second timer. |
| `src/warp/manager.lua` | Implemented; discovery, checkpoint, switch coordination, errors, lifecycle, pinning, navigation, menu bar, diagnostics, start/stop cleanup. |
| `src/warp/adapters/finder.lua` | New; two runtime role IDs, window adoption/reuse, path navigation, shared layout learning. |
| `src/warp/adapters/safari.lua` | New; bounded AX row search excluding web content, optional exact menu selection, verification, shared Safari Space discovery. |
| `src/warp/adapters/vscode.lua` | New; explicit full-path discovery, distinct-root restoration, CLI reopen, cold retention reason. |
| `src/warp/adapters/terminal.lua` | New; exact tmux session lookup/create, pane-command diagnostics, dedicated Terminal viewer, layout restoration. |
| `src/warp/adapters/owned.lua` | New; substantive common Figma/Docker UI implementation, exclusive ownership, unique window titles, warm/native restore support, conservative retention. |
| `src/warp/adapters/figma.lua` | New thin factory selecting the shared UI implementation with Figma’s identity. Avoids duplicated lifecycle logic. |
| `src/warp/adapters/docker.lua` | New thin factory selecting Docker UI behavior; explicitly documents backend retention. |
| `tests/lua-runner.c` | New optional development-only embedded Lua host; executes Lua test scripts without loading GUI extensions. |
| `tests/run.sh` | New; discovers Lua or compiles temporary host, runs syntax/behavior/shell/installer checks, cleans test executable. |
| `tests/syntax.lua` | New; compiles all 24 Lua source/config/test files with `loadfile` without executing desktop operations. |
| `tests/unit.lua` | New; 25 named behavioral tests with mocked Hammerspoon interfaces and temporary-file persistence tests. Imports all adapter factories. |
| `tests/finder.lua` | Finder follow-up; 18 isolated regression tests exercising the actual adapter, parser, adoption, directory mutation generation, metadata, diagnostics, and primary-focus policy using fake Finder/AX data. |
| `tests/install.sh` | New; isolated temporary configuration checks for print-only mode, original-content preservation, backup, repeat-run idempotency, paths with spaces. |
| `docs/implementation-report.md` | New; this audit document, including actual implementation details and manual acceptance plan. |

`docs/workflow-manager.md` was not modified. No files in `~/.hammerspoon` were changed. No repository commits were created; the supplied directory had no `.git` directory.

## 3. Architecture

Data flow:

```text
existing Hammerspoon dofile loader
  → src/init.lua (derive root, validate, clean prior instance)
  → manager (store + independent adapter instances)
  → wheel / menu / console
  → switch request context (generation, timers, helpers)
  → checkpoint old → warm old → mark target ACTIVE
  → Safari → Finder → VS Code → Terminal → Figma → Docker
  → checkpoint target → rebuild live Space registry → primary navigation
```

The manager owns its state and adapter instances. `_G.WARP` is the only public global added. Modules use repository-local `require` paths. Window discovery has one private module-level filter, started/stopped with the manager and cleared during WARP reload. It does not change Hammerspoon’s shared/default filter.

Adapters implement `discover(workflow)` and `restore(workflow, state, request, done)`, with optional `checkpoint` and `cold`. The manager centralizes window capture and WARM minimization rather than duplicating those operations in every adapter. `done(false, reason)` degrades the restore while allowing the next adapter to proceed. An exception in a request callback is logged and advances the sequence.

No automatic restore occurs on startup. A persisted ACTIVE identity is loaded as metadata only; users explicitly select it to reapply the context. A first-time empty state has no active workflow until selection. At most one workflow can be ACTIVE.

## 4. Radial wheel

A resident `flagsChanged` event tap recognizes Control, Option, and Command together, with Shift absent. The wheel opens on the mouse’s display, falling back to the main display. It creates a fresh canvas sized to the available frame, capped at 620 points.

Each configured workflow occupies an equally spaced position around a circle; numeric sorting determines clockwise order starting at the top. Dark translucent backing, compact cards, bright number labels, and readable workflow labels are native `hs.canvas` elements. This is a radial arrangement of cards, not pointer-selectable pie wedges. There is no hover/pointer selection or brief highlight animation; selection dismisses immediately.

The canvas uses overlay level and `canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`, and `ignoresCycle` behaviors. It has no click callback and does not activate the app on click.

While visible, a second tap captures `keyDown` events:

- A configured numeric key with the chord held dismisses the canvas and invokes the manager.
- Escape dismisses with no action.
- Unconfigured keys, including letters, dismiss and return `false` so existing bindings continue receiving them.
- Modifier release dismisses without switching.

A latch prevents reappearance while the same chord remains held after selection/cancellation. Releasing the chord clears the latch. The key tap stops on dismissal; the flags tap must remain active to detect the next invocation. On stop, both taps stop and the canvas is deleted. Monitor changes dismiss the current canvas; the next chord recreates it using the new screen.

`WARP.previewWheel(true)` changes only wheel selection into a log message. Menu/console switches still act normally. Secure Input can prevent event capture; `WARP.status().secureInput` reports it. Event taps disabled by macOS may require WARP reload; there is no watchdog polling to restart them.

## 5. Workflow config schema

`config/workflows.lua` returns a map. Each map key must match `^[a-z][a-z0-9_-]*$`. It is the stable ID, independent of label and selector. Unknown fields are rejected.

```lua
return {
  example = {
    label = 'Example',                   -- required; 1–48 bytes, no control chars
    key = '1',                           -- required; unique single '0' through '9'
    finder = {leftRoot = '~/Projects/Example'},
    safari = {
      tabGroup = 'Example',
      -- Optional exact, inspected, localized menu hierarchy:
      -- menuPath = {'Actual menu', 'Actual submenu', 'Example'},
    },
    vscode = {
      allowedRoots = {'~/Projects/Example'}, -- required nonempty array if enabled
      openRoots = {'~/Projects/Example/a'},  -- optional seeds, default empty
      -- cliPath = '/absolute/path/to/code',
    },
    terminal = {
      tmuxSession = 'example',            -- [a-zA-Z0-9_-]+, exclusive owner
      root = '~/Projects/Example',        -- defaults to finder.leftRoot, then HOME
      -- tmuxPath = '/absolute/path/to/tmux',
    },
    apps = {
      {
        id = 'figma',                     -- only figma or docker
        name = 'Figma',                   -- optional; must match adapter
        preferredFullscreen = true,      -- optional boolean
        warm = 'preserve',                -- optional; only supported value
        cold = 'resource_aware',          -- optional; or 'preserve'
      },
    },
    primary = 'figma',                    -- defaults to desktop
    coldAfterMinutes = 30,                -- finite positive number
    pinned = false,                      -- optional config pin
    spaceOrder = {'desktop', 'safari', 'figma', 'vscode', 'terminal', 'docker'},
  },
}
```

All sections other than `label` and `key` are optional. `primary` must be `desktop` or a configured adapter (`finder`, `safari`, `vscode`, `terminal`, `figma`, `docker`). It addresses an adapter role, not a hardcoded Space or window. `spaceOrder` accepts a unique subset of these roles plus desktop; unlisted roles sort after listed roles. The logical desktop is always the first registry entry. The default order also includes Finder.

Paths accept `/absolute/...` and `~/...`; control characters and relative paths are rejected, `.`/`..` segments are normalized lexically. Filesystem existence is checked at adapter execution, not config validation. Roots belonging to different workflows must not overlap at directory boundaries. `openRoots` must lie under that workflow’s allowed roots. Symbolic links and case-folding are not canonicalized.

`apps` does not accept arbitrary bundle IDs or commands. ChatGPT cannot accidentally enter the managed set. If Figma or Docker is declared in multiple workflows, that UI is treated as shared and preserved, with a restore issue explaining the unsupported document ownership.

Settings schema:

```lua
return {
  stateDirectory = '~/.workflow-manager',
  navigation = {mods = {'ctrl', 'alt'}, next = 'right', previous = 'left'},
  notifications = true,
}
```

`navigation=false` disables bindings. Modifier names are `ctrl`, `alt`, `cmd`, `shift`, without duplicates. The three-modifier wheel chord is prohibited for navigation. Actual key names are checked against `hs.keycodes.map` at startup; invalid names log warnings. Notifications are enabled unless false. A custom state directory’s parent must already exist.

Config is executed in an empty Lua environment, which removes ordinary access to `hs`, `os`, `require`, and libraries. This is not a CPU sandbox: it does not prevent a deliberately infinite loop in trusted local Lua. Data-only configuration is a convention supported by schema validation. Lua silently overwrites duplicate literal map keys before validation; duplicate numeric selectors across distinct workflow IDs are rejected, but repeated literal workflow IDs cannot be detected after evaluation. Audit map keys when editing.

## 6. State storage

Default: `~/.workflow-manager/state.json`. The production directory is created lazily when saving. No production state was created during implementation/testing.

Structure:

```text
version = 1
active = workflow ID or nil
workflows[ID]
  lifecycle, lastActive (Unix seconds), pinned
  windows[adapter:stable identity]
    adapter, identity, title, fullscreen
    frame {x,y,w,h} normalized to usable screen frame
    screenUUID
    windowID, pid, spaceIDs (runtime hints)
  spaces[] {role, identity, id, screenUUID, windowID}
  retained[adapter] = conservative retention reason
  terminalProcesses[] = pane command names observed during restore
  safari = {tabGroup, verified}
shared.finder.left/right = latest normal role layout
```

The last known normal frame is preserved while a window is full-screen. Finder’s shared role frames are sanitized separately. Records for missing app windows remain to allow later reopening; there is no automatic history pruning or “forget root” command yet.

Saving encodes the whole state, writes and closes `state.json.tmp` in the same directory, and uses `os.rename` to replace the final file. Write/close/encode/rename errors are logged. Tests prove encoding failure preserves the prior file. This provides atomic visibility on normal local filesystems, not an `fsync` durability guarantee, locking, or multi-process writer support. WARP is intended as one Hammerspoon instance. Permissions follow the user’s umask; data is not encrypted and can contain project paths and window titles.

Reload validates schema and numeric frame values, restores stable metadata, and clears window IDs/PIDs/Space mappings. Shared Finder runtime IDs are also discarded. Safari verification resets to false. Multiple ACTIVE flags are demoted; only the valid persisted `active` field can restore ACTIVE. Removed workflow IDs are ignored.

Unreadable/unsupported/corrupt state is left untouched, an empty in-memory state is used, and persistence is disabled with an ERROR. To recover, first back up that file, repair it or move it aside yourself, then reload WARP. The implementation does not silently overwrite potentially recoverable user metadata.

## 7. Exact switch sequence

For `soft2412 → elec3609`:

1. Validate the target and Accessibility availability. Increment generation. Cancel prior switch timers and short-lived helpers.
2. Set `switching=true`; log source, target, and request number.
3. Discover/capture SOFT windows, normal frames, full-screen flags, screen UUIDs, project identities, and current Space hints. Capture shared Finder layout only from the active context. Save.
4. Mark SOFT WARM and record departure time. Minimize discovered SOFT-owned normal VS Code/Terminal/Figma/Docker windows. Leave full-screen windows and shared Finder/Safari alive.
5. Commit ELEC as the single ACTIVE ID immediately, before asynchronous work. Persist that identity. This intentional departure from “commit only at the end” lets a newer request checkpoint a partially restored ELEC context correctly.
6. Restore Safari context; independently log any selection/verification failure.
7. Enumerate Finder’s own windows, correlate optional Hammerspoon metadata, and reuse/adopt the left/right roles. Change left to ELEC and right to Downloads without applying any frame/screen setter to existing windows. Create only a genuinely missing role; only a created window may receive a saved layout.
8. Restore distinct discovered/saved/configured ELEC VS Code roots, launching missing roots via CLI and waiting for explicit path identity.
9. Check/create ELEC tmux session; record pane commands; reuse or create a dedicated Terminal viewer and restore its layout/full-screen state.
10. Restore Figma, including saved/preferred full-screen behavior. Run Docker’s adapter (a no-op if not configured for ELEC).
11. Each adapter completion yields through a zero-delay timer, allowing intervening newer switch requests. Adapter failures do not abort the sequence.
12. Checkpoint ELEC, rebuild its current Space registry, navigate to the primary adapter window’s actual Space, and focus that window. For Finder primary, focus a correlated existing LEFT role (RIGHT if LEFT lacks correlation) directly, without `gotoSpace`. Finder restore failure or unavailable correlation skips focus/navigation entirely. Other primary adapters retain their existing desktop fallback.
13. Set `switching=false`, save, cancel any residual request work, log completion/issue count, and optionally send one concise failure notification.

Selecting the active workflow again checkpoints and reapplies it without making it WARM. Unknown IDs and missing Accessibility permission do not alter the active state. An app launching as part of the switch may temporarily take focus before final navigation.

## 8. App adapter status

| Adapter | Implemented behavior | Limitations/fallback | Manual validation |
|---|---|---|---|
| Finder | Authoritative AppleScript enumeration, optional filter/application/AX correlation, active-desktop preference, leftmost/rightmost adoption, exact Finder-ID target mutation, layout-preserving reuse, guarded missing-role creation | IDs are separate namespaces; correlation requires unique title+geometry. Uncorrelated scriptable normal windows can still be reused. Saved frames apply only to a newly created window with an available Hammerspoon handle. Tabs and full-screen reconstruction remain limited; see section 19 | Two existing windows, 0/1-window fallback, extra window, active Space, reload, changed layout, failure with no Mission Control |
| Safari | Launch/focus shared Safari; bounded AX row search outside web content; exact unique title/value selection; optional exact menu path; verify AXSelected | Sidebar/UI/version/language dependent. No invented Tab Group AppleScript API. Missing/ambiguous row degrades safely. Default row lookup scans the application, so duplicate matching rows across Safari windows are ambiguous. Registry uses the main Safari window; multiwindow group association is limited | Show sidebar, switch both groups, close sidebar, duplicate group labels/windows, verify warning and continued Finder restore |
| VS Code | Parse `[WARP:absolute root]` title, verify allowed-root ownership, capture multiple distinct roots, minimize normal windows, preserve fullscreen, reopen recorded/seed roots via CLI | Required title configuration; default basename titles remain unmanaged. Same-root duplicate windows are preserved as ambiguous. No remote/untitled workspace support; `]` in path unsupported. No unsafe close. A failed root aborts remaining roots within this adapter, but later adapters continue | Two distinct roots and one unrelated root; missing CLI/root; user-closed saved root; fullscreen recreation; unsaved editor remains |
| Terminal/tmux | Exact `has-session -t =name`; create missing detached session with root; list pane command names; `do script` without a target creates a new viewer; custom title marker identifies it | tmux binary in common locations or explicit path. Existing arbitrary terminals are never commandeered. Reserved title assumes viewer still represents that session; user detach/reuse is not fully verifiable. Multiple same-session viewers are not modeled separately. Pane command names are observations, not a resource/safety classifier | Missing tmux/root, two sessions, pane/CWD continuity, viewer reuse, deliberate detach, running protected job |
| Figma | Exclusive app ownership, unique-title windows, normal minimize, fullscreen preservation, launch/native restore, single-saved/single-recreated layout fallback | No document API. Multiple missing documents cannot be explicitly reopened; duplicate titles remain unmanaged. Shared Figma UI is preserved and reported. COLD never quits | One document initially, fullscreen, normal warm restore, app manually quit after saving, document-native restore |
| Docker | Same exclusive UI layout/minimize handling; Desktop launch if missing | Desktop launch can itself start the engine, as a user-requested restoration side effect. No engine/container stop commands. No resource classification. Shared UI remains unmanaged. `resource_aware` currently records retention only | Test with backend already running, normal/fullscreen UI, active build/containers, COLD retention |

Figma/Docker windows already open without a record keep their current captured layout; preferredFullscreen applies on first adoption when requested. Saved fullscreen=false overrides a later preferredFullscreen=true because learned runtime state takes precedence.

## 9. Spaces and full-screen implementation

Window discovery combines a private `hs.window.filter` with application window enumeration and `hs.axuielement.applicationElement(app)` → `AXWindows` → `asHSWindow()`. The filter subscribes to creation/destruction events to maintain a cross-Space cache. Basic `app:allWindows()` alone is insufficient; that was caught and corrected during self-review.

Space APIs: `hs.spaces.windowSpaces`, `allSpaces`, `focusedSpace`, `spacesForScreen`, `spaceType`, `gotoSpace`. No IDs are hardcoded. No Spaces are created or destroyed by WARP. `gotoSpace` uses Hammerspoon’s Mission Control implementation; it initiates navigation, and success is not an end-to-end proof that macOS finished focusing the expected Space.

A registry rebuild uses current discovered windows only, filters IDs through current `allSpaces`, deduplicates physical Spaces, and associates role/identity/screen UUID. A desktop comes from a normal managed window’s user Space, then focused user Space, then an existing user Space on the main screen. Additional actual normal-window Spaces can be registered; WARP does not consolidate all normal windows onto one desktop or reserve a dedicated desktop per workflow.

Primary navigation resolves the live primary adapter window and its current Space, then focuses it. Finder is intentionally non-disruptive: it focuses a correlated LEFT/RIGHT role directly only after successful restore; failure or missing correlation does nothing. Other primary adapters retain the first-desktop fallback. Next/previous rebuild first, discard destroyed IDs, wrap within this workflow’s list, and never enumerate unrelated full-screen Spaces as navigation targets. Physical desktops and shared Safari can legitimately appear in more than one workflow’s registry. Another workflow’s exclusive full-screen windows do not.

Full-screen restoration uses `isFullScreen`, `setFullScreen`, and condition-based retries every 250 ms while restoring, for up to 12 seconds per wait. Entering full-screen is considered registered only after the window reports full-screen and one of its current Spaces has type `fullscreen`. No move-to-old-Space operation is attempted.

Display migration occurs only if the saved display still exists and differs from the window’s current display: exit fullscreen, wait, move normal window, re-enter, discover. If the saved display is missing, an existing fullscreen window stays on its current available display; a normal/recreated window falls back to main/primary. Normal frames are clamped to the available usable display bounds. Monitor changes invalidate registries and dismiss the wheel but do not rearrange the desktop.

Platform caveats: private/experimental APIs, Mission Control animation and Accessibility permissions, separate-Spaces settings, app-specific AX gaps, initial discovery of unvisited Spaces, Split View/Stage Manager behavior, and OS transitions already underway. These were not live-tested.

## 10. Lifecycle

`lifecycle.due` is pure: only WARM, unpinned workflows beyond their configured inactivity threshold qualify. One timer runs every 60 seconds and skips while switching. Runtime and config pins both block cold; `unpin` cannot override a config pin.

COLD checkpoints the workflow, runs each available conservative `cold` method, records retention reasons, saves, and changes the label to COLD. No app/window/container is closed. This satisfies data preservation but does **not** fulfill the architecture’s eventual resource-reclamation objective. Pin/unpin and explicit `makeCold(id)` are exposed; `makeCold` refuses ACTIVE, already COLD, pinned, unknown, or currently switching cases.

The inactivity clock starts when switching away. The implementation does not infer workflow inactivity from keyboard idleness while ACTIVE.

## 11. Safety

- No quit/force-quit, close-window, Discard/Don’t Save, container-stop, session-kill, or process-tree-kill operation exists in production adapters.
- WARM only minimizes positively owned standard normal windows. Full-screen windows are retained. Shared/global apps are excluded from warming.
- ChatGPT’s bundle is absent from managed identities and rejected by configurable app schema.
- Only fixed local helper executables are launched via `hs.task`; arguments are arrays. Terminal shell text and AppleScript strings are escaped separately. tmux names reject shell metacharacters.
- Helper timeout/cancellation sends termination only to WARP’s task object (osascript, CLI helper, short tmux command), not application PIDs or tmux sessions.
- Missing app/path/CLI and uncertain identity preserve existing work and produce errors. No attempt is made to close a modal dialog or determine “unsaved means safe” from a window title.
- Existing Hammerspoon config was not touched. The future installer defaults to no changes and never replaces an init file.

The system does change the desktop when explicitly selected: app activation, minimization, Finder navigation, full-screen toggling, and Space navigation. Run the staged tests on disposable/saved contexts first.

## 12. Performance

Idle WARP owns one modifier event tap, one 60-second lifecycle timer, one screen watcher, one private window-filter subscription set, two optional hotkeys, and a menu-bar item. The numeric key tap and canvas exist/operate only while the wheel is visible. A finite set of timer objects is owned by the active switch; all are stopped on cancellation/completion/stop.

Discovery occurs at checkpoints, restore waits, or navigation. AX Safari traversal is bounded to 700 visited queue nodes, depth 9, excludes AXWebArea, and examines row descendants up to depth 2. Accessibility calls themselves may still be slow. Each individual wait is bounded, but sequential projects/fullscreen transitions can take longer than the design’s 10–15 second target. No latency or RAM benchmark was performed.

There is no periodic screenshotting, browser, daemon, or high-frequency idle polling. The window filter uses Hammerspoon’s native event infrastructure and its own internal behavior. State writes happen at lifecycle/switch/checkpoint/pin/stop boundaries, not on every mouse movement. Logs go to the Hammerspoon console; no persistent rotating log file is implemented.

## 13. Error handling

Adapter discovery/checkpoint errors are caught and logged. Restore calls are wrapped in `xpcall`, and request timers/helpers run through generation-checked guards. Each restore adapter’s completion is protected against duplicate invocation. Individual restore failures accumulate in `WARP.status().errors`; one final notification reports the count unless disabled.

Generation checks cover every scheduled WARP callback. Cancelling detaches helper callbacks, terminates WARP’s helper processes, and stops timers. Completed requests also cancel residual work. Already-delivered native application launches, Apple Events, fullscreen transitions, or Mission Control actions cannot be recalled. This is a material rapid-switch limitation rather than a claim of transactional macOS control.

Startup validation fails before stopping an already running WARP instance. Direct WARP reload cleans its taps, canvas, timers, hotkeys, screen watcher, filter and menu. Explicit stop checkpoints a settled active workflow. A complete Hammerspoon runtime reload disposes native resources, but there is no replacement of the owner’s `hs.shutdownCallback`; users can checkpoint first to preserve their most recent manual layout.

## 14. Tests and checks performed

Command: `bash tests/run.sh`. Final result: all checks passed.

- Compiled 24 Lua files using the installed Hammerspoon Lua interpreter library.
- Imported all real adapter factories before installing test doubles; require paths resolved.
- Ran 25 named behavioral cases (including Finder-failure workflow continuation without Mission Control): config defaults/IDs/normalization; empty workflows; duplicate/non-numeric selectors/global app rejection; overlap/path/session/policy rejection; tmux-owner/chord rejection; path boundaries/marker identity; shell/AppleScript quoting; one-active recovery/runtime ID clearing; malformed schema/frames; corrupt-state no-write; lifecycle thresholds/pins; newest-generation timers; wait timeout cleanup; callback exception containment; screen clamp/fallback; exact wheel modifiers; workflow-only Space navigation; navigation disable; atomic save/failure preservation; helper cancellation/timeout; complete mocked wheel key/cancel/cleanup/dynamic-count behavior; fullscreen migration/new Space/no unnecessary retoggle; manager rapid switch/partial failure/ACTIVE-WARM-COLD/stop; repeated manager start/stop cleanup of taps, filter, watcher, hotkeys, menu, and timer.
- Ran 18 additional Finder regression tests, including all ten requested adoption/layout/reload/failure cases. Compiled the actual generated enumeration, reuse, and guarded-creation AppleScripts with the installed Finder dictionary; never executed those scripts. See section 19 for the initial sandbox-only compiler failure and successful rerun.
- `bash -n` passed for installer and test shell scripts.
- Installer tests preserved original contents, confirmed dry-run makes no changes, created one backup on append, avoided duplicate loader on a second run, and handled a configuration directory containing spaces.
- Reviewed locally installed Hammerspoon `docs.json` signatures for window discovery, filter behavior/cleanup, AX conversions, canvas behavior, timers, screen lookup, tasks, and Space APIs.
- Reviewed official upstream Hammerspoon documentation and VS Code source documentation for API limitations/title identity. Reference links below.
- Searched production code for destructive operations, timers/event taps/fullscreen transitions, IDs, and hardcoded owner paths. Production code has no owner username/path and no app/container/session kill operation.

Tests operate on fake Hammerspoon objects and temporary files only. They do not render a real canvas, deliver an Apple Event, exercise an actual app, or validate GUI output. No live workflow action was used as a test. Syntax success does not establish that every app exposes the required AX information.

## 15. Manual test plan

Keep the console open for `[WARP]` logs. Use saved or disposable projects, keep original config copies, and add adapters gradually. Each config edit must leave `primary` pointing to an enabled adapter or `desktop`. Reload using the Hammerspoon menu initially, then `WARP.reload()` as convenient. Do not use the installer on the owner’s already-bootstrapped machine.

| Step | Setup | Action | Expected result | Failure evidence |
|---|---|---|---|---|
| 1 — wheel only | Reload Hammerspoon, confirm “WARP loaded”, then run `WARP.previewWheel(true)` in console. Do not click workflow menu entries | Hold Control+Option+Command; release without a key. Repeat with Escape, then numbers 1/2. Finally try an existing letter launcher | Centered readable wheel; release/Escape cancel; numbers log preview only; letter launcher still works. No app workflow action | `Loaded 2 workflows`, `Wheel preview selected …`; inspect Accessibility/Secure Input in `WARP.status()` if absent |
| 2 — screen/wheel cleanup | Preview still enabled | Show on each monitor; disconnect a display while visible if convenient; repeat chord; run `WARP.reload()` twice, reenable preview each time | Correct next-screen sizing; no orphan canvas or duplicate handlers. Preview resets after reload | Any `[ERROR] wheel` or Startup trace; status loaded flag |
| 3 — engine selection only | Temporarily use two minimal entries `{label='Test A',key='1',primary='desktop'}` and corresponding Test B. No app fields. Reload; preview off | Select A, then B, then A | Exactly one ACTIVE, other WARM, desktop registry/fallback; no app automation. Space navigation may open Mission Control | `Switching … [request …]`, `ACTIVE; restore finished`, status lifecycle/Spaces |
| 4 — Finder | Add only real existing Finder roots to both entries; primary finder. Arrange two normal Finder windows left/right; keep extra windows recognizable | Switch A→B. Navigate right to another folder, resize both roles, switch A→B again | Left follows config root, right resets to Downloads, two roles reused, latest split learned, extras untouched | `finder restore` error/timeout; inspect `shared.finder` frames. Verify OS Automation prompt permitted |
| 5 — Safari | Add existing exact Tab Group names, show sidebar, keep primary finder | Switch both directions; then hide sidebar and repeat | Selected group changes if row supported; failure remains concise and Finder still changes | `safari restore`, `verification`, `sidebar row missing/ambiguous`; inspect `state.workflows[ID].safari` |
| 6 — normal owned windows | Configure VS Code user title marker and allowedRoots; open one distinct project under each workflow plus unrelated project; primary vscode | Resize/move A editor, switch to B and back | A normal editor minimizes; B restores; return learns A layout; unrelated editor untouched | `vscode restore`, checkpoint logs; state window identities/fullscreen/frame |
| 7 — native fullscreen | Make A’s marked editor full-screen, allow animation to finish | Switch B, then A | A full-screen Space survives WARM; switch back navigates directly; fullscreen flag and Space IDs reflect reality | `exit full-screen`/`full-screen Space registration` timeout, `Space navigation`; inspect registry |
| 8 — local Space navigation | Active workflow has desktop + marked fullscreen editor + another owned fullscreen app when available | Press Control+Option+Right repeatedly, then Left | Wrap through only current workflow’s registered physical Spaces. Shared desktop/Safari may be common; other workflow’s exclusive fullscreen Space excluded | `workflow Space navigation` or `no registered Spaces`; compare status registry with Mission Control |
| 9 — multiple VS Code projects | Open two **different** roots under A; set one normal, one fullscreen. Leave an unmarked/unrelated editor open | Switch A→B→A. Then save and manually close one A root; repeat | Both identified roots restore. Missing saved root reopens via CLI. Unmarked window unchanged | Missing CLI/root, title-marker timeout, ownership records. Same-root duplicates intentionally remain unmanaged |
| 10 — tmux | Install tmux yourself if missing; add distinct session names and real roots; Terminal settings must show the custom title | Switch A, create two panes and note CWD/variables/processes; switch B→A repeatedly | One reserved viewer reused; same session/panes/process state. No arbitrary existing shell receives commands | `tmux missing`, `missing terminal root`, `Terminal tmux viewer`, pane command metadata. If detached manually, inspect viewer association rather than trusting its old title |
| 11 — Figma | Add Figma to only one workflow; start with one saved document | Switch away/back normal, then fullscreen. Save and manually quit Figma, then return | UI returns; saved fullscreen reapplied; native document restore if Figma supports it. No auto quit | `figma restore`, window timeout, Space registration; verify actual document, not just app launch |
| 12 — Docker | Add Docker only to SOFT; preferably start Desktop/engine manually first. Use a harmless container/build you can inspect | Switch away; later make SOFT cold while inactive | UI minimizes if normal; build/containers/backend remain untouched | `docker restore`/retained metadata. Check Docker yourself; WARP never sends stop commands |
| 13 — warm round trip | Both workflows configured, with mixed normal/fullscreen windows, project roots, shared Finder/Safari | SOFT→ELEC→SOFT, inspect every component | Learned normal layouts, owned fullscreen navigation, tmux continuity, shared context updates | Per-adapter restore lines and final issue count; compare window identities and registry |
| 14 — pin/cold | Pin inactive workflow with `WARP.pin('soft2412')`; temporarily set `coldAfterMinutes=1` in config for timed test, or use explicit makeCold | With pin, wait over two minutes; unpin and wait, or call `WARP.makeCold('soft2412')` while WARM | Pin prevents cold; unpinned WARM becomes COLD; ACTIVE cannot. Unsaved editors and all processes remain. No RAM-reclamation expectation | `-> COLD (unproven-safe resources retained)`; retained reasons and lifecycle in status |
| 15 — cold restore/recreation | Keep a saved marked fullscreen VS Code root recorded, switch away, manually close it after saving, mark inactive workflow cold | Switch back | Saved root reopened; fullscreen reentered; **new** Space ID registered; tmux never destroyed | VS Code launch/path matching and full-screen registration logs; compare old/new hints |
| 16 — rapid switching | Saved contexts; make one app start slowly if naturally available; do not introduce destructive work | Select SOFT→ELEC→SOFT rapidly, including during fullscreen animation | Final ACTIVE is SOFT; old WARP callbacks stop and no old registry commit occurs. Observe/report any late native OS activation as known race | Request numbers, final ACTIVE, no older completion after latest; exact app/animation that appeared late |
| 17 — external display | Capture normal and fullscreen layouts on external display | Switch away, unplug external, restore; reconnect and repeat next activation | Normal windows clamped to available screen; existing fullscreen remains on available screen; saved available display migration uses exit/move/reenter. No immediate reconnect rearrangement | Screen UUID/frame fields, full-screen timeout, Space navigation errors |
| 18 — permissions/missing resources | Temporarily use a missing project directory or unavailable optional app (do not delete real data) | Switch to affected workflow | That adapter fails; remaining adapters continue and target stays ACTIVE | Named adapter error and one final issue notification |
| 19 — stop/reload/state | Run `WARP.checkpoint()`, inspect status; keep working documents saved | `WARP.stop()`, verify chord inactive; reload Hammerspoon | WARP controls are cleaned up; apps remain alive; reload restores stable metadata, clears runtime hints, performs no app restore until selected | Loaded line, persistenceEnabled, no duplicate callbacks; if invalid state is reported, back up before repair |

If a test fails, stop at that layer and leave later adapters disabled while diagnosing. Do not “fix” a verification failure by enabling destructive cleanup.

## 16. Known limitations and risks

1. **No live GUI certification.** The full acceptance flow remains to be exercised on the owner’s Mac.
2. **No resource reclamation yet.** COLD is a conservative lifecycle label with explicit retention reasons. No Docker classifier or safe-editor-close capability exists.
3. **OS-level cancellation gap.** Generation IDs prevent stale Lua work, not late launch/focus/fullscreen effects already handed to macOS.
4. **Safari AX fragility.** Sidebar visibility, exact names, duplicate rows, localization, window choice, and Safari updates can prevent reliable selection or verification.
5. **VS Code identity setup required.** The marker is a user-controlled protocol, not a native workspace API. A spoofed marker is trusted local metadata. Remote paths, `]`, duplicate same-root windows, symlinks/case variants, and omitted titles can remain unmanaged.
6. **Incomplete app document identity.** Figma/Docker use unique titles, with single-window layout fallback. They do not reconstruct missing collections of documents. Old title records may accumulate.
7. **Terminal marker can become stale.** Detaching tmux or reusing the viewer manually is not reliably detected; do not repurpose WARP’s reserved viewer title. Pane-command diagnostics are not a heavy-job resource audit.
8. **Finder roles are runtime assignments.** Re-adoption after reload prefers active-desktop normal windows, then chooses leftmost/rightmost. AppleScript IDs are authoritative for navigation, never substituted for Hammerspoon IDs. Optional correlation/focus and tabs/fullscreen behavior still need live validation. See section 19.
9. **Space API limits.** Mission Control may animate/fail; discovery after reload can miss unvisited Spaces; Split View and Stage Manager are not certified; normal windows are not consolidated onto one desktop.
10. **Checkpoint-based learning.** Manual layouts are saved on switch, explicit checkpoint, cold checkpoint, and settled explicit stop. A hard crash or full Hammerspoon reload can lose layout changes since the last checkpoint.
11. **Persistence scope.** One local writer; no locks, `fsync`, encryption, automatic corruption repair, migration beyond version 1, or record pruning.
12. **Configuration is trusted Lua.** Empty environment is not a execution-time sandbox; repeated literal IDs are collapsed by Lua before validation. Existing numeric shortcuts on the wheel chord will conflict by design; existing letter shortcuts pass through.
13. **Partial within-adapter recovery.** One failed VS Code root or app window can stop later restoration within that adapter. Other adapters continue.
14. **UI/documentation omissions versus design.** No automatic highlight animation, menu-based reload/log opener/make-cold items, persistent log file, dedicated desktop creation, process policy configuration, or container stop policies. Equivalent console functions cover reload/cold/checkpoint/pins.

## 17. Next recommended steps

1. Run the wheel-only and minimal two-workflow manual tests, then validate Finder IDs/permissions and Safari’s actual AX tree on the installed releases.
2. Certify cross-Space/fullscreen/window-filter behavior, particularly freshly reloaded Hammerspoon and external displays; add captured fixture-based adapter tests from observed AX structures.
3. Add a VS Code extension/IPC identity source and Terminal TTY↔tmux-client correlation to remove title-marker assumptions.
4. Add stronger app document identities, missing-document reopening, per-root failure isolation, and state-record pruning/forget commands.
5. Improve rapid-switch reconciliation after unavoidable late native launches/transitions; consider app/window event-driven reconciliation scoped strictly to proven owned windows.
6. Implement opt-in resource policies only with explicit ownership/protection evidence and safe app-specific dirty-state checks. Preserve tmux by default.
7. Add versioned state migrations, durable logging, optional shutdown checkpoint composition, actual performance measurements, and a tested macOS/Hammerspoon compatibility matrix.

## 18. Commands the owner needs to run

The existing loader already works. **Do not reinstall or rewrite it.**

From the WARP repository, optional repeatable checks:

```sh
bash tests/run.sh
```

Edit `config/workflows.lua` to real roots, initially reducing it to minimal workflows for the staged plan. Use the Hammerspoon menu’s **Reload Config**, then in its console:

```lua
WARP.previewWheel(true)
hs.inspect(WARP.status())
```

After wheel-only tests and staged configuration, enable actual wheel selection:

```lua
WARP.previewWheel(false)
```

Subsequent repository config/code edits can be loaded with `WARP.reload()`. Install tmux only if you choose the Terminal adapter and it is not already installed. No package manager command, migration, bootstrap edit, or deployment is otherwise required by this implementation.

### Reference material consulted

- [Hammerspoon Spaces documentation](https://www.hammerspoon.org/docs/hs.spaces.html): API names and experimental Mission Control/private API caveats.
- [Hammerspoon window documentation](https://www.hammerspoon.org/docs/hs.window.html) and [window filter documentation](https://www.hammerspoon.org/docs/hs.window.filter.html): cross-Space enumeration limits and filter scope.
- [Hammerspoon Accessibility documentation](https://www.hammerspoon.org/docs/hs.axuielement.html): AX querying, setting, actions and window conversion.
- [Hammerspoon task documentation](https://www.hammerspoon.org/docs/hs.task.html): argument arrays, callbacks, and helper lifecycle.
- [Hammerspoon canvas documentation](https://www.hammerspoon.org/docs/hs.canvas.html): overlay drawing and window behaviors.
- [VS Code upstream settings completion source](https://github.com/microsoft/vscode/blob/main/extensions/configuration-editing/src/settingsDocumentHelper.ts): `rootPath` title variable identity.

The installed `/Applications/Hammerspoon.app/Contents/Resources/docs.json` was also read directly. These references establish API contracts, not successful live execution on this machine.

## 19. Finder adoption fix after live testing

### Live bug and diagnosis

The owner reported that activating ELEC3609 created two new default-size Finder windows while two existing ordinary side-by-side Finder windows remained untouched. That is a failure of the intended adoption behavior, not an accepted fallback.

Inspection identified three concrete defects in the old implementation:

1. The creation decision depended entirely on `W.list('finder')`. Although that function combined a window filter, application enumeration, and AXWindows, all results still had to become standard `hs.window` objects. There was **no Finder AppleScript enumeration before creation**. An empty/incomplete Hammerspoon list was incorrectly interpreted as zero existing Finder windows. This directly explains how the duplicate-creation branch could run. The report of the live failure does not contain a source-by-source snapshot, so the particular API that omitted/rejected those original windows cannot be established retrospectively.
2. The old adapter stored `win:id()` as its role identifier, passed that number into `Finder window id …`, and passed a returned Finder ID into `hs.window.get(...)`. There is no API contract establishing interchangeable IDs. Even where IDs happen to match on a particular OS, relying on equality is incorrect. Navigation must use IDs returned by Finder; Hammerspoon IDs must remain separate metadata hints.
3. The old adapter called `screens.restore` on every existing normal role window, applying either saved frames or a default half-screen layout. Independently, `spaces.primary` could invoke `gotoSpace` on a synthetic fallback desktop after Finder failed. Both could disturb the user's desktop even after an unsuccessful restore.

The patch changes only Finder-specific discovery/adoption, the Finder-primary focus branch, the public diagnostic wiring, and relevant tests/documentation. Other adapters, config, installation behavior, lifecycle policy, and the architecture document are unchanged. `~/.hammerspoon/init.lua` was not edited.

### Files changed in this follow-up

| File | Targeted change |
|---|---|
| `src/warp/adapters/finder.lua` | Adds read-only Finder enumeration, a validated escaped record parser, unique optional AX/Hammerspoon correlation, pure adoption selection, separate Finder/HS role IDs, process-scoped runtime roles, exact target mutation, creation fencing, current-layout capture, and diagnostic output. |
| `src/warp/windows.lua` | Adds `finderEvidence()` without changing other adapters' `list()` path. Collects filter, application and AX evidence independently, labels sources, captures available geometry/Space IDs, and includes unconvertible AX elements for diagnostics. |
| `src/warp/spaces.lua` | Adds a Finder-only primary branch: successful direct role focus; no Mission Control fallback after failure or missing correlation. Existing non-Finder behavior is unchanged. |
| `src/warp/manager.lua` | Passes adapter success outcomes to primary selection. Owns/cancels the read-only Finder diagnostic request, including cleanup on stop/reload. |
| `src/init.lua` | Exposes `WARP.debugFinder()`; existing loader contract is unchanged. |
| `tests/finder.lua` | New isolated regression suite with a fake Finder Apple Event transport but the actual Finder adapter/parser/selection code. Records generated scripts for compile-only checks. |
| `tests/unit.lua` | Adds manager-level proof that a failed Finder restore still completes the workflow, runs subsequent adapters, and calls no `gotoSpace`. |
| `tests/syntax.lua`, `tests/run.sh` | Include the new suite and compile its actual generated AppleScript artifacts against the installed dictionary when `osacompile` is available. Compilation never runs the scripts. |
| `README.md`, `docs/implementation-report.md` | Correct Finder capability/limitation descriptions and document the diagnostic and retest plan. |

### Exact adoption and mutation algorithm

1. Validate both configured directories. Invalid roots fail the Finder adapter without changing any Finder window.
2. Run a read-only AppleScript enumeration of Finder's `every window`. Read its Finder ID, class, bounds, modal/floating/collapsed flags, and title. An escaped line protocol preserves titles containing tabs, newlines, percent signs and quotes. A scripting error or malformed response fails closed; it is never treated as an empty Finder desktop.
3. Independently collect Hammerspoon filter, `application:allWindows()`, and AX application-window evidence. A failing source or element does not prevent the other sources from contributing. Unconvertible AX elements remain diagnostic evidence.
4. Correlate Finder records to Hammerspoon evidence only for a unique one-to-one title-and-frame match, with a three-point per-coordinate tolerance. Numeric IDs and list order are never used as a cross-API identity mapping. Ambiguous matches do not acquire a guessed Hammerspoon handle.
5. Only ordinary Finder file-viewer records with positive bounds and no modal/floating/nonstandard/fullscreen evidence are adoptable. Desktop pseudo-windows and other scriptable window classes are excluded. Finder has no dictionary fullscreen property; without AX fullscreen information, a full-display rectangle is conservatively considered uncertain and not adopted.
6. Retain healthy role Finder IDs while the observed Finder process remains the same. After WARP/Hammerspoon reload or a detected Finder process change, start without trusted runtime roles and re-adopt.
7. Prefer candidates whose known Space IDs intersect `hs.spaces.activeSpaces()`. With at least two preferred candidates, use their leftmost/rightmost windows. With one preferred candidate, include it and an available other candidate, ordered by X. With no known active-space candidates, use the overall leftmost/rightmost suitable windows. Healthy assigned roles are not swapped when the user later changes their physical positions. Additional unselected windows are left untouched.
8. Record role identity, Finder ID, optional Hammerspoon ID, title, current bounds, process ID and available layout/display/Space hints in shared state. If no `hs.window` is available, bounds still provide layout evidence; normalized display layout is inferred from the screen with greatest geometric overlap. Runtime IDs are discarded by the existing state loader on reload.
9. For each existing selected role, address **`Finder window id <Finder-returned ID>`**, verify the file-viewer class, and set its `target` to the desired directory alias. Do not activate Finder, create/open a replacement, unminimize, move screen, set a frame, or move a Space as part of reuse. Existing window layout is the latest layout and is checkpointed.
10. Rescan before each role. If fewer than two usable windows exist, create only the missing role. Do not create if unexplained standard normal Hammerspoon windows remain unmatched. Immediately before creating, compare Finder's current complete ID set with the enumerated ID set; a changed set aborts creation and asks for a new switch instead of risking a duplicate. There is no close/recreate recovery branch.
11. After mutation, rescan for the returned Finder ID. No `hs.window.get(Finder ID)` wait is used. Apply a saved normalized layout **only to a newly created window with an available correlated Hammerspoon handle**. With no such handle, leave the new window's native placement alone; existing windows never receive a saved/default frame.
12. If Finder is primary and its restore succeeded, focus the correlated LEFT role directly (RIGHT if LEFT has no handle). Do not explicitly call `gotoSpace` for Finder. If restore failed, or both handles are unavailable, log that focus was skipped and leave navigation alone. The workflow still completes and later adapters still run.

The 0/1/2+ policy is explicit: zero usable windows creates LEFT and RIGHT; one adopts LEFT and creates RIGHT; two or more adopts existing roles and creates nothing. This assumes no healthy prior role assignments; an existing healthy RIGHT role is retained if LEFT later disappears.

### Read-only diagnostics

After reloading repository code, run in the Hammerspoon console:

```lua
WARP.debugFinder()
```

The function returns immediately and prints its asynchronous result under `[WARP][INFO] Finder diagnostics (read-only)`. It reports every enumerated/correlated window plus unmatched evidence, including:

- discovery sources (`window filter`, `application`, `AX`, `AppleScript`);
- title, bounds/frame, Finder ID and Hammerspoon ID separately;
- screen UUID and Space IDs when available;
- normal/fullscreen information, active-context preference, adoptability and rejection reason;
- proposed LEFT/RIGHT Finder IDs, or a conditional missing-role indication;
- source-specific errors and Finder process ID.

If AppleScript enumeration fails, the diagnostic still reports available Hammerspoon/AX evidence and the scripting error. It does not adopt roles, save state, change targets, create/focus windows, resize/move anything, or invoke Mission Control. It uses only a read-only helper task, which is cancelled on a repeat diagnostic or WARP stop/reload. macOS may request Automation permission when the AppleScript helper first queries Finder.

### Verification performed

Final complete command: `bash tests/run.sh`.

- **24 Lua files compile.**
- **25 core behavioral tests pass**, including manager-level Finder failure continuation with zero Mission Control calls.
- **18 Finder regression tests pass:** two existing/zero creations; one existing/one creation; zero existing/two creations; X extremes plus third-window preservation; active-desktop preference; repeated workflow switches preserving IDs and latest layout; reload/re-adoption with zero duplicates; stale saved frames ignored for existing windows; saved layout applied to reconstruction only; AppleScript-only discovery; enumeration failure without mutations; desktop/modal/floating/fullscreen exclusion; read-only diagnostics; escaped-title parsing/failure on malformed data; failed/uncorrelated primary without Mission Control; direct successful LEFT focus; independent AX evidence after application enumeration failure; ambiguous title/geometry never guessing HS identity.
- **Three generated AppleScript variants compile** against the installed Finder dictionary: read-only enumeration, existing-window target mutation, and guarded missing-window creation. No compiled script was executed.
- Shell syntax and all existing installer-preservation tests pass.

The initial compile-only run inside the restricted execution sandbox could not access macOS's scripting dictionary services and reported an XPC connection error plus a misleading parser error. Re-running the same checks with dictionary-service access succeeded. This was a test-environment limitation, not bypassed by executing scripts or mutating Finder. Test development also corrected a strict floating-point equality assertion and a mock expectation that wrongly assumed correlation would remain ambiguous after window titles changed.

No live Finder mutation, live workflow switch, or Hammerspoon configuration edit was performed by the agent. The fix is ready for a user-controlled live retest; passing mocks/compilation is not a claim of completed live acceptance.

### Remaining Finder/macOS limitations

- A source-by-source snapshot from the original failure is unavailable. The new diagnostic is intended to identify the exact discovery omission if any remains.
- If optional Hammerspoon/AX correlation is unavailable or ambiguous, existing scriptable normal windows can still be reused, but active-Space preference, primary focus, and reconstructed-window layout restoration may be unavailable. The adapter reports/skips navigation rather than guessing a Space.
- Without AX fullscreen information, full-display geometry is an uncertainty heuristic. A manually edge-to-edge normal window can be conservatively skipped. Finder tabs, minimized viewers, native fullscreen and unusual Finder configurations need live testing; no tab reorganization or fullscreen migration was added.
- AppleScript and AX snapshots are sequential observations, not an atomic desktop transaction. Creation is guarded against ID-set changes, but the user or macOS can still change windows during an already-delivered target mutation. The existing request-generation guards remain in force for WARP callbacks.
- Finder IDs are scoped to a running Finder process, not permanent document identities. The layout survives reload; roles are re-adopted by current context/geometry, not trusted from disk.
- In-place target mutation relies on Finder's own normal window navigation behavior. The adapter itself does not apply a layout setter to an existing window. If a particular Finder release changes geometry internally on target changes, capture that in the retest diagnostics rather than reintroducing unconditional frame forcing.

### Exact manual retest

Use the already-configured real ELEC3609/SOFT2412 roots. For the clearest test, use Finder-only workflows with `primary='finder'`, or temporarily omit other adapters while preserving the rest of the configuration in a copy. Keep your existing Hammerspoon loader.

1. **Baseline:** leave the two original normal side-by-side Finder windows open in the current desktop. Put each in an arbitrary directory. Run `WARP.reload()` and then `WARP.debugFinder()`. Expected: both appear as scriptable candidates; proposed LEFT/RIGHT follow X position; no window or layout changes. Save the output, especially Finder IDs, frame values, sources and Space hints.
2. **First activation:** run `WARP.switchTo('elec3609')`. Expected: the same LEFT ID now targets ELEC; the same RIGHT ID targets Downloads; no new windows, default-size windows, display changes or Mission Control animation. Logs must say `Finder left reused AppleScript ID …` and `Finder right reused AppleScript ID …`, not `created`.
3. **Round trip:** run `WARP.switchTo('soft2412')`, then `WARP.debugFinder()`. Expected: identical role Finder IDs and geometry; only LEFT's directory changes and RIGHT resets to Downloads. Compare baseline and post-switch output.
4. **Layout learning:** manually resize/move the existing windows into a different split. Run `WARP.checkpoint()`, switch back to ELEC, and inspect again. Expected: the new split stays exactly as arranged; no saved/default frame reset. Healthy role identity stays fixed even if you deliberately swap their X positions.
5. **Extra window:** open a third ordinary Finder window between the two in X position. Reload WARP, run diagnostics, then switch. Expected: leftmost/rightmost chosen in the preferred active desktop; the middle window's directory, bounds and identity stay untouched. No fourth/fifth window appears.
6. **Reload:** with the intended pair present, reload Hammerspoon or call `WARP.reload()` twice, then activate a workflow. Expected: runtime identities are re-adopted; existing windows reused, zero duplicates.
7. **One-window fallback:** manually close one intended Finder viewer when safe, leaving one suitable normal viewer. Reload WARP and switch. Expected: existing viewer becomes LEFT; exactly one new RIGHT window appears. If a saved right layout exists and its new window correlates to HS, that layout may be applied only to the created window.
8. **Zero-window fallback:** manually close ordinary Finder viewers when safe, reload, switch. Expected: exactly two new role windows. This is the only ordinary zero-window case that should log two `created` lines.
9. **Cross-Space preference:** put a distinguishable extra normal Finder window on another Space, keep two on the current desktop, reload, and run diagnostics before switching. Expected when Space metadata is available: current-desktop pair chosen; the other window remains untouched. If metadata is absent, inspect the reported limitation before allowing the switch.
10. **Failure path:** temporarily point one workflow's Finder root at a nonexistent directory while keeping `primary='finder'`, reload, then select it. Expected: one Finder restore error, workflow still ACTIVE, no new windows, no focus/Space jump and no Mission Control fallback. Restore the real root afterward. Inspect `Finder primary focus skipped: restore failed` and `WARP.status().errors`.

If the two-window test still fails, provide the **before-switch** `WARP.debugFinder()` output plus the `[WARP]` switch logs. Do not compensate by closing/recreating the original windows or repeatedly running installation.
