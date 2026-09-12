# WARP

**Your work context, one chord away.**

> Switching from one project to another? WARP automatically swaps your open apps, windows, tabs, files, terminals, and Spaces to match the new task — then restores everything when you switch back.

WARP is a lightweight macOS workflow manager built with Hammerspoon and Lua. A workflow describes a project’s Safari Tab Group, VS Code projects, tmux session, and supporting applications. Dynamic window layouts and Space mappings live separately from configuration.

**Status: conservative v1 implementation, awaiting live macOS acceptance testing.** The promise above describes the intended experience. Safari automation is conditional, VS Code requires a title marker, and cold cleanup currently preserves resources rather than claiming it can safely close them. Read the [implementation report](docs/implementation-report.md) for exact behavior, limitations, and staged tests.

## Use it

Hold **Control + Option + Command** to reveal the radial wheel. Press a configured **number** while holding the chord to switch. Release a modifier or press Escape to cancel. Existing letter shortcuts pass through unchanged and dismiss the overlay.

The wheel uses a translucent native Hammerspoon canvas. It supports up to ten workflows, one for each numeric key. It does not activate a web view or replace your existing Hammerspoon configuration.

**Control + Option + Right/Left** navigates only the active workflow’s registered Spaces. Shortcuts are configurable.

## Workflow lifecycle

| State | Behavior |
|---|---|
| ACTIVE | Owns the requested context. Individual restoration failures are reported without rejecting the workflow. |
| WARM | Normal owned windows minimize; native full-screen windows and tmux sessions remain alive. |
| COLD | After 30 minutes by default, safety policies run and metadata persists. This release retains all apps, containers, and terminal processes because safe destruction is not established. |

At most one workflow is ACTIVE. No workflow activates automatically on a fresh install. Pinning prevents automatic cold transitions. COLD does **not** currently promise reduced RAM usage.

## Requirements

- macOS with a working Hammerspoon installation and Accessibility permission. This implementation was checked against the locally installed Hammerspoon APIs; no minimum macOS version or compatibility matrix has been certified.
- Enable **Displays have separate Spaces** for the intended multi-monitor behavior. Space navigation uses Hammerspoon’s experimental Mission Control integration and can visibly animate.
- Allow Hammerspoon/its AppleScript helper to automate Terminal when macOS prompts.
- Safari with existing named Tab Groups; its sidebar should be visible for the default Accessibility strategy.
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
    vscode = {
      allowedRoots = {'~/Projects/Study'},
      openRoots = {'~/Projects/Study/project-a'}, -- optional initial projects
    },
    terminal = {tmuxSession = 'study', root = '~/Projects/Study'},
    apps = {{id = 'figma', preferredFullscreen = true}},
    primary = 'figma',
    coldAfterMinutes = 30,
  },
}
```

The shipped ELEC3609 and SOFT2412 entries are minimal selectors with `primary = 'none'` and no managed apps. Add the desired adapter fields and real paths when ready. Omit an adapter’s field to disable it. Supported workflow apps are `figma` and `docker`. Finder and ChatGPT are GLOBAL and entirely unmanaged.

Legacy `finder` settings are ignored with one warning per workflow per load; `primary = 'finder'` becomes `'none'`, skipping activation focus and Space navigation. Legacy Finder Space ordering and saved state are discarded. Set `terminal.root` explicitly if it previously inherited a Finder root; its default is now your home directory.

`config/settings.lua` controls persistence, notifications, and navigation:

```lua
return {
  stateDirectory = '~/.workflow-manager',
  navigation = {mods = {'ctrl', 'alt'}, next = 'right', previous = 'left'},
  notifications = true,
}
```

Set `navigation = false` to disable those hotkeys. Configuration is trusted local Lua data, loaded without `hs`, `os`, or `require`; do not put procedural workflow actions in it. Validation rejects unknown fields, duplicate numeric selectors, overlapping ownership roots across workflows, unsafe session names, and unsupported lifecycle policies. See the [complete schema](docs/implementation-report.md#configuration).

### VS Code setup

In **VS Code user settings**, set:

```json
"window.title": "[WARP:${rootPath}] ${dirty}${activeEditorShort}${separator}${appName}"
```

This exposes the actual workspace/folder path. WARP recognizes only this explicit marker, then checks it against `allowedRoots`. It does not infer a project from an editor tab or a folder basename. Multiple distinct project roots are supported. Unmarked windows and multiple windows exposing the same root remain unmanaged; use distinct workspaces when necessary. Remote/untitled workspaces and paths containing `]` are unsupported.

`openRoots` is optional: existing marked windows are discovered and saved dynamically. Reopening requires the VS Code CLI; set `vscode.cliPath` if installed in an unusual location. WARP lets VS Code handle editor tabs and internal state.

### Safari setup

Create your Tab Groups manually and show the sidebar. WARP looks for a unique matching accessible row outside web content, selects it, and verifies its selected state. If your Safari release exposes a useful menu, set an exact localized path, for example `menuPath = {'actual menu', 'actual submenu', 'Study'}` using names you have inspected. That is a schema illustration, not a claim those menus exist. No fictitious Safari Tab Group AppleScript API or guessed keyboard shortcut is used.

## What each adapter does

| Adapter | Implemented | Limits |
|---|---|---|
| Safari | Shared app; exact sidebar-row selection or configured menu path, then verification | Version/UI dependent. Hidden sidebar or ambiguous rows produce a partial failure. |
| VS Code | Full-path ownership, multiple distinct projects, warm minimize, reopen, normal/full-screen layout | Requires title marker; does not close editors automatically. |
| Terminal/tmux | Creates missing detached session, opens a dedicated viewer, reuses its title marker, records pane commands | Viewer title must remain reserved; detached/reused viewers are not reliably detectable. Sessions and processes always survive. |
| Figma | Exclusive workflow UI, warm minimize/full-screen retention, launch and layout restore | Relies on native document restoration; unknown duplicate titles are preserved. Shared Figma UI is unmanaged. |
| Docker | Exclusive Desktop UI restoration/minimize; backend preserved | No container shutdown, engine quit, or resource reclamation. Shared Desktop UI is unmanaged. |

## Diagnostics and safe testing

In the Hammerspoon console:

```lua
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
