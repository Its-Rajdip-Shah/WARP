local U=require('warp.util')
local W=require('warp.windows')
local Spaces=require('warp.spaces')
local Request=require('warp.request')
local M={}
function M.new(config)
  local self={config=config,store=require('warp.state').new(config),generation=0,switching=false,errors={},hotkeys={},stopped=false}
  self.adapters={}
  for _,name in ipairs({'safari','vscode','terminal','figma','docker'}) do
    self.adapters[#self.adapters+1]=require('warp.adapters.'..name).new(config,self.store.data.shared)
  end
  for _,a in ipairs(self.adapters) do if a.id=='vscode' then self.vscode=a elseif a.id=='safari' then self.safari=a end end
  if self.vscode.attach then self.vscode:attach(self.store) end
  function self:discover(id)
    local out={}; local w=config.workflows[id]; if not w then return out end
    for _,a in ipairs(self.adapters) do
      local ok,items=U.try(a.id..' discovery',function() return a:discover(w) end)
      if ok then for _,item in ipairs(items) do out[#out+1]=item end end
    end
    return out
  end
  function self:checkpoint(id)
    id=id or self.store.data.active; if not config.workflows[id] then return false,'no active workflow' end
    local state=self.store.data.workflows[id]
    if self.vscode.checkpoint then U.try('VS Code membership checkpoint',function() self.vscode:checkpoint(config.workflows[id],state) end) end
    local live=self:discover(id)
    for _,item in ipairs(live) do
      U.try(item.adapter..' checkpoint',function()
        local key=W.key(item.adapter,item.identity)
        state.windows[key]=W.capture(item.win,item.adapter,item.identity,state.windows[key])
      end)
    end
    U.try('Space registry',function() Spaces.rebuild(config.workflows[id],state,live) end)
    self.store:save(); U.log('INFO','Checkpoint complete: '..id); return true
  end
  function self:makeCold(id)
    local state=self.store.data.workflows[id]; local workflow=config.workflows[id]
    if not state or state.lifecycle~='WARM' or state.pinned or workflow.pinned or self.switching then return false,'only unpinned WARM workflows can become COLD' end
    self:checkpoint(id)
    state.lifecycle='COLD'; self.store:save()
    for _,a in ipairs(self.adapters) do if a.cold then U.try(a.id..' cold',function() a:cold(workflow,state) end) end end
    state.lifecycle='COLD'; self.store:save(); U.log('INFO',id..' -> COLD (unproven-safe resources retained)'); return true
  end
  function self:pin(id,pinned)
    local state=self.store.data.workflows[id]; if not state then return false,'unknown workflow' end
    state.pinned=pinned~=false; self.store:save(); return true
  end
  function self:switchTo(id)
    if self.stopped then return false,'WARP stopped' end
    local target=config.workflows[id]; if not target then return false,'unknown workflow: '..tostring(id) end
    if not hs.accessibilityState() then U.log('ERROR','Accessibility permission required'); return false,'Accessibility permission required' end
    if self.vscode.cancel then self.vscode:cancel('workflow changed') end
    if self.vscode.coldStore then self.vscode.coldStore:stop() end
    if self.safari.stop then self.safari:stop() end
    self.generation=self.generation+1
    if self.request then self.request:cancel() end
    self.switching=true; self.errors={}
    local old=self.store.data.active
    U.log('INFO','Switching '..tostring(old)..' -> '..id..' [request '..self.generation..']')
    if old then
      self:checkpoint(old)
      if old~=id then
        local state=self.store.data.workflows[old]; state.lifecycle='WARM'; state.lastActive=hs.timer.secondsSinceEpoch()
        for _,item in ipairs(self:discover(old)) do if item.adapter~='safari' and item.adapter~='vscode' then U.try(item.adapter..' warm',function() W.warm(item.win) end) end end
      end
    end
    -- Commit target before asynchronous restore: a new request checkpoints this partial context.
    self.store.data.active=id
    local state=self.store.data.workflows[id]; state.lifecycle='ACTIVE'; state.lastActive=hs.timer.secondsSinceEpoch(); state.retained=nil
    self.store:save()
    local index,advance=0,nil
    local ctx
    local function fail(message) self.errors[#self.errors+1]=message; U.log('ERROR',message) end
    ctx=Request.new(self.generation,function() return self.generation end,function(err) fail(err); advance() end)
    self.request=ctx
    local function finish()
      if not ctx:valid() then return end
      self:checkpoint(id)
      local live=self:discover(id)
      local ok,result=U.try('primary Space',function()
        Spaces.rebuild(target,state,live)
        local success,why=Spaces.primary(target,state.spaces,live); if not success then fail('Space navigation: '..tostring(why)) end
      end)
      if not ok then fail(tostring(result)) end
      self.switching=false; self.store:save()
      if self.vscode.focus then self.vscode:focus(hs.window.focusedWindow()) end
      ctx:cancel(); self.request=nil
      U.log('INFO',id..' ACTIVE; restore finished with '..#self.errors..' issue(s)')
      if #self.errors>0 and config.settings.notifications~=false then hs.notify.new({title='WARP',informativeText=target.label..' active — '..#self.errors..' restore issue(s); see console'}):send() end
    end
    advance=function()
      if not ctx:valid() then return end
      index=index+1; local adapter=self.adapters[index]; if not adapter then finish(); return end
      local called=false
      local function done(ok,err)
        if called or not ctx:valid() then return end; called=true
        if not ok then fail(adapter.id..' restore: '..tostring(err)) end
        -- Yield between adapters so a newer key event can supersede this request.
        ctx:after(0,advance)
      end
      local ok,err=xpcall(function() adapter:restore(target,state,ctx,done) end,debug.traceback)
      if not ok then done(false,err) end
    end
    ctx:after(0,advance); return true
  end
  function self:navigate(direction)
    local id=self.store.data.active; if not id or self.switching then return false,'no settled active workflow' end
    local ok,result=U.try('workflow Space navigation',function()
      local entries=Spaces.rebuild(config.workflows[id],self.store.data.workflows[id],self:discover(id))
      local success,err=Spaces.navigate(entries,direction); if not success then U.log('WARN',err) end; return success
    end)
    return ok and result
  end
  function self:diagnostics()
    return U.copy({loaded=not self.stopped,active=self.store.data.active,switching=self.switching,generation=self.generation,errors=self.errors,statePath=self.store.path,persistenceEnabled=self.store.writable,accessibility=hs.accessibilityState(),secureInput=hs.eventtap.isSecureInputEnabled(),state=self.store.data,config=config})
  end
  function self:start()
    W.start()
    if self.vscode.start then self.vscode:start(function() return not self.switching and not self.stopped and self.store.data.active or nil end) end
    self.wheel=require('warp.wheel').new(config,function(id) U.try('switch request',function() self:switchTo(id) end) end); self.wheel:start()
    local nav=config.settings.navigation
    if nav then
      for _,entry in ipairs({{nav.next,1},{nav.previous,-1}}) do
        if hs.keycodes.map[entry[1]] then self.hotkeys[#self.hotkeys+1]=hs.hotkey.bind(nav.mods,entry[1],function() self:navigate(entry[2]) end)
        else U.log('WARN','Unknown navigation key: '..entry[1]) end
      end
    end
    self.lifecycle=require('warp.lifecycle').new(self)
    self.screenWatcher=hs.screen.watcher.new(function()
      if self.wheel.visible then self.wheel:dismiss(); self.wheel.latched=true end
      -- Invalidate hints only. Placement is restored on the next activation.
      for _,s in pairs(self.store.data.workflows) do s.spaces={} end
    end):start()
    self.menu=hs.menubar.new()
    if self.menu then self.menu:setTitle('WARP'):setMenu(function()
      local items={}; local active=self.store.data.active
      for _,w in ipairs(config.list) do items[#items+1]={title=w.label..' · '..self.store.data.workflows[w.id].lifecycle,checked=active==w.id,fn=function() self:switchTo(w.id) end} end
      items[#items+1]={title='-'}
      items[#items+1]={title='Checkpoint',disabled=not active,fn=function() self:checkpoint() end}
      items[#items+1]={title='Pin active workflow',disabled=not active,checked=active and self.store.data.workflows[active].pinned or false,fn=function() self:pin(active,not self.store.data.workflows[active].pinned) end}
      items[#items+1]={title='Next workflow Space',fn=function() self:navigate(1) end}
      items[#items+1]={title='Previous workflow Space',fn=function() self:navigate(-1) end}
      return items
    end) end
    U.log('INFO','Loaded '..#config.list..' workflows; no desktop actions run on load')
    hs.alert.show('WARP loaded',1)
  end
  function self:stop()
    if self.stopped then return end
    if not self.switching and self.store.data.active then self:checkpoint() end
    if self.safari.stop then self.safari:stop() end
    if self.vscode.stop then self.vscode:stop() end
    self.stopped=true; self.generation=self.generation+1
    if self.request then self.request:cancel() end
    self.switching=false
    if self.wheel then self.wheel:stop() end
    if self.lifecycle then self.lifecycle:stop() end
    if self.screenWatcher then self.screenWatcher:stop() end
    for _,key in ipairs(self.hotkeys) do key:delete() end; self.hotkeys={}
    if self.menu then self.menu:delete() end
    W.stop()
    self.store:save()
  end
  return self
end
return M
