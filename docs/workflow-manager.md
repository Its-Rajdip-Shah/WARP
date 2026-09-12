<!-- Current Finder policy: GLOBAL/unmanaged. Other platform goals remain subject to the implementation report. -->

# macOS Workflow Manager — Final Concrete Implementation Plan

**Status:** Finalized v1 design  
**Target machine:** MacBook Air M3, 16 GB RAM  
**Primary goal:** Switch between task workflows such as `SOFT2412`, `ELEC3609`, and `GIT_CLEANUP` in roughly 10–15 seconds, while preserving useful state, avoiding visual clutter, and not keeping every workflow fully active in RAM/CPU.

---

# 1. Final decisions locked in

These choices are now part of the v1 design.

## Terminal / tmux
- Keep tmux sessions alive even when a workflow becomes COLD.
- Do **not** kill idle shells just for the sake of freeing resources.
- Heavy child processes inside tmux are treated separately.
- v1 prioritizes safe continuation over aggressive terminal cleanup.

## Window layouts
- The manager learns the latest manual window position/layout.
- If the user moves or resizes a managed window during a workflow, that becomes the saved layout for the next restore.

## Meaning of COLD
- COLD is **resource-aware**, not absolute.
- A workflow may be called COLD even if protected processes remain alive.
- COLD means: everything that is safe and worthwhile to shut down has been shut down.

## ChatGPT
- ChatGPT is GLOBAL in v1.
- The workflow manager does not move it, hide it, reopen it, or switch projects/conversations.
- User switches ChatGPT project/thread manually.

## Finder

Finder is GLOBAL and entirely unmanaged. Its windows, directories, tabs, layout, focus and Spaces remain under manual control. No Finder adapter or workflow ownership exists.

## Full-screen / Spaces
- Native macOS full-screen is part of the design.
- The manager must work with Spaces rather than avoiding them.
- Full-screen apps are allowed and expected.
- Because native full-screen windows become their own Spaces, the manager tracks those Spaces instead of trying to force full-screen windows into arbitrary existing Spaces.

---

# 2. What the system actually is

This is a **workflow context manager**.

It is not just:

```text
open Safari
open VS Code
```

It manages:

```text
workflow
├── app/window membership
├── Safari context
├── VS Code project windows
├── terminal sessions
├── Docker state
├── Figma state
├── macOS Spaces
├── full-screen state
├── window layout
├── warm/cold lifecycle
└── restore behavior
```

The core promise is:

> The Mac should reshape itself around the task instead of making the user hunt around the Mac for the task.

---

# 3. Final workflow model

At any moment:

```text
one workflow = ACTIVE
zero or more = WARM
zero or more = COLD
```

Example:

```text
SOFT2412      WARM
ELEC3609      ACTIVE
GIT_CLEANUP   COLD
```

The manager always knows:

```text
active_workflow
last_active_time
state
owned windows
shared app state
Space locations
full-screen windows
saved layouts
protected processes
```

---

# 4. The three lifecycle states

## ACTIVE

The workflow currently being used.

Properties:

- its Safari Tab Group is active;
- its VS Code windows are available;
- its terminal/tmux state is available;
- workflow-specific apps are available;
- relevant full-screen Spaces are registered;
- switching between its windows/Spaces should require no manual hunting.

---

## WARM

Recently left workflow.

Goal:

> Preserve state and make returning very fast.

Properties:

- tmux remains alive;
- workflow-specific apps may remain open;
- workflow-specific normal windows are minimized/hidden where useful;
- workflow-specific full-screen windows may remain in their own Spaces;
- heavy services may continue temporarily;
- Safari Tab Group remains stored but inactive;
- VS Code project windows remain recoverable;
- all Space/window identity information remains registered.

Important:

> WARM does not mean "visible in the current working context."

A warm workflow can have Spaces that still technically exist in Mission Control, but the workflow manager knows their IDs and navigates directly to the active workflow's Spaces. The user should not need to search for them manually.

---

## COLD

Workflow has been unused long enough that safe resource cleanup occurs.

Properties:

- expensive workflow-only services may be stopped;
- Docker may be stopped/partially stopped where safe;
- workflow-only apps may be quit where safe;
- tmux remains alive in v1;
- VS Code state is persisted using VS Code's own state restoration;
- full-screen Spaces belonging to closed apps may disappear naturally;
- metadata remains saved so the workflow can be reconstructed.

COLD does **not** mean:

```text
literally zero process survives
```

It means:

```text
everything safely reclaimable has been reclaimed
```

---

# 5. Recommended timing

Initial v1 default:

```text
ACTIVE → WARM
immediately on workflow switch

WARM → COLD
30 minutes after last workflow use
```

This is configurable per workflow.

Example:

```yaml
SOFT2412:
  cold_after_minutes: 30

ELEC3609:
  cold_after_minutes: 30

GIT_CLEANUP:
  cold_after_minutes: 20
```

---

# 6. Main implementation stack

## Hammerspoon

Hammerspoon is the main orchestrator.

Responsibilities:

- global hotkeys;
- workflow picker;
- window discovery;
- window minimize/unminimize;
- full-screen detection;
- toggling full-screen;
- Space discovery;
- Space navigation;
- Space/window mapping;
- screen detection;
- window frame tracking;
- activity timers;
- calling shell commands;
- calling AppleScript/accessibility automation where necessary;
- maintaining workflow state.

---

## tmux

tmux holds terminal state.

Terminal.app is treated as the GUI.

Example sessions:

```text
soft2412
elec3609
git-cleanup
```

Each tmux session may contain several windows/panes.

Example:

```text
soft2412
├── shell: ~/Uni/SOFT2412
├── shell: ~/Uni/SOFT2412/project-a
└── shell: ~/Uni/SOFT2412/project-b
```

The tmux session stays alive even after Terminal.app becomes invisible.

---

## VS Code native persistence

VS Code manages its own deep editor state.

The workflow manager stores:

```text
which workspace/folder windows existed
which workflow owns them
whether they were full-screen
which Space they belonged to
latest normal-window frame
```

It does **not** manually serialize:

```text
open tabs
cursor position
split editor arrangement
sidebar expansion
```

VS Code itself handles those.

---

## Safari Tab Groups

Each workflow gets one Safari Tab Group.

Example:

```text
SOFT2412
ELEC3609
GIT CLEANUP
```

Safari stays one shared application.

Switching workflows changes Safari's internal context.

---

## Finder

Finder is GLOBAL and entirely unmanaged. Its windows, directories, tabs, layout, focus and Spaces remain under manual control. No Finder adapter or workflow ownership exists.

---

# 7. Important macOS Spaces reality

macOS treats a native full-screen app as its own Space.

Therefore the workflow manager must distinguish between:

```text
USER DESKTOP SPACE
FULL-SCREEN APP SPACE
```

This matters because full-screen windows cannot simply be moved between arbitrary Spaces the way normal floating windows can.

So v1 uses this rule:

> Normal windows can be moved/repositioned.  
> Full-screen windows are tracked by the Space macOS created for them.

The manager does **not** attempt to drag a full-screen window into some arbitrary desktop Space.

Instead it remembers:

```text
window
→ workflow
→ full-screen = true
→ current Space ID
→ screen
```

---

# 8. Space strategy

We use Spaces as actual workflow navigation units.

But we do **not** create a permanent named desktop Space for every workflow.

Instead, workflows may contain:

```text
one normal desktop context
+
zero or more full-screen app Spaces
```

Example SOFT2412:

```text
Desktop Space
└── supporting windows

Full-screen Space
└── VS Code project-a

Full-screen Space
└── Docker Desktop, if user chooses full-screen

Full-screen Space
└── Terminal, if user chooses full-screen
```

Example ELEC3609:

```text
Desktop Space
└── supporting windows

Full-screen Space
└── Figma

Full-screen Space
└── VS Code project

Full-screen Space
└── Safari, if desired
```

---

# 9. Why old warm Spaces are acceptable

A warm workflow may still have full-screen Spaces in Mission Control.

This is not considered a failure.

The problem we are solving is not:

```text
Mission Control must visually contain only one workflow
```

The problem is:

```text
the user should never have to hunt through Mission Control
```

Therefore:

- the manager tracks the active workflow's Spaces;
- switching workflows navigates directly to the target workflow's first/primary Space;
- subsequent workflow navigation can cycle only through Spaces registered to that workflow.

Example:

```text
SOFT2412 Spaces:
S4, S5, S6

ELEC3609 Spaces:
S8, S9
```

When ELEC is active:

```text
workflow next-space
```

cycles:

```text
S8 → S9 → S8
```

It does **not** cycle through SOFT Spaces.

This is a key part of the design.

---

# 10. Workflow-local Space navigation

The manager exposes shortcuts such as:

```text
⌥Space → choose workflow

⌥→ → next Space in current workflow
⌥← → previous Space in current workflow
```

Example:

```text
ELEC3609 registered Spaces:
1. desktop/reference
2. Figma
3. VS Code
```

Then:

```text
⌥→
```

moves only:

```text
desktop → Figma → VS Code → desktop
```

Old SOFT Spaces are ignored.

This makes native full-screen practical without manual Space hunting.

---

# 11. Workflow structure

Each workflow contains:

```text
workflow metadata
shared-app context
owned app/window definitions
dynamic window state
Space registry
terminal session
resource policy
layout state
lifecycle state
```

Example:

```yaml
ELEC3609:

  safari:
    tab_group: "ELEC3609"

  vscode:
    allowed_roots:
      - "~/Uni/ELEC3609"

  terminal:
    tmux_session: "elec3609"

  apps:
    Figma:
      ownership: workflow
      preferred_fullscreen: true

  lifecycle:
    cold_after_minutes: 30
```

---

# 12. Global state

Some things belong to no workflow.

Example:

```yaml
global:

  apps:
    ChatGPT:
      ownership: global

  windows:
    music:
      ownership: global
```

The workflow manager must never accidentally hide/quit a GLOBAL app just because a workflow changes.

---

# 13. State directory

Use:

```text
~/.workflow-manager/
```

Structure:

```text
~/.workflow-manager/
├── config/
│   ├── workflows.yaml
│   └── global.yaml
├── state/
│   ├── SOFT2412.json
│   ├── ELEC3609.json
│   └── GIT_CLEANUP.json
├── logs/
│   └── manager.log
└── scripts/
```

No database is needed.

---

# 14. Persistent workflow state

Example saved state:

```json
{
  "name": "SOFT2412",
  "state": "warm",
  "last_active": "2026-09-12T13:45:00+10:00",


  "safari": {
    "tab_group": "SOFT2412"
  },

  "vscode": [
    {
      "root": "/Users/me/Uni/SOFT2412/project-a",
      "fullscreen": true,
      "space_id": 74,
      "screen_uuid": "..."
    },
    {
      "root": "/Users/me/Uni/SOFT2412/project-b",
      "fullscreen": false,
      "frame": {
        "x": 0,
        "y": 0,
        "w": 0.7,
        "h": 1.0
      }
    }
  ],

  "terminal": {
    "tmux_session": "soft2412"
  }
}
```

Space IDs are treated as **runtime state**, not permanent identifiers.

If an app/window dies and macOS destroys the Space, the next restore discovers the new Space ID and updates the state.

---

# 15. Dynamic ownership detection

The manager needs reliable ownership rules.

## VS Code

Ownership is path-based.

Example:

```text
workspace root starts with ~/Uni/SOFT2412
→ SOFT2412
```

```text
workspace root starts with ~/Uni/ELEC3609
→ ELEC3609
```

---

## Terminal

Ownership is tmux-session-based.

Example:

```text
tmux attach soft2412
→ SOFT2412
```

---

## Figma

Declared by workflow configuration.

Example:

```text
Figma → ELEC3609
```

If Figma later becomes relevant to another workflow, ownership becomes document/window-specific rather than app-wide.

---

## Docker

Declared as a workflow resource.

Example:

```text
Docker Desktop UI → SOFT2412
```

Docker backend may be shared by several workflows.

Therefore UI ownership and backend ownership are separate.

---

## Safari

Shared.

Its Tab Group determines context.

---

## Finder

Finder is GLOBAL and entirely unmanaged. Its windows, directories, tabs, layout, focus and Spaces remain under manual control. No Finder adapter or workflow ownership exists.

---

# 16. Finder global policy

Finder is GLOBAL, like ChatGPT. Activation, checkpoint, WARM, COLD, reload and shutdown perform no Finder operations. WARP does not enumerate or assign its windows, navigate directories, create or close windows, minimize, resize, move, restore, focus, or register Finder Spaces. There are no left/right roles or Downloads reset policy.

Legacy `finder` config is ignored with one deprecation warning per affected workflow per load. Legacy `primary = "finder"` becomes `primary = "none"`; this skips activation focus and Space navigation. Old `finder` space-order entries are removed. Other configured adapters continue normally. Explicit navigation hotkeys retain the general desktop registry behavior, independent of Finder.

---

# 17. Finder state migration

State version 1 remains supported. Loading drops `shared.finder`, Finder window records and Finder retention reasons. Workflow-local Finder fields are not copied. Runtime Space entries are rebuilt from managed windows and the general desktop; Finder windows supply no entries. Other workflow state remains intact. Normal atomic saves persist the cleaned state; corrupt unrelated data retains the existing preservation policy.

Set `terminal.root` explicitly if it previously relied on a Finder root; the default is now the home directory. Finder layout and directories are never checkpointed or restored.

---

# 18. Safari behavior

Safari remains shared.

Switch:

```text
SOFT2412 → ELEC3609
```

does:

```text
Safari stays open
↓
active Tab Group changes
↓
Safari now represents ELEC3609
```

If Safari is full-screen:

- its full-screen Space remains Safari's Space;
- switching Tab Groups does not require creating another Safari Space;
- Safari is effectively transformed in place from SOFT context to ELEC context.

This is ideal because one app/Space serves several workflows.

---

# 19. Safari Tab Group adapter

Implementation preference order:

1. use a reliable native Safari/Shortcuts action if available;
2. otherwise Accessibility/UI automation;
3. otherwise deterministic keyboard/menu automation.

The adapter exposes:

```lua
safari.activateTabGroup("ELEC3609")
```

Verification:

- after switching, query accessible UI or visible group label if possible;
- if verification fails, report degraded restore;
- never block the rest of the workflow switch.

---

# 20. VS Code behavior

VS Code may have multiple windows per workflow.

Example:

```text
SOFT2412:
- project-a
- project-b
```

The manager must discover these dynamically.

It does not assume:

```text
one workflow = one VS Code window
```

---

# 21. VS Code checkpoint

For each VS Code window:

store:

```text
workflow root/workspace path
full-screen true/false
screen
current Space ID if full-screen
normal frame if not full-screen
last-seen window title
runtime window ID
```

Runtime window ID is not trusted after restart.

Workspace path is the primary identity.

---

# 22. VS Code WARM behavior

If a VS Code window is normal:

```text
minimize/hide
```

If it is native full-screen:

```text
leave full-screen Space alive
register it as belonging to warm workflow
do not navigate user to it
```

This preserves exact state and gives fast resume.

The user does not manually encounter it because workflow-local Space navigation ignores Spaces from other workflows.

---

# 23. VS Code COLD behavior

If safe:

```text
close workflow-specific VS Code windows
```

VS Code's native persistence handles editor restoration.

If there is unsaved work or closing is unsafe:

```text
do NOT force close
leave preserved
mark:
cold_blocked = unsaved_work
```

---

# 24. VS Code cold restore

For each recorded root:

```bash
code --new-window "<root>"
```

Then:

```text
wait for matching VS Code window
```

If saved state says it should be normal:

```text
restore latest saved frame
```

If saved state says it should be full-screen:

```text
window:setFullScreen(true)
↓
wait for macOS to create full-screen Space
↓
discover new Space ID
↓
register it under workflow
```

Do not try to move the resulting full-screen window to an old Space ID.

The old Space may no longer exist.

---

# 25. Terminal behavior

Each workflow gets a tmux session.

Example:

```text
soft2412
elec3609
```

Terminal.app is merely the visible shell viewer.

---

# 26. Terminal WARM behavior

When leaving SOFT:

```text
tmux soft2412 remains alive
```

If Terminal's window is normal:

```text
minimize/hide it
```

If Terminal is full-screen:

```text
leave its full-screen Space alive
register that Space under SOFT2412
```

---

# 27. Terminal COLD behavior

v1:

```text
tmux remains alive
```

We do **not** destroy the session.

Why:

- idle shells are cheap;
- destroying them does not meaningfully solve heavy resource usage;
- live shell/process state is valuable.

Heavy processes are handled individually.

---

# 28. Heavy terminal child processes

Examples:

```text
npm dev
Python server
webpack
compiler
database
model training
```

v1 policy:

```text
do not auto-kill unknown terminal child processes
```

Instead:

- record their existence;
- allow workflow to become resource-aware COLD;
- optionally notify/log that retained child processes are still consuming resources.

Future v2 can add process policies.

---

# 29. Docker behavior

Docker has two separate things:

```text
Docker Desktop UI
Docker backend / containers
```

They are not the same lifecycle object.

---

# 30. Docker WARM

When leaving SOFT:

Docker Desktop window:

```text
normal → minimize
fullscreen → leave full-screen Space registered
```

Backend:

```text
unchanged
```

This makes warm return very fast.

---

# 31. Docker COLD

Inspect Docker resources.

Containers/services are classified:

```text
workflow-only
shared
protected
ephemeral
```

Example:

```yaml
docker:
  containers:

    soft-api:
      policy: stop_on_cold

    soft-db:
      policy: preserve

    shared-postgres:
      policy: shared
```

COLD behavior:

```text
stop_on_cold → stop
preserve → leave running
shared → leave running
```

Docker Desktop itself may only quit if nothing important still uses the Docker engine.

---

# 32. Figma behavior

Figma is initially ELEC3609-owned.

Warm:

```text
normal window → minimize
full-screen → leave full-screen Space alive
```

Cold:

```text
quit only if safe
```

Restore:

```text
launch if missing
restore/reopen document using Figma/native recent state
restore full-screen if last state was full-screen
register resulting Space
```

The manager does not attempt to reproduce internal Figma canvas state that Figma itself does not persist.

---

# 33. ChatGPT behavior

ChatGPT is completely global in v1.

The manager:

```text
does not move it
does not minimize it
does not restore it
does not switch project
does not switch thread
```

User handles ChatGPT manually.

This keeps the first version simple and avoids fragile UI automation.

---

# 34. Layout learning

Every checkpoint records the latest user layout.

For normal windows:

```text
x
y
width
height
screen
```

stored as normalized proportions of the screen.

Example:

```json
{
  "x": 0.0,
  "y": 0.0,
  "w": 0.63,
  "h": 1.0
}
```

This makes layout resilient to resolution changes.

---

# 35. Full-screen layout learning

Full-screen windows do not have meaningful normal frames while full-screen.

Store:

```text
fullscreen = true
screen UUID
current Space ID
workflow-local order
```

Also preserve the last known normal frame before entering full-screen.

This gives fallback behavior if full-screen restoration fails.

---

# 36. Workflow-local Space order

Because raw macOS Space order can shift when full-screen apps open/close, maintain a separate logical order.

Example:

```yaml
ELEC3609:

  space_order:
    - desktop
    - safari
    - figma
    - vscode-main
    - terminal
```

Runtime mapping:

```text
desktop      → Space 4
safari       → Space 7
figma        → Space 9
vscode-main  → Space 10
terminal     → Space 12
```

These IDs may change.

The logical names do not.

---

# 37. Switching between workflow Spaces

When the user invokes:

```text
next workflow Space
```

manager:

1. finds current logical workflow Space;
2. looks up the next logical entry;
3. resolves current runtime Space ID;
4. navigates directly to it.

This completely avoids:

```text
swipe swipe swipe
wait which one is SOFT
oh damn that's Git cleanup
swipe back
```

💀

---

# 38. Full-screen Space recreation

When a COLD app needs restoration:

Example Figma:

```text
launch Figma
↓
wait for Figma window
↓
restore document
↓
set full-screen = true
↓
macOS creates full-screen Space
↓
detect windowSpaces(window)
↓
record new Space ID
↓
add logical name "figma"
```

The manager never assumes the old full-screen Space survives a cold shutdown.

---

# 39. Desktop Space role

Every workflow has one logical desktop/reference Space.

This is where normal non-full-screen workflow windows may live.

Typical content:

```text
small utility windows
```

Rather than one permanent desktop Space per workflow, v1 can reuse the currently active user desktop and transform its shared windows.

If a workflow later needs a dedicated desktop Space, that can be configured.

---

# 40. Exact switch algorithm

Example:

```text
SOFT2412 → ELEC3609
```

---

## Phase 1 — Lock switching

Create:

```text
request_id = request_id + 1
switch_in_progress = true
target = ELEC3609
```

Any delayed action checks that its request ID is still current.

---

## Phase 2 — Checkpoint SOFT2412

Capture:

```text
VS Code windows
terminal/tmux association
Docker UI state
workflow-owned app state
full-screen flags
Space membership
latest normal frames
screen membership
```

Save atomically.

---

## Phase 3 — Safety check

Check:

```text
unsaved work
long-running protected jobs
active Docker work
downloads/builds
modal dialogs
```

Nothing destructive happens during ordinary ACTIVE → WARM transition.

---

## Phase 4 — SOFT becomes WARM

Normal SOFT-only windows:

```text
minimize/hide
```

Full-screen SOFT-only windows:

```text
leave alive in their full-screen Spaces
mark those Spaces as SOFT-only
```

tmux:

```text
leave alive
```

Docker backend:

```text
leave alive
```

---

## Phase 5 — Transform Safari

```text
Safari Tab Group
SOFT2412
↓
ELEC3609
```

If Safari is full-screen, it stays in its current full-screen Safari Space.

Its context changes in place.

---

## Phase 6 — Global apps

Leave Finder and ChatGPT untouched.

## Phase 7 — Restore ELEC warm windows

For every normal ELEC window:

```text
find
unminimize
restore frame
restore screen
```

For every ELEC full-screen window:

```text
confirm it still exists
confirm full-screen
discover its current Space
register Space
```

---

## Phase 8 — Restore missing/cold windows

For any expected window that does not exist:

```text
launch/reopen
```

Examples:

```text
VS Code root
Figma
Terminal
```

Then recreate full-screen state if required.

---

## Phase 9 — Rebuild ELEC Space registry

Discover:

```text
all runtime Space IDs
all full-screen workflow windows
desktop/reference Space
```

Map them to logical ELEC Space roles.

---

## Phase 10 — Navigate to ELEC primary Space

Each workflow defines:

```yaml
primary_space: figma
```

or:

```yaml
primary_space: vscode-main
```

Manager jumps directly there.

No manual left/right hunting.

---

## Phase 11 — Finish

```text
SOFT2412 = WARM
ELEC3609 = ACTIVE
switch_in_progress = false
```

Start SOFT cold timer.

---

# 41. Warm → cold algorithm

Every 60 seconds:

```text
check warm workflows
```

If:

```text
idle < threshold
```

do nothing.

If threshold exceeded:

1. checkpoint;
2. inspect protected/expensive resources;
3. stop configured workflow-only services;
4. close safe workflow-only normal windows;
5. close safe workflow-only full-screen app windows;
6. allow macOS to destroy their full-screen Spaces;
7. keep tmux alive;
8. update Space registry;
9. mark COLD.

---

# 42. Unsaved work rule

The manager must never automatically cause data loss.

Absolute rules:

```text
never click Don't Save
never click Discard
never force quit because cold timer fired
```

If closing produces a save prompt:

```text
abort closing that app/window
mark resource as retained
workflow may still become resource-aware COLD
```

---

# 43. Protected jobs

Some jobs must survive.

Examples:

```text
Docker build
large download
npm install
long test suite
compile
file transfer
```

The manager supports:

```text
PIN WORKFLOW
```

Pinned workflow:

```text
never auto-cold
```

until unpinned.

v1 also supports configuration-based protected resources.

---

# 44. Shared-resource rule

Before shutting down anything:

```text
does another workflow need this?
```

Example:

```text
Docker used by SOFT
Docker also used by ELEC
```

Then switching SOFT → ELEC:

```text
do not stop Docker backend
```

Only UI context/layout may change.

---

# 45. App crash recovery

Persistent identity must not rely on window IDs.

Use:

```text
application bundle ID
workspace path
document path
tmux session name
Safari Tab Group name
```

Window IDs and Space IDs are runtime hints.

If Figma crashes:

```text
stored window ID invalid
↓
adapter notices no matching window
↓
relaunch
↓
restore document
↓
restore full-screen
↓
discover new Space
```

---

# 46. Restore failure behavior

Each app adapter restores independently.

Example:

```text
Safari ✓
VS Code ✓
Terminal ✓
Figma ✗
```

ELEC still becomes active.

Display one concise notification:

```text
ELEC3609 ready — Figma restore failed
```

Log full details.

Never abort the entire workflow because one app failed.

---

# 47. Rapid workflow switching

Example:

```text
SOFT
↓
ELEC
↓ 1 second later
SOFT
```

Use request generation numbers:

```text
41 = ELEC
42 = SOFT
```

Every delayed restore operation from request 41 checks:

```text
41 == current_request?
```

If no:

```text
abort
```

This prevents Figma suddenly appearing after SOFT has already become active.

---

# 48. External monitor handling

Screen UUIDs are stored.

Example:

```text
MSI monitor
MacBook display
```

If external monitor exists:

```text
restore normal layout on saved screen
```

If missing:

```text
fallback to built-in display
```

Full-screen restore:

```text
create full-screen on best available target display
```

When monitor reconnects:

- do not violently rearrange everything immediately;
- on next workflow activation/checkpoint cycle, restore preferred display placement.

---

# 49. Separate Spaces per display

For multi-monitor use, enable:

```text
Displays have separate Spaces
```

The manager then tracks:

```text
Space ID
+
display UUID
```

A workflow Space registry is display-aware.

Example:

```text
ELEC:
Figma → external monitor Space
Safari → built-in display Space
```

---

# 50. Full-screen caveat handling

Hammerspoon can detect/toggle full-screen.

However moving native full-screen windows directly between Spaces is restricted.

Therefore the rule is:

```text
normal window:
move it

full-screen window:
track its Space
```

If full-screen window must move to another display:

1. exit full-screen;
2. move normal window to target display;
3. re-enter full-screen;
4. detect newly created Space;
5. update registry.

This is slower but deterministic.

Only do this when display placement actually needs to change.

---

# 51. Workflow definitions

Example final config:

```yaml
workflows:

  SOFT2412:

    safari:
      tab_group: "SOFT2412"

    vscode:
      allowed_roots:
        - "~/Uni/SOFT2412"

    terminal:
      tmux_session: "soft2412"

    resources:

      Docker:
        type: workflow_specific
        warm: preserve
        cold: resource_aware

    primary_space: vscode-main

    cold_after_minutes: 30


  ELEC3609:

    safari:
      tab_group: "ELEC3609"

    vscode:
      allowed_roots:
        - "~/Uni/ELEC3609"

    terminal:
      tmux_session: "elec3609"

    resources:

      Figma:
        type: workflow_specific
        preferred_fullscreen: true

    primary_space: figma

    cold_after_minutes: 30
```

---

# 52. Global config

```yaml
global:

  apps:

    ChatGPT:
      policy: untouched

  terminal:
    keep_tmux_on_cold: true

  lifecycle:
    cold_mode: resource_aware

  layout:
    learn_latest_positions: true
```

---

# 53. Hammerspoon module structure

```text
~/.hammerspoon/
├── init.lua
└── workflow/
    ├── manager.lua
    ├── state.lua
    ├── spaces.lua
    ├── windows.lua
    ├── lifecycle.lua
    ├── ownership.lua
    ├── screens.lua
    ├── ui.lua
    └── adapters/
        ├── safari.lua
        ├── vscode.lua
        ├── terminal.lua
        ├── docker.lua
        └── figma.lua
```

---

# 54. `manager.lua`

Responsible for:

```text
switchTo()
checkpoint()
restore()
makeWarm()
makeCold()
pin()
unpin()
```

State:

```text
active workflow
switch request ID
switch lock
workflow state map
```

---

# 55. `spaces.lua`

Responsible for:

```text
discover Spaces
discover window → Space
register workflow Spaces
logical Space ordering
goto workflow Space
next workflow Space
previous workflow Space
rebuild runtime mapping
```

Important:

```text
Space IDs are runtime-only
```

Never hard-code:

```text
ELEC Figma = Space 9 forever
```

---

# 56. `windows.lua`

Responsible for:

```text
discover app windows
identify normal/full-screen
minimize
unminimize
capture frame
restore frame
toggle full-screen
move normal windows
screen fallback
```

---

# 57. `state.lua`

Stores workflow JSON.

Writes atomically:

```text
state.tmp
↓
rename
↓
state.json
```

So a crash cannot leave corrupted half-written state.

---

# 58. `lifecycle.lua`

Tracks:

```text
ACTIVE
WARM
COLD
PINNED
```

Runs lightweight check:

```text
once per minute
```

No high-frequency polling.

---

# 59. `ownership.lua`

Determines:

```text
which workflow owns this window/resource?
```

Rules:

```text
VS Code → workspace path
Terminal → tmux session
Figma → config/document
Docker UI → config
Safari → shared
Finder → GLOBAL / untouched
ChatGPT → global
```

---

# 60. `screens.lua`

Handles:

```text
screen UUIDs
monitor presence
preferred display
fallback display
display reconnect
```

---

# 61. Adapter contract

Every adapter implements:

```lua
checkpoint(workflow)
warm(workflow)
cold(workflow)
restore(workflow)
verify(workflow)
```

Not every app needs all methods.

---

# 62. User controls

Primary:

```text
⌥Space
```

opens workflow chooser:

```text
● ELEC3609
  SOFT2412
  Git Cleanup
```

---

# 63. Workflow Space controls

Example:

```text
⌥→
next Space belonging to active workflow

⌥←
previous Space belonging to active workflow
```

This is extremely important because native full-screen remains enabled.

It replaces blind macOS-wide Space swiping.

---

# 64. Optional direct workflow hotkeys

Example:

```text
⌥1 → SOFT2412
⌥2 → ELEC3609
⌥3 → GIT_CLEANUP
```

---

# 65. Menu bar control

Small Hammerspoon menu:

```text
Workflow: ELEC3609
────────────────
Switch Workflow…
Next Workflow Space
Previous Workflow Space
Checkpoint Now
Pin Workflow
Make Cold Now
Reload Config
Open Logs
```

No heavy GUI.

---

# 66. Performance design

The automation itself must remain negligible.

Rules:

- no Electron workspace manager;
- no continuous screenshotting;
- no high-frequency polling;
- no background browser;
- no database server;
- no permanent Python process.

Hammerspoon remains resident.

Expensive scans happen only:

```text
on switch
on checkpoint
on monitor change
on full-screen state change
```

Lifecycle timer:

```text
once every 60 seconds
```

---

# 67. Expected resource impact

Workflow metadata:

```text
tiny JSON/YAML files
```

tmux itself:

```text
small
```

Hammerspoon:

```text
lightweight resident process
```

Main resource consumption remains:

```text
Safari
VS Code
Docker
Figma
development processes
```

The workflow manager's job is specifically to reduce unnecessary usage from those larger components.

---

# 68. V1 implementation order

Do not build everything simultaneously.

## Phase 1 — Core state engine

Implement:

```text
workflow config
state storage
ACTIVE/WARM/COLD
workflow chooser
logging
```

No app automation yet.

---

## Phase 2 — Global app exclusion

Verify Finder is excluded from discovery, ownership, checkpoint, restore, cleanup and focus.

## Phase 3 — Safari

Implement:

```text
workflow Tab Group switch
```

This validates shared application context switching.

---

## Phase 4 — Spaces/full-screen engine

Implement:

```text
Space discovery
full-screen window detection
window → Space mapping
workflow Space registry
next/previous workflow Space
```

This is the most important technical milestone.

---

## Phase 5 — VS Code

Implement:

```text
multiple window discovery
path ownership
warm preservation
cold reopen
full-screen reconstruction
```

---

## Phase 6 — tmux/Terminal

Implement:

```text
workflow tmux sessions
Terminal viewer restoration
full-screen registration
```

---

## Phase 7 — Figma

Implement ELEC-specific app behavior.

---

## Phase 8 — Docker

Implement:

```text
window behavior
backend/container policies
resource-aware cold
```

---

## Phase 9 — Lifecycle automation

Add:

```text
30-minute warm → cold
pinning
protected jobs
resource safety
```

---

# 69. First real test workflows

Only build:

```text
SOFT2412
ELEC3609
```

Do not add Git Cleanup until these work correctly.

---

# 70. SOFT2412 acceptance state

Example:

```text
Safari
→ SOFT2412 Tab Group

Finder
→ untouched/global

VS Code
→ project-a
→ project-b

Terminal
→ tmux soft2412

Docker
→ available

ChatGPT
→ untouched/global
```

---

# 71. ELEC3609 acceptance state

Example:

```text
Safari
→ ELEC3609 Tab Group

Finder
→ untouched/global

Figma
→ restored

VS Code
→ previous ELEC projects

Terminal
→ tmux elec3609

ChatGPT
→ untouched/global
```

---

# 72. Acceptance tests

## Test A — warm SOFT → ELEC

Expected:

```text
Safari switches group
Finder remains untouched/global
SOFT normal windows disappear
SOFT full-screen Spaces remain registered but ignored
ELEC windows restore
manager jumps directly to ELEC primary Space
```

---

## Test B — warm ELEC → SOFT

Expected:

```text
same in reverse
```

No manual Mission Control hunting.

---

## Test C — multiple VS Code windows

Open:

```text
SOFT project-a
SOFT project-b
```

Switch away/back.

Both return.

---

## Test D — full-screen VS Code

Make project-a full-screen.

Switch away/back.

Expected:

```text
Space remains registered
manager jumps directly to it
```

---

## Test E — cold full-screen recreation

Allow workflow to become cold and close safe app.

Return.

Expected:

```text
window reopens
full-screen reapplied
new Space discovered
registry updated
```

---

## Test F — tmux continuity

Run commands in two tmux panes.

Switch away for >30 min.

Return.

Expected:

```text
same tmux session
same shell state
same CWD
same live process state
```

unless process exited naturally.

---

## Test G — Finder non-interference

Manually arrange Finder windows and navigate to arbitrary directories. Switch workflows, checkpoint, make an inactive workflow COLD, and reload. Expect identical Finder directories, window count, geometry and fullscreen state; no Finder restore issues. Repeat with no Finder windows open: WARP creates none.

## Test H — unsaved VS Code file

Create unsaved work.

Workflow reaches cold threshold.

Expected:

```text
no data loss
window remains if needed
workflow still allowed resource-aware cold
```

---

## Test I — Docker build

Run Docker build.

Workflow becomes inactive.

Expected:

```text
ordinary warm switch succeeds
build is not killed
cold does not destructively stop protected operation
```

---

## Test J — rapid switch

```text
SOFT → ELEC → SOFT quickly
```

Newest target wins.

No delayed Figma/Space operation corrupts SOFT layout.

---

## Test K — monitor removal

Disconnect external monitor.

Switch workflow.

Expected:

```text
all required normal windows visible
full-screen windows created on available display
nothing stranded
```

---

# 73. Important technical limitation

Native full-screen introduces more complexity than ordinary windows.

Specifically:

- full-screen windows are Spaces;
- they cannot be moved between user Spaces like normal windows;
- their Space IDs can change after recreation;
- entering/exiting full-screen can take a moment;
- Mission Control/Accessibility automation has some unavoidable macOS animation/latency.

Therefore the system is built around:

```text
track
discover
navigate
re-register
```

not:

```text
force every full-screen window into a predetermined Space ID
```

This is the correct model for macOS.

---

# 74. Final user experience

User is in SOFT2412.

They press:

```text
⌥Space
ELEC3609
```

The manager:

```text
checkpoints SOFT
preserves tmux
warms SOFT
switches Safari group
changes restores ELEC apps
re-registers ELEC full-screen Spaces
restores normal layouts
jumps directly to ELEC primary Space
```

User starts working.

No:

```text
find Safari tabs
hunt for Figma
swipe five Spaces
open wrong VS Code project
re-find Terminal directory
```

---

# 75. Final mental model

```text
                    WORKFLOW MANAGER
                           │
       ┌───────────────────┼──────────────────┐
       │                   │                  │
   SOFT2412            ELEC3609          GIT_CLEANUP
      WARM               ACTIVE              COLD
       │                   │                  │
       │             context projected        │
       │                   │                  │
       └───────────────────┼──────────────────┘
                           │
                    CURRENT MAC
                           │
          ┌────────────────┼─────────────────┐
          │                │                 │
        Safari       GLOBAL apps         workflow apps
       ELEC group    (manual control)          │
                                              │
                                      workflow Space map
                                              │
                                  desktop / Figma / VS Code
```

The final invariants are:

> **Only one workflow controls the current context.**

> **Warm preserves state.**

> **Cold reclaims whatever is safe to reclaim.**

> **tmux stays alive in v1.**

> **ChatGPT stays global in v1.**

> **Finder is GLOBAL. WARP never manages its windows, directories, layout, focus or Spaces.**

> **Full-screen windows are treated as Spaces and tracked instead of forcibly moved.**

> **The user navigates within the active workflow's Space set, not through every Space on the Mac.**

That is the final v1 implementation plan.
