# WARP

**Your work context, one chord away.**

> Switching from one project to another? WARP automatically swaps your open apps, windows, tabs, files, terminals, and Spaces to match the new task — then restores everything when you switch back.

WARP is a lightweight macOS workflow manager built with Hammerspoon and Lua. A workflow describes a project’s Safari Tab Group, VS Code projects, tmux session, and supporting applications. Dynamic window layouts and Space mappings live separately from configuration.

**Status: conservative v1 implementation, awaiting live macOS acceptance testing.** The promise above describes the intended experience. Safari automation is conditional, VS Code membership is learned from sustained focus, and verified VS Code windows can gracefully close/reopen through the companion described below. Read the [implementation report](docs/implementation-report.md) for exact behavior, limitations, and staged tests.

## Use it

Hold **Control + Option + Command** to reveal the radial wheel. Press a configured **number** while holding the chord to switch. Release a modifier or press Escape to cancel. Existing letter shortcuts pass through unchanged and dismiss the overlay.

The wheel uses a translucent native Hammerspoon canvas. It supports up to ten workflows, one for each numeric key. It does not activate a web view or replace your existing Hammerspoon configuration.

**Control + Option + Right/Left** navigates only the active workflow’s registered Spaces. Shortcuts are configurable.

## Workflow lifecycle

| State | Behavior |
|---|---|
| ACTIVE | Owns the requested context. Individual restoration failures are reported without rejecting the workflow. |
| WARM | Normal Code windows not owned by the active target minimize, including unowned windows; shared target windows stay visible. |
| COLD | After 30 minutes by default, safety policies run and metadata persists. Verified exclusive Code windows may close gracefully with persisted restore intent. Shared, dirty, terminal-bearing or unverified windows remain alive. Other apps/processes retain their existing safety policies. |

At most one workflow is ACTIVE. No workflow activates automatically on a fresh install. Pinning prevents automatic cold transitions. COLD does **not** currently promise reduced RAM usage.

## Requirements

- macOS with a working Hammerspoon installation and Accessibility permission. This implementation was checked against the locally installed Hammerspoon APIs; no minimum macOS version or compatibility matrix has been certified.
- Enable **Displays have separate Spaces** for the intended multi-monitor behavior. Space navigation uses Hammerspoon’s experimental Mission Control integration and can visibly animate.
- Allow Hammerspoon/its AppleScript helper to automate Terminal when macOS prompts.
- Safari already running with existing native Tab Groups and an accessible toolbar picker. Sidebar visibility is irrelevant; normal switching does not need Safari database access.
- Optional VS Code, Terminal + tmux, Figma, Docker Desktop, according to your workflows.
- No Node service, Python daemon, database, Electron application, or additional resident WARP process.

## Installation

Clone or place the repository wherever you want. From its root:

```sh
bash install.sh
```

This displays your repository-specific loader and changes nothing. Future installations can append it safely:

```sh
bash install.sh --install-loader
```

The installer backs up an existing `init.lua`, appends a small loader, and avoids duplicate entries. It refuses to modify a symlinked init. It never replaces existing configuration. If you already have a working WARP `dofile(...)` loader, **keep it and skip installation**.

Edit `config/workflows.lua`, then reload Hammerspoon using its menu. Loading WARP itself does not launch apps or switch your desktop. The message **“WARP loaded”** confirms startup.

## Declarative configuration

`config/workflows.lua` returns a table keyed by stable, lowercase workflow IDs:

```lua
return {
  study = {
    label = 'Study', key = '1',
    safari = {tabGroup = 'Study'},
    vscode = true,
    terminal = {tmuxSession = 'study', root = '~/Projects/Study'},
    apps = {{id = 'figma', preferredFullscreen = true}},
    primary = 'figma',
    coldAfterMinutes = 30,
  },
}
```

The current ELEC3609 and SOFT2412 entries use `primary = 'none'`, Safari Tab Groups and dynamic VS Code membership. Add the desired adapter fields and real paths when ready. Omit other adapter fields to disable them. `vscode` opts into membership learning; target visibility still minimizes every non-owned Code window. Supported workflow apps are `figma` and `docker`. Finder and ChatGPT are GLOBAL and entirely unmanaged.

Legacy `finder` settings are ignored with one warning per workflow per load; `primary = 'finder'` becomes `'none'`, skipping activation focus and Space navigation. Legacy Finder Space ordering and saved state are discarded. Set `terminal.root` explicitly if it previously inherited a Finder root; its default is now your home directory.

`config/settings.lua` controls persistence, notifications, and navigation:

```lua
return {
  stateDirectory = '~/.workflow-manager',
  navigation = {mods = {'ctrl', 'alt'}, next = 'right', previous = 'left'},
  notifications = true,
}
```

Set `navigation = false` to disable those hotkeys. Configuration is trusted local Lua data, loaded without `hs`, `os`, or `require`; do not put procedural workflow actions in it. Validation rejects unknown fields, duplicate numeric selectors, unsafe session names, and unsupported lifecycle policies. See the [complete schema](docs/implementation-report.md#configuration).

### VS Code membership

Set `vscode = true` (or `{}`) in each participating workflow. Focus a Code window continuously for six 10-second checks while the workflow is active to add membership. No folders, title markers or CLI are required. Membership is additive: the same window can belong to several workflows. Focus loss, title/workspace changes and minimizing do not remove membership.

Every activation (including reselecting the active workflow) restores target-owned live windows and minimizes all other normal Code windows, even unowned ones. A user-closed window loses membership at checkpoint and is never resurrected. Missing enumeration alone is not proof of closure. Live runtime ownership is relearned after reload; explicit WARP COLD-close records survive.

For safe COLD reclamation, install the bundled companion once; it reads the actual VS Code workspace API, requiring no folder lists or title markers:

```sh
python3 extras/vscode-companion/package.py
"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" --install-extension /tmp/warp-companion-0.1.0.vsix
```

Reload existing Code windows after installing the companion, then reload WARP and qualify windows. The companion runs inside VS Code, uses filesystem events rather than an idle polling loop, and requires no npm service or network connection. WARP verifies its session against the focused native window using a fresh request nonce. Remote, untitled, untrusted or ambiguous workspaces remain uncloseable. Dirty editors/notebooks and any integrated terminals also prevent COLD closing. Without the companion, visibility and membership work, while COLD preserves Code windows.

Only confirmed WARP COLD closures can trigger CLI reopening. Folder and saved workspace descriptors are learned dynamically. Close/reopen intent is persisted before the action, and uncertain outcomes block automatic retry to avoid duplicates. A live corresponding verified window is reused. Normal geometry is restored after the recreated window is verified and rebound to its logical owners. `allowedRoots`, `openRoots` and `cliPath` are obsolete configuration and ignored with warnings.

Use `WARP.debugVSCodeOwnership()` for windows, owners, descriptors and logical COLD records. Qualification has no idle polling: focus events start a temporary sequence, cancelled on focus/workflow change or stop.

### Safari setup

Create native Tab Groups manually and keep the intended Safari window frontmost within Safari. Normal restore requires Safari already running. When Safari is in the background, WARP calls `hs.application.launchOrFocus("Safari")`; when already frontmost, it retains a 200 ms initial delay. Readiness polls every 50 ms with a fresh AX application element for up to two seconds, requiring both Safari foreground and its toolbar picker by `AXMenuButton` role and `TabGroupPickerButton` identifier (even with an empty description). The identifier supplies the current group; an empty value means `Local`. An already-active target succeeds without navigation. Legacy `menuPath` remains ignored with a warning.

WARP presses the picker, waits 120 ms, and reads its displayed group order beginning at `<N> Tabs` (Local), deduplicating entries and stopping before group-creation commands. After Escape and 80 ms, it sends the shortest Cmd+Shift+Down/Up route with 60 ms between hops; ties go forward. Verification starts 200 ms after the last hop and polls fresh picker identifiers every 50 ms for up to 750 ms. Missing UI/groups, focus loss, secure input, or verification mismatch reports failure while later adapters continue. No sidebar, database reads, tab reconstruction, or group mutation is involved.

`WARP.debugSafariSwitch()` retains the older, slower DB/keyboard experiment for explicit diagnostics only. That diagnostic needs readable `SafariTabs.db` (Full Disk Access on this Mac); it does not test the production AX route. Starting a workflow switch, stopping, or reloading cancels diagnostics.

## What each adapter does

| Adapter | Implemented | Limits |
|---|---|---|
| Safari | Toolbar AX order/current state, shortest keyboard route, bounded AX verification | Safari must be running; accessible picker and unambiguous group names required. Intended window must be frontmost within Safari. |
| VS Code | Additive focus membership, target visibility and verified COLD close/reopen | Companion required for descriptors; unsafe windows preserved. Non-target fullscreen windows are reported rather than forcibly migrated. |
| Terminal/tmux | Creates missing detached session, opens a dedicated viewer, reuses its title marker, records pane commands | Viewer title must remain reserved; detached/reused viewers are not reliably detectable. Sessions and processes always survive. |
| Figma | Exclusive workflow UI, warm minimize/full-screen retention, launch and layout restore | Relies on native document restoration; unknown duplicate titles are preserved. Shared Figma UI is unmanaged. |
| Docker | Exclusive Desktop UI restoration/minimize; backend preserved | No container shutdown, engine quit, or resource reclamation. Shared Desktop UI is unmanaged. |

## Diagnostics and safe testing

In the Hammerspoon console:

```lua
WARP.debugSafariSwitch("SOFT2412") -- explicit legacy DB diagnostic; not the production AX route
WARP.debugVSCodeOwnership()       -- runtime window IDs, titles and workflow owners
WARP.status()                     -- copied config/state, errors, permission status
hs.inspect(WARP.status())         -- readable diagnostic output
WARP.previewWheel(true)           -- number selection logs only; no workflow switch
WARP.previewWheel(false)          -- enable real selection after wheel tests
WARP.switchTo('soft2412')
WARP.checkpoint()
WARP.pin('soft2412')
WARP.unpin('soft2412')
WARP.makeCold('soft2412')          -- only an inactive, unpinned WARM workflow
WARP.nextSpace()
WARP.previousSpace()
WARP.reload()                     -- validate config, stop owned resources, reload
WARP.stop()                       -- stop WARP; does not close your applications
```

Run local tests without touching the live desktop:

```sh
bash tests/run.sh
```

Tests use Lua if available, otherwise a temporary C host linked to Hammerspoon’s bundled Lua (requires Apple command-line developer tools). They check syntax, pure logic, mocked asynchronous GUI behavior, persistence, and installer preservation. They do not establish live GUI compatibility. Follow the [manual acceptance plan](docs/implementation-report.md#manual-acceptance) starting with the wheel alone.

Finder is untouched throughout activation, checkpoint, WARM, COLD and reload. WARP has no Finder discovery, AppleScript, role assignment, window mutation, saved layout, primary focus, or Space registration. `WARP.debugFinder()` has been removed.

Logs use `[WARP][INFO|WARN|ERROR]` in the Hammerspoon console. State is a versioned JSON file at `~/.workflow-manager/state.json`, written using a same-directory temporary file and rename. Runtime IDs are discarded on reload; invalid state is preserved and disables further persistence until repaired. State is not encrypted. Back it up if project metadata matters.

## Architecture and safety

`src/init.lua` derives the repository location from itself. The manager coordinates independent adapters through a request context that owns timers and helper tasks. Screens, windows, ownership, Spaces, state, and lifecycle logic each have their own module.

A newer request cancels older WARP timers/helpers and invalidates callbacks. Already-delivered macOS launch or Accessibility commands cannot be recalled; a late OS activation remains a documented race. WARP does not force-quit, click Discard, close unsaved documents, kill shells, or stop containers. Normal window layouts are learned at checkpoints instead of continually enforced.

Native full-screen windows are tracked by their current Space, not moved into an old saved Space. Display migration exits full-screen only when an available saved display differs, moves the normal window, re-enters full-screen, and discovers the new Space. Missing displays fall back to an available display. Some windows may remain undiscoverable until their Space has been visited after a reload.

The [architecture document](docs/workflow-manager.md) defines Finder as GLOBAL. The [implementation report](docs/implementation-report.md) documents actual behavior and deviations; design goals are not claims of completed platform support.
