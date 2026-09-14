-- Descriptor transport only. No owners and no close/COLD commands.
local B=require('warp.vscode_bridge')
local W=require('warp.windows')
local U=require('warp.util')
local R=require('warp.request')
local M={}
local function isCode(win)
  local app=win and win:application()
  return app and app:bundleID()=='com.microsoft.VSCode'
end
function M.runtime(win)
  local ok,key=pcall(function() local id=win:id();if id then return tostring(win:application():pid())..':'..id end end)
  return ok and key or nil
end
function M.key(d) return B.valid(d) and (d.kind..':'..d.path) or nil end
function M.new()
  local self={bridge=B.new(),bindings={},pending={},epoch=0}
  function self:cancelProbe()
    if self.probe then self.probe:cancel();self.probe=nil end
  end
  function self:learn(win)
    if not win then return end
    self:cancelProbe()
    if not isCode(win) then return end
    local key=M.runtime(win);if not key then return end;local ctx
    ctx=R.new(1,function() return self.probe==ctx and 1 or 0 end,function() self:cancelProbe() end)
    self.probe=ctx
    ctx:guard(function() self.bridge:request(ctx,'probe',nil,nil,function(r)
      if r and B.valid(r.descriptor) and M.runtime(hs.window.focusedWindow())==key then
        self.bindings[key]={session=r.session,descriptor=U.copy(r.descriptor),win=win}
      end
      self:cancelProbe()
    end) end)
  end
  function self:start(active)
    local f=hs.window.filter
    self.filter=f.new(function(w) return not not isCode(w) end)
    self.filter:subscribe(f.windowFocused,function(w) if not w then return end;self.epoch=self.epoch+1;if active() then self:learn(w) end end)
    self.filter:subscribe(f.windowUnfocused,function() self.epoch=self.epoch+1;self:cancelProbe() end)
    self.filter:subscribe(f.windowDestroyed,function(win)
      if not win then return end
      self.epoch=self.epoch+1;self:cancelProbe()
      local runtime=M.runtime(win)
      for key,b in pairs(self.bindings) do if b.win==win or key==runtime then self.bindings[key]=nil end end
    end)
  end
  function self:prepare(ctx,done)
    self:cancelProbe()
    local epoch=self.epoch;local initial=M.runtime(hs.window.focusedWindow())
    self.bridge:request(ctx,'inventory',nil,nil,function(response,why)
      if not response then U.log('VSCODE','descriptor inventory unavailable; runtime-only presentation: '..tostring(why)) end
      self.inventory=response and response.windows or nil
      local sessions={}
      for _,r in ipairs(self.inventory or {}) do sessions[r.session]=r end
      for key,b in pairs(self.bindings) do
        local r=sessions[b.session]
        if r and B.valid(r.descriptor) then b.descriptor=U.copy(r.descriptor)
        end
      end
      -- A single focused companion response can identify the native focused Code window.
      local focused=hs.window.focusedWindow();local count,chosen=0,nil
      for _,r in ipairs(self.inventory or {}) do if r.focused and B.valid(r.descriptor) then count=count+1;chosen=r end end
      if count==1 and epoch==self.epoch and M.runtime(focused)==initial and isCode(focused) then
        self.bindings[M.runtime(focused)]={session=chosen.session,descriptor=U.copy(chosen.descriptor),win=focused}
      end
      done()
    end)
  end
  function self:descriptor(win)
    local b=self.bindings[M.runtime(win)];return b and (not b.win or b.win==win) and b.descriptor
  end
  function self:reopen(ctx,descriptor,done)
    local key=M.key(descriptor)
    if not key then done(nil,'invalid Code descriptor');return end
    local live=W.list('vscode')
    local allMapped=true
    for _,win in ipairs(live) do
      local known=self:descriptor(win)
      if B.same(known,descriptor) then
        U.log('VSCODE','resource='..key..' liveMatch=verified reopenAction=reuse newWindowId='..win:id())
        self.pending[key]=nil;done(win);return
      end
      if not B.valid(known) then allMapped=false end
    end
    -- Verified live bindings rule out duplicates without consulting dead sessions.
    -- Unmapped live windows still require complete, unambiguous inventory.
    if not allMapped then
      if not self.inventory or #self.inventory~=#live then done(nil,'incomplete companion inventory; reopen deferred');return end
      for _,r in ipairs(self.inventory) do
        if B.same(r.descriptor,descriptor) or (not B.valid(r.descriptor) and not r.empty) then
          done(nil,'unmapped or matching live resource; reopen deferred');return
        end
      end
    end
    if self.pending[key] then done(nil,'previous reopen unresolved: '..key);return end
    U.log('VSCODE','resource='..key..' liveMatch=none reopenEligibility=verified-descriptor reopenAction=launch')
    local cli='/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
    local mode=hs.fs.attributes(descriptor.path,'mode')
    if not hs.fs.attributes(cli) or (descriptor.kind=='folder' and mode~='directory') or (descriptor.kind=='workspace' and mode~='file') then done(nil,'missing Code CLI or resource path');return end
    local before={};for _,w in ipairs(live) do before[M.runtime(w)]=true end
    self.pending[key]=true -- Do not repeat an uncertain launch after cancellation/timeout.
    ctx:task(cli,{'--new-window',descriptor.path},function(code,_,err)
      if code~=0 then done(nil,'Code launch failed: '..err);return end
      ctx:wait('Code resource window',function()
        local w=hs.window.focusedWindow()
        return isCode(w) and M.runtime(w) and not before[M.runtime(w)]
      end,function(ok,why)
        if not ok then done(nil,why);return end
        local attempts=0
        local function identify()
          if not ctx:valid() then return end
          attempts=attempts+1
          local win=hs.window.focusedWindow();local runtime=M.runtime(win);local epoch=self.epoch
          U.log('VSCODE','resource='..key..' companionRequest=inventory-after-launch attempt='..attempts)
          self.bridge:request(ctx,'inventory',nil,nil,function(response,reason)
            local matches={}
            for _,r in ipairs(response and response.windows or {}) do
              if r.focused and B.same(r.descriptor,descriptor) then matches[#matches+1]=r end
            end
            if #matches==1 and runtime and not before[runtime] and self.epoch==epoch and M.runtime(hs.window.focusedWindow())==runtime then
              local r=matches[1]
              self.bindings[runtime]={session=r.session,descriptor=U.copy(r.descriptor),win=win}
              self.pending[key]=nil;self.inventory=response.windows
              U.log('VSCODE','resource='..key..' reopenResult=verified newWindowId='..win:id())
              done(win)
            elseif attempts<3 then
              identify()
            else
              local why=reason or 'reopened resource identity not verified after 3 inventory requests'
              U.log('VSCODE','resource='..key..' reopenResult=unverified companionRequest=inventory reason='..why)
              done(nil,why)
            end
          end)
        end
        identify()
      end,3)
    end,3)
  end
  function self:stop()
    self:cancelProbe()
    if self.filter then self.filter:unsubscribeAll();self.filter:pause();self.filter=nil end
    self.bindings={};self.pending={};self.inventory=nil
  end
  return self
end
return M
