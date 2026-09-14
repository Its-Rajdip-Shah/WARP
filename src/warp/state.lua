local U = require('warp.util')
local M = {}
local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end
function M.sanitize(raw, config)
  assert(type(raw) == 'table' and raw.version == 1 and type(raw.workflows) == 'table', 'unsupported/corrupt state schema')
  local data = {version=1,active=nil,workflows={},shared={}}
  if type(raw.shared)=='table' then data.shared=U.copy(raw.shared); data.shared.finder=nil end
  -- Only explicit WARP close/reopen intents survive; native runtime IDs never do.
  local cold=data.shared.vscodeCold; data.shared.vscodeCold={}
  if type(cold)=='table' then
    for id,r in pairs(cold) do
      if type(id)=='string' and type(r)=='table' and require('warp.vscode_bridge').valid(r.descriptor)
        and ({warp_cold_closed=true,close_requested=true,close_uncertain=true,reopen_pending=true})[r.state] and type(r.owners)=='table' then
        local owners={}; for owner,value in pairs(r.owners) do if value==true and config.workflows[owner] then owners[owner]=true end end
        local entry={state=r.state,owners=owners,descriptor=U.copy(r.descriptor)}
        if type(r.layout)=='table' then
          local layout=r.layout; local frame=layout.frame; local good=type(frame)=='table'
          if good then for _,axis in ipairs({'x','y','w','h'}) do if not finite(frame[axis]) then good=false end end end
          if good and frame.w>0 and frame.h>0 then entry.layout={frame=U.copy(frame),screenUUID=type(layout.screenUUID)=='string' and layout.screenUUID or nil,fullscreen=layout.fullscreen==true} end
        end
        if next(owners) then data.shared.vscodeCold[id]=entry end
      end
    end
  end
  for id in pairs(config.workflows) do
    local old = raw.workflows[id] or {}; assert(type(old) == 'table','invalid workflow state')
    local w = {lifecycle=old.lifecycle or 'COLD',lastActive=old.lastActive or 0,pinned=old.pinned == true,windows={},spaces={}}
    assert(w.lifecycle == 'ACTIVE' or w.lifecycle == 'WARM' or w.lifecycle == 'COLD', 'invalid lifecycle')
    assert(finite(w.lastActive), 'invalid timestamp')
    for key, record in pairs(old.windows or {}) do
      -- Discard obsolete records before validating their old shape.
      local finder=key=='finder' or (type(key)=='string' and key:match('^finder:')) or (type(record)=='table' and record.adapter=='finder')
      local vscode=key=='vscode' or (type(key)=='string' and key:match('^vscode:')) or (type(record)=='table' and record.adapter=='vscode')
      if not finder and not vscode then
        assert(type(key) == 'string' and type(record) == 'table' and type(record.adapter) == 'string' and type(record.identity) == 'string', 'invalid window record')
        assert(record.fullscreen == nil or type(record.fullscreen) == 'boolean', 'invalid fullscreen flag')
        if record.frame then
          for _, axis in ipairs({'x','y','w','h'}) do assert(finite(record.frame[axis]), 'invalid frame') end
          assert(record.frame.w > 0 and record.frame.h > 0,'invalid frame size')
        end
        -- Never trust a persisted runtime window/Space ID after a Lua reload.
        record = U.copy(record); record.windowID = nil; record.spaceIDs = nil; record.pid = nil
        w.windows[key] = record
      end
    end
    if w.lifecycle == 'ACTIVE' then w.lifecycle = 'WARM' end
    if type(old.terminalProcesses)=='table' then
      w.terminalProcesses={}
      for _,command in ipairs(old.terminalProcesses) do if type(command)=='string' then w.terminalProcesses[#w.terminalProcesses+1]=command end end
    end
    if type(old.retained)=='table' then
      w.retained={}; for adapter,reason in pairs(old.retained) do if adapter~='finder' and type(adapter)=='string' and type(reason)=='string' then w.retained[adapter]=reason end end
    end
    if type(old.safari)=='table' and type(old.safari.tabGroup)=='string' then w.safari={tabGroup=old.safari.tabGroup,verified=false} end
    data.workflows[id] = w
  end
  if type(raw.active) == 'string' and data.workflows[raw.active] then
    data.active = raw.active; data.workflows[raw.active].lifecycle = 'ACTIVE'
  end
  return data
end
-- Dynamic VS Code layouts/memberships are runtime-only, including Space hints.
function M.persistable(data)
  local copy=U.copy(data)
  for _,w in pairs(copy.workflows) do
    for key,r in pairs(w.windows) do if r.adapter=='vscode' then w.windows[key]=nil end end
    local spaces={}; for _,entry in ipairs(w.spaces or {}) do if entry.role~='vscode' then spaces[#spaces+1]=entry end end; w.spaces=spaces
  end
  return copy
end
function M.new(config)
  local self = {path=config.settings.stateDirectory .. '/state.json', writable=true}
  local raw = {version=1,workflows={}}
  if hs.fs.attributes(self.path) then
    local ok, result = pcall(hs.json.read,self.path)
    if ok and type(result) == 'table' then raw = result else self.writable=false; U.log('ERROR','State unreadable; preserving original, persistence disabled') end
  end
  local ok, data = pcall(M.sanitize,raw,config)
  if not ok then self.writable=false; U.log('ERROR','State schema invalid; persistence disabled: ' .. tostring(data)); data=M.sanitize({version=1,workflows={}},config) end
  self.data = data
  function self:save()
    if not self.writable then return false, 'persistence disabled to preserve invalid state' end
    local dir = config.settings.stateDirectory
    if not hs.fs.attributes(dir) then local made, err=hs.fs.mkdir(dir); if not made then U.log('ERROR','State directory: '..tostring(err)); return false,err end end
    local tmp = self.path .. '.tmp'
    local good, err = pcall(function()
      local encoded = hs.json.encode(M.persistable(self.data), true); assert(encoded,'JSON encoding failed')
      local f = assert(io.open(tmp,'w')); local written, why=f:write(encoded); local closed, closeErr=f:close()
      assert(written,why); assert(closed,closeErr); assert(os.rename(tmp,self.path))
    end)
    if not good then U.log('ERROR','State save failed: ' .. tostring(err)); return false,err end
    return true
  end
  return self
end
return M
