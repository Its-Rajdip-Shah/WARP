local U=require('warp.util')
local W=require('warp.windows')
local M={}
local bundle='com.microsoft.VSCode'
local function identity(win)
  if not win then return end
  local ok,key=pcall(function()
    local app=win:application()
    if app and app:bundleID()==bundle and win:id() then return tostring(app:pid())..':'..win:id() end
  end)
  if ok then return key end
end
function M.new(config)
  local self={focusEpoch=0,id='vscode',members={},dead={},recycled={},running=false}
  local function log(s) U.log('VSCODE',s) end
  function self:attach(store) self.coldStore=require('warp.vscode_cold').new(self,store,identity) end
  function self:cancel(reason)
    self.focusEpoch=self.focusEpoch+1
    local c=self.candidate
    if c then
      if c.timer then c.timer:stop() end
      self.candidate=nil
      log('qualification cancelled id='..c.id..': '..reason)
    end
  end
  function self:owns(workflow,win)
    local k=identity(win)
    return k and self.members[workflow] and self.members[workflow][k] and not self.dead[k] or false
  end
  function self:focus(win)
    local k=identity(win); local workflow=self.active and self.active()
    if self.candidate and self.candidate.key==k and self.candidate.workflow==workflow then return end
    self:cancel('focus changed')
    if not self.running or not k or not workflow or not config.workflows[workflow].vscode or self:owns(workflow,win) then return end
    -- A newly focused window with a recycled ID begins a new membership lifetime.
    if self.dead[k] then
      for _,members in pairs(self.members) do members[k]=nil end
      self.dead[k]=nil; self.recycled[k]=true
    end
    local c={key=k,id=win:id(),win=win,workflow=workflow,checks=0}; self.candidate=c
    log('candidate id='..win:id()..' workflow='..workflow)
    local function check()
      c.timer=nil
      if self.candidate~=c or not self.running then return end
      if self.active()~=workflow then self:cancel('workflow changed'); return end
      if self.dead[k] or identity(c.win)~=k or identity(hs.window.focusedWindow())~=k then self:cancel('focus changed or window closed'); return end
      c.checks=c.checks+1
      log('qualification '..c.checks..'/6 id='..win:id())
      if c.checks==6 then
        self.members[workflow]=self.members[workflow] or {}; self.members[workflow][k]=win
        self.candidate=nil; log('ADOPT id='..win:id()..' workflow='..workflow)
        if self.coldStore then self.coldStore:learn(win) end
      else c.timer=hs.timer.doAfter(10,check) end
    end
    c.timer=hs.timer.doAfter(10,check)
  end
  function self:start(active)
    if self.running then return end
    self.running=true; self.active=active
    local f=hs.window.filter
    self.filter=f.new(function(win) return identity(win)~=nil end)
    self.filter:subscribe(f.windowFocused,function(win) self:focus(win) end)
    self.filter:subscribe(f.windowUnfocused,function() self:cancel('focus changed') end)
    self.filter:subscribe(f.windowDestroyed,function(win)
      if self.coldStore then self.coldStore:destroyed(win) end
      -- The event is definitive; enumeration absence is not.
      for _,members in pairs(self.members) do for k,owned in pairs(members) do if owned==win then self.dead[k]=true end end end
      if self.candidate and self.candidate.win==win then self:cancel('window closed') end
    end)
    self:focus(hs.window.focusedWindow())
  end
  function self:stop()
    if self.coldStore then self.coldStore:stop() end
    self.running=false; self:cancel('stopped')
    if self.filter then self.filter:unsubscribeAll(); self.filter:pause(); self.filter=nil end
    self.members={}; self.dead={}; self.recycled={}
  end
  function self:checkpoint(workflow,state)
    -- Enumerate as positive evidence only; retained handles cover hidden/minimized Spaces.
    W.list('vscode')
    for k,win in pairs(self.members[workflow.id] or {}) do
      local ok,id=pcall(function() return win:id() end)
      local current=identity(win)
      if self.dead[k] or (ok and id==nil) or (current and current~=k) then
        self.members[workflow.id][k]=nil; state.windows[W.key('vscode',k)]=nil
      end
    end
  end
  function self:discover(workflow)
    local out={}; if not workflow.vscode then return out end
    for k,win in pairs(self.members[workflow.id] or {}) do
      if not self.dead[k] and identity(win)==k then out[#out+1]={win=win,adapter='vscode',identity=k} end
    end
    table.sort(out,function(a,b) return a.identity<b.identity end)
    return out
  end
  function self:restore(workflow,state,ctx,done)
    local function converge(errors)
      errors=errors or {}
      local items=self:discover(workflow); local i=0
      local function finish()
        for _,win in ipairs(W.list('vscode')) do
          if not self:owns(workflow.id,win) then
            local ok,why=pcall(function()
              -- Generic warm leaves fullscreen alone; this MVP reports that limitation.
              if win:isFullScreen() then error('non-target fullscreen Code window cannot minimize safely') end
              if not win:isMinimized() then win:minimize() end
              log('minimize id='..win:id()..' target='..workflow.id)
            end)
            if not ok then errors[#errors+1]=tostring(why) end
          end
        end
        done(#errors==0,table.concat(errors,'; '))
      end
      local function nextWindow()
        if not ctx:valid() then return end
        i=i+1; local item=items[i]; if not item then finish(); return end
        local called=false; local child
        local function advance(ok,why)
          if called then return end; called=true
          if child then child:cancel() end
          if not ok then errors[#errors+1]=tostring(why) end
          nextWindow()
        end
        child=require('warp.request').new(1,function() return ctx:valid() and 1 or 0 end,function(why) advance(false,why) end)
        if ctx.onCancel then ctx:onCancel(function() child:cancel() end) end
        local ok,why=pcall(function()
          local r=(not self.recycled[item.identity] and state.windows[W.key('vscode',item.identity)]) or W.capture(item.win,'vscode',item.identity)
          log('restore id='..item.win:id()..' target='..workflow.id)
          local app=item.win:application()
          if app.isHidden and app:isHidden() then app:unhide() end
          W.restore(item.win,r,child,advance)
        end)
        if not ok then advance(false,why) end
      end
      nextWindow()
    end
    if self.coldStore then
      local ended=false; local reopenCtx
      local function finish(errors)
        if ended or not ctx:valid() then return end; ended=true
        reopenCtx:cancel(); converge(errors)
      end
      reopenCtx=require('warp.request').new(1,function() return ctx:valid() and 1 or 0 end,function(why) finish({why}) end)
      if ctx.onCancel then ctx:onCancel(function() reopenCtx:cancel() end) end
      reopenCtx:guard(function() self.coldStore:reopen(workflow,reopenCtx,finish) end)
    else converge() end
  end
  function self:debug()
    local rows,seen={},{}
    local function add(win)
      local k=identity(win); if not k or seen[k] or self.dead[k] then return end; seen[k]=true
      local owners={}; for id in pairs(self.members) do if self:owns(id,win) then owners[#owners+1]=id end end; table.sort(owners)
      rows[#rows+1]={id=win:id(),title=win:title(),owners=owners}
    end
    for _,win in ipairs(W.list('vscode')) do add(win) end
    for _,members in pairs(self.members) do for _,win in pairs(members) do add(win) end end
    table.sort(rows,function(a,b) return a.id<b.id end)
    log('runtime windows:')
    for _,r in ipairs(rows) do log('id='..r.id..' title='..string.format('%q',r.title or '')..' owners={'..table.concat(r.owners,',')..'}') end
    if self.coldStore then self.coldStore:debug() end
    return rows
  end
  function self:cold(workflow,state)
    if self.coldStore then self.coldStore:close(workflow,state) end
  end
  return self
end
return M
