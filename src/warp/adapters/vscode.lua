-- Workflow resources with presentation state. Descriptor observation is not ownership.
local U=require('warp.util')
local W=require('warp.windows')
local Resources=require('warp.vscode_resources')
local M={}
local function minimized(s) return s.visibility=='minimized' or (s.visibility==nil and s.minimized) end
local function fullscreen(s) return s.restorePresentation=='fullscreen' or (s.restorePresentation==nil and s.fullscreen) end
local function presentation(s)
  s.visibility=minimized(s) and 'minimized' or 'visible'
  s.restorePresentation=fullscreen(s) and 'fullscreen' or 'normal'
  s.minimized=s.visibility=='minimized';s.fullscreen=s.restorePresentation=='fullscreen'
  return s
end
local function frame(win)
  local f=win:frame()
  return {x=f.x,y=f.y,w=f.w,h=f.h}
end
local function sameFrame(a,b)
  for _,axis in ipairs({'x','y','w','h'}) do if math.abs(a[axis]-b[axis])>2 then return false end end
  return true
end
function M.new()
  local self={id='vscode',snapshots={},configured={},resources=Resources.new(),intent={},transitions={}}
  local function log(s) U.log('VSCODE',s) end
  local function liveWindows()
    local live={}
    for _,win in ipairs(W.list('vscode')) do local id=win:id(); if id then live[id]=win end end
    return live
  end
  function self:start(active) self.resources:start(active) end
  function self:prepare(ctx,done) self.resources:prepare(ctx,done) end
  local function resourceKey(win)
    local descriptor=self.resources:descriptor(win)
    return Resources.key(descriptor) or ('runtime:'..Resources.runtime(win)),descriptor
  end
  function self:checkpoint(workflow)
    if not workflow.vscode then return end
    local live=liveWindows();local snapshot=self.configured[workflow.id] and U.copy(self.snapshots[workflow.id] or {}) or {};local count=0
    local observed={}
    for id,win in pairs(live) do
      local screen=win:screen()
      local key,descriptor=resourceKey(win)
      if observed[key] then error('duplicate Code resource identity; capture preserved') end
      observed[key]=true
      local previous=(self.snapshots[workflow.id] or {})[key] or self.intent[key]
      local transition=self.transitions[key]
      if transition and transition.workflow==workflow.id then
        -- A cancelled/unfinished restore is not user curation.
        snapshot[key]=U.copy(transition.state)
      else
        local isMin=win:isMinimized()
        local mode=win:isFullScreen() or (isMin and previous and fullscreen(previous))
        snapshot[key]=presentation({descriptor=U.copy(descriptor),runtime=Resources.runtime(win),windowId=id,title=win:title(),minimized=isMin,fullscreen=not not mode,
          frame=(mode and (isMin or win:isFullScreen())) and previous and U.copy(previous.frame) or frame(win),screen=screen and screen:getUUID()})
      end
      self.intent[key]=U.copy(snapshot[key])
      log('capture resource='..key..' visibility='..snapshot[key].visibility..' restorePresentation='..snapshot[key].restorePresentation)
      count=count+1
    end
    self.snapshots[workflow.id]=snapshot;self.configured[workflow.id]=true
    log('snapshot workflow='..workflow.id..' windows='..count)
  end
  function self:discover(workflow)
    local out={};if not workflow.vscode then return out end
    local snapshot=self.snapshots[workflow.id]
    for id,win in pairs(liveWindows()) do
      -- Only visible snapshot entries contribute to workflow Space navigation.
      local key=resourceKey(win)
      if (not self.configured[workflow.id] or (snapshot[key] and not minimized(snapshot[key]))) and not win:isMinimized() then
        out[#out+1]={win=win,adapter='vscode',identity=tostring(id)}
      end
    end
    return out
  end
  function self:restore(workflow,_,ctx,done)
    if not workflow.vscode then done(true);return end
    local snapshot=self.snapshots[workflow.id]
    local curation=not self.configured[workflow.id]
    snapshot=snapshot or {}
    local live=liveWindows()
    local pending,errors,queue={},{},{}
    local advance
    local matched={}
    local function apply(id,win,saved)
      if not ctx:valid() then return end
      local key=resourceKey(win)
      if saved then
        saved=presentation(U.copy(saved))
        self.intent[key]=U.copy(saved)
        self.transitions[key]={workflow=workflow.id,state=U.copy(saved)}
      else self.transitions[key]=nil end
      local function action(name)
        log('resource='..key..' target visibility='..(saved and saved.visibility or 'curation')..' target restorePresentation='..(saved and saved.restorePresentation or 'unchanged')..' live minimized='..tostring(win:isMinimized())..' live fullscreen='..tostring(win:isFullScreen())..' action='..name)
      end
      local ok,why=pcall(function()
        if win:isFullScreen() and (not saved or (saved.fullscreen and not saved.minimized)) then
          action('preserve-fullscreen');self.transitions[key]=nil;return
        end
        if saved and saved.fullscreen and not saved.minimized then
          action('unminimize');win:unminimize()
          pending[id]={win=win,state=saved,key=key,action=action,curation=curation,unminimizing=true,deadline=hs.timer.secondsSinceEpoch()+2};return
        end
        if saved and win:isFullScreen() then
          action(saved.minimized and 'exit-fullscreen-for-minimize' or 'exit-fullscreen-for-normal');win:setFullScreen(false)
          pending[id]={win=win,state=saved,key=key,action=action,curation=curation,exiting=true,deadline=hs.timer.secondsSinceEpoch()+2}
          return
        end
        if saved then
          win:unminimize()
          win:setFrame(saved.frame)
          if saved.minimized then action('minimize');win:minimize() end
        elseif curation then win:unminimize()
        else win:minimize() end
        pending[id]={win=win,state=saved,key=key,action=action,curation=curation}
      end)
      if not ok then errors[#errors+1]=tostring(why) end
    end
    local function enqueue(id,win,saved)
      queue[#queue+1]={id=id,win=win,saved=saved}
      if saved then
        local key=resourceKey(win)
        self.transitions[key]={workflow=workflow.id,state=presentation(U.copy(saved))}
      end
    end
    for id,win in pairs(live) do
      local key=resourceKey(win);local saved=snapshot[key]
      -- Runtime fallback is valid only for the same still-live process/window.
      if not saved then
        for oldKey,entry in pairs(snapshot) do
          if not entry.descriptor and entry.runtime==Resources.runtime(win) then saved=entry;key=oldKey;break end
        end
      end
      if saved then matched[key]=true end
      enqueue(id,win,saved)
    end
    local missing={}
    for key,saved in pairs(snapshot) do
      if not matched[key] then
        if saved.descriptor and not minimized(saved) then missing[#missing+1]=saved
        elseif not saved.descriptor then snapshot[key]=nil;log('prune stale id='..saved.windowId) end
      end
    end
    -- Complete one resource before starting the next native presentation transition.
    local deadline
    local function verify()
      if not ctx:valid() then return end
      for id,entry in pairs(pending) do
        local ok,matched=pcall(function()
          local win,saved=entry.win,entry.state
          if win:id()~=id then return false end
          if entry.unminimizing then
            if win:isMinimized() then return false end
            entry.unminimizing=false
            entry.action('enter-fullscreen');win:setFullScreen(true)
            entry.deadline=hs.timer.secondsSinceEpoch()+2
          end
          if entry.exiting then
            if win:isFullScreen() then return false end
            entry.exiting=false
            win:unminimize()
            win:setFrame(saved.frame)
            if saved.minimized then entry.action('minimize');win:minimize() end
            entry.deadline=hs.timer.secondsSinceEpoch()+0.75
          end
          if saved and saved.fullscreen and not saved.minimized then return win:isFullScreen() and not win:isMinimized() end
          if win:isFullScreen() then return false end
          local minimized=not entry.curation and (not saved or saved.minimized)
          return win:isMinimized()==minimized and (not saved or sameFrame(frame(win),saved.frame))
        end)
        if ok and matched then
          log(entry.state and ('restore id='..id..' state='..(entry.state.fullscreen and 'fullscreen' or entry.state.minimized and 'minimized' or 'visible')) or ((entry.curation and 'curation visible id=' or 'minimize absent id=')..id))
          log('resource='..entry.key..' result minimized='..tostring(entry.win:isMinimized())..' result fullscreen='..tostring(entry.win:isFullScreen())..' preserved restorePresentation='..(entry.state and entry.state.restorePresentation or 'unchanged'))
          self.transitions[entry.key]=nil
          pending[id]=nil
        elseif not ok or hs.timer.secondsSinceEpoch()>=(entry.deadline or deadline) then
          local why='Code state verification failed id='..id..(not ok and (': '..tostring(matched)) or '')
          log(why);errors[#errors+1]=why;pending[id]=nil
        end
      end
      if next(pending) then ctx:after(0.05,verify)
      else advance() end
    end
    local cursor=0
    advance=function()
      if not ctx:valid() then return end
      cursor=cursor+1
      local item=queue[cursor]
      if not item then done(#errors==0,table.concat(errors,'; '));return end
      deadline=hs.timer.secondsSinceEpoch()+0.75
      apply(item.id,item.win,item.saved)
      verify()
    end
    local i=0
    local function reopenNext()
      if not ctx:valid() then return end
      i=i+1;local saved=missing[i]
      if not saved then advance();return end
      self.resources:reopen(ctx,saved.descriptor,function(win,why)
        if win then enqueue(win:id(),win,saved)
        else errors[#errors+1]=why or 'resource reopen unavailable' end
        reopenNext()
      end)
    end
    reopenNext()
  end
  function self:debug()
    local snapshots=U.copy(self.snapshots)
    for workflow,snapshot in pairs(snapshots) do
      for id,s in pairs(snapshot) do log('snapshot workflow='..workflow..' id='..id..' minimized='..tostring(s.minimized)..' restorePresentation='..tostring(s.restorePresentation)..' visibility='..tostring(s.visibility)) end
    end
    return {configured=U.copy(self.configured),resources=snapshots}
  end
  function self:stop() self.resources:stop();self.snapshots={};self.configured={};self.intent={};self.transitions={} end
  return self
end
return M
