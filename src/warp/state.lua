local U = require('warp.util')
local M = {}
local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end
function M.sanitize(raw, config)
  assert(type(raw) == 'table' and raw.version == 1 and type(raw.workflows) == 'table', 'unsupported/corrupt state schema')
  local data = {version=1,active=nil,workflows={},shared={}}
  if type(raw.shared) == 'table' and type(raw.shared.finder) == 'table' then
    data.shared.finder={}
    for _,role in ipairs({'left','right'}) do
      local r=raw.shared.finder[role]
      if type(r)=='table' and type(r.frame)=='table' then
        local good=true
        for _,axis in ipairs({'x','y','w','h'}) do if not finite(r.frame[axis]) then good=false end end
        if good and r.frame.w>0 and r.frame.h>0 then
          data.shared.finder[role]={frame=U.copy(r.frame),screenUUID=type(r.screenUUID)=='string' and r.screenUUID or nil}
        end
      end
    end
  end
  for id in pairs(config.workflows) do
    local old = raw.workflows[id] or {}; assert(type(old) == 'table','invalid workflow state')
    local w = {lifecycle=old.lifecycle or 'COLD',lastActive=old.lastActive or 0,pinned=old.pinned == true,windows={},spaces={}}
    assert(w.lifecycle == 'ACTIVE' or w.lifecycle == 'WARM' or w.lifecycle == 'COLD', 'invalid lifecycle')
    assert(finite(w.lastActive), 'invalid timestamp')
    for key, record in pairs(old.windows or {}) do
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
    if w.lifecycle == 'ACTIVE' then w.lifecycle = 'WARM' end
    if type(old.terminalProcesses)=='table' then
      w.terminalProcesses={}
      for _,command in ipairs(old.terminalProcesses) do if type(command)=='string' then w.terminalProcesses[#w.terminalProcesses+1]=command end end
    end
    if type(old.retained)=='table' then
      w.retained={}; for adapter,reason in pairs(old.retained) do if type(adapter)=='string' and type(reason)=='string' then w.retained[adapter]=reason end end
    end
    if type(old.safari)=='table' and type(old.safari.tabGroup)=='string' then w.safari={tabGroup=old.safari.tabGroup,verified=false} end
    data.workflows[id] = w
  end
  if type(raw.active) == 'string' and data.workflows[raw.active] then
    data.active = raw.active; data.workflows[raw.active].lifecycle = 'ACTIVE'
  end
  return data
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
      local encoded = hs.json.encode(self.data, true); assert(encoded,'JSON encoding failed')
      local f = assert(io.open(tmp,'w')); local written, why=f:write(encoded); local closed, closeErr=f:close()
      assert(written,why); assert(closed,closeErr); assert(os.rename(tmp,self.path))
    end)
    if not good then U.log('ERROR','State save failed: ' .. tostring(err)); return false,err end
    return true
  end
  return self
end
return M
