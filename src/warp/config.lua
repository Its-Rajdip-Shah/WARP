local U = require('warp.util')
local M = {}
local function keys(t, allowed, where)
  assert(type(t) == 'table', where .. ' must be a table')
  for k in pairs(t) do assert(allowed[k], where .. ': unsupported field ' .. tostring(k)) end
end
local function str(s) return type(s) == 'string' and #s > 0 and not s:find('[%c]') end
local function array(t, name)
  assert(type(t) == 'table', name .. ' must be an array')
  local n = 0; for k in pairs(t) do assert(type(k) == 'number' and k % 1 == 0 and k > 0, name .. ' must be an array'); n = n + 1 end
  assert(n == #t, name .. ' must be contiguous')
end
function M.validate(input, options)
  local ok, result = pcall(function()
    local workflows, list, selectors, roots, sessions = U.copy(input), {}, {}, {}, {}
    local warnings={}
    assert(type(workflows) == 'table', 'workflows must return a table')
    for id, w in pairs(workflows) do
      assert(type(id) == 'string' and id:match('^[a-z][a-z0-9_-]*$'), 'invalid workflow ID')
      keys(w, {label=true,key=true,finder=true,safari=true,terminal=true,vscode=true,apps=true,primary=true,coldAfterMinutes=true,spaceOrder=true,pinned=true}, id)
      assert(str(w.label) and #w.label <= 48, id .. ': label required (max 48 bytes)')
      assert(type(w.key) == 'string' and w.key:match('^[0-9]$'), id .. ': selector must be one numeric character')
      assert(not selectors[w.key], 'duplicate numeric selector ' .. w.key); selectors[w.key] = id
      w.id = id; w.coldAfterMinutes = w.coldAfterMinutes or 30
      assert(type(w.coldAfterMinutes) == 'number' and w.coldAfterMinutes > 0 and w.coldAfterMinutes < math.huge, 'invalid coldAfterMinutes')
      assert(w.pinned == nil or type(w.pinned) == 'boolean', 'pinned must be boolean')
      local deprecatedFinder=w.finder~=nil or w.primary=='finder'
      w.finder=nil -- Legacy values are ignored, including malformed old blocks.
      if w.primary=='finder' then w.primary='none' end
      if w.safari then
        keys(w.safari,{tabGroup=true,menuPath=true},'safari'); assert(str(w.safari.tabGroup), 'tabGroup required')
        if w.safari.menuPath then array(w.safari.menuPath,'menuPath'); assert(#w.safari.menuPath > 0, 'empty menuPath'); for _, v in ipairs(w.safari.menuPath) do assert(str(v),'invalid menuPath') end end
      end
      if w.terminal then
        keys(w.terminal,{tmuxSession=true,root=true,tmuxPath=true},'terminal')
        local s = w.terminal.tmuxSession
        assert(str(s) and s:match('^[a-zA-Z0-9_-]+$'), 'unsafe tmux session name')
        assert(not sessions[s], 'tmux session must have one workflow owner'); sessions[s] = id
        w.terminal.root = U.path(w.terminal.root or os.getenv('HOME'))
        if w.terminal.tmuxPath then w.terminal.tmuxPath = U.path(w.terminal.tmuxPath) end
      end
      if w.vscode then
        keys(w.vscode,{allowedRoots=true,openRoots=true,cliPath=true},'vscode')
        array(w.vscode.allowedRoots,'allowedRoots'); assert(#w.vscode.allowedRoots > 0, 'allowedRoots required')
        for i, p in ipairs(w.vscode.allowedRoots) do
          p = U.path(p); w.vscode.allowedRoots[i] = p
          for _, r in ipairs(roots) do assert(r.id == id or not (U.under(p,r.path) or U.under(r.path,p)), 'overlapping VS Code ownership roots') end
          roots[#roots+1] = {id=id,path=p}
        end
        w.vscode.openRoots = w.vscode.openRoots or {}; array(w.vscode.openRoots,'openRoots')
        for i, p in ipairs(w.vscode.openRoots) do
          p = U.path(p); local owned = false
          for _, root in ipairs(w.vscode.allowedRoots) do if U.under(p,root) then owned = true end end
          assert(owned,'openRoots must be under allowedRoots'); w.vscode.openRoots[i] = p
        end
        if w.vscode.cliPath then w.vscode.cliPath = U.path(w.vscode.cliPath) end
      end
      w.apps = w.apps or {}; array(w.apps,'apps'); local seen = {}
      for _, app in ipairs(w.apps) do
        keys(app,{id=true,name=true,preferredFullscreen=true,warm=true,cold=true},'app')
        assert(app.id == 'figma' or app.id == 'docker', 'v1 apps supports only figma and docker; global apps cannot be managed')
        assert(not seen[app.id], 'duplicate app ID'); seen[app.id] = true
        assert(app.name == nil or app.name == (app.id == 'figma' and 'Figma' or 'Docker'), 'app name must match adapter')
        assert(app.preferredFullscreen == nil or type(app.preferredFullscreen) == 'boolean', 'preferredFullscreen must be boolean')
        assert(app.warm == nil or app.warm == 'preserve', 'unsupported warm policy')
        assert(app.cold == nil or app.cold == 'preserve' or app.cold == 'resource_aware', 'unsupported cold policy')
      end
      w.primary = w.primary or 'desktop'
      assert(w.primary == 'none' or w.primary == 'desktop' or (w.primary == 'safari' and w.safari) or (w.primary == 'vscode' and w.vscode) or (w.primary == 'terminal' and w.terminal) or seen[w.primary], 'primary must reference a configured adapter, desktop, or none')
      w.spaceOrder = w.spaceOrder or {'desktop','safari','figma','vscode','terminal','docker'}
      array(w.spaceOrder,'spaceOrder'); local order = {}
      local spaceOrder={}
      for _, role in ipairs(w.spaceOrder) do
        if role=='finder' then deprecatedFinder=true else
          assert(({desktop=true,safari=true,figma=true,vscode=true,terminal=true,docker=true})[role] and not order[role], 'invalid/duplicate spaceOrder role')
          order[role]=true; spaceOrder[#spaceOrder+1]=role
        end
      end
      w.spaceOrder=spaceOrder
      if deprecatedFinder then warnings[#warnings+1]="workflow '"..id.."' contains deprecated finder config; Finder is global and the config is ignored (Finder primary becomes none)" end
      list[#list+1] = w
    end
    table.sort(list,function(a,b) return tonumber(a.key) < tonumber(b.key) end)
    local settings = U.copy(options or {})
    keys(settings,{stateDirectory=true,navigation=true,notifications=true},'settings')
    settings.stateDirectory = U.path(settings.stateDirectory or '~/.workflow-manager')
    assert(settings.notifications == nil or type(settings.notifications) == 'boolean', 'notifications must be boolean')
    if settings.navigation == nil then settings.navigation = {mods={'ctrl','alt'},next='right',previous='left'} end
    if settings.navigation ~= false then
      keys(settings.navigation,{mods=true,next=true,previous=true},'navigation'); array(settings.navigation.mods,'navigation.mods')
      local mods = {}; for _, m in ipairs(settings.navigation.mods) do assert(({ctrl=true,alt=true,cmd=true,shift=true})[m] and not mods[m], 'invalid navigation modifier'); mods[m] = true end
      assert(#settings.navigation.mods > 0 and str(settings.navigation.next) and str(settings.navigation.previous) and settings.navigation.next ~= settings.navigation.previous, 'invalid navigation keys')
      assert(not (mods.ctrl and mods.alt and mods.cmd), 'navigation must not use the wheel chord')
    end
    table.sort(warnings)
    return {workflows=workflows,list=list,selectors=selectors,settings=settings,warnings=warnings}
  end)
  if ok then return result end
  return nil, tostring(result)
end
function M.load(root)
  -- Empty environment enforces data-only configuration; no os/hs/require hooks.
  local function read(path)
    local chunk, err = loadfile(path,'t',{}); assert(chunk,err); return chunk()
  end
  local ok, data, settings = pcall(function()
    local opts = {}; if hs.fs.attributes(root .. '/config/settings.lua') then opts = read(root .. '/config/settings.lua') end
    return read(root .. '/config/workflows.lua'), opts
  end)
  if not ok then return nil, data end
  local config,err=M.validate(data, settings)
  if config then for _,warning in ipairs(config.warnings) do U.log('WARN',warning) end end
  return config,err
end
return M
