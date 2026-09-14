local U=require('warp.util')
local W=require('warp.windows')
local B=require('warp.vscode_bridge')
local Request=require('warp.request')
local M={}
function M.new(adapter,store,identity)
  local self={bindings={},pending={},tasks={},bridge=B.new()}
  store.data.shared.vscodeCold=store.data.shared.vscodeCold or {}
  self.records=store.data.shared.vscodeCold
  local function log(s) U.log('VSCODE',s) end
  local complete
  local function context()
    local ctx
    ctx=Request.new(1,function() return self.tasks[ctx] and 1 or 0 end,function(e) log('preserved: '..e); if ctx then complete(ctx) end end)
    self.tasks[ctx]=true; return ctx
  end
  complete=function(ctx)
    ctx:cancel(); self.tasks[ctx]=nil
    for key,p in pairs(self.pending) do if p.ctx==ctx then
      if p.record.state=='close_requested' then p.record.state='close_uncertain'; store:save() end
      self.pending[key]=nil
    end end
  end
  function self:stop()
    for ctx in pairs(self.tasks) do complete(ctx) end; self.tasks={}
  end
  function self:learn(win)
    local key=identity(win); local epoch=adapter.focusEpoch
    if not key then return end
    local ctx=context()
    self.bridge:request(ctx,'probe',nil,nil,function(r,why)
      if r and B.valid(r.descriptor) and identity(hs.window.focusedWindow())==key and epoch==adapter.focusEpoch then
        self.bindings[key]={session=r.session,descriptor=r.descriptor}
        log('restore descriptor learned id='..win:id()..' '..r.descriptor.kind..':'..r.descriptor.path)
      else log('preserved id='..tostring(win:id())..': '..(why or 'no verified local workspace')) end
      complete(ctx)
    end)
  end
  function self:destroyed(win)
    for _,members in pairs(adapter.members) do for key,owned in pairs(members) do if owned==win then self.bindings[key]=nil end end end
    for key,p in pairs(self.pending) do
      if p.win==win then
        p.record.state='warp_cold_closed'; store:save(); self.pending[key]=nil
        log('cold-close logical='..p.logical..' confirmed')
      end
    end
  end
  function self:close(workflow,state)
    for key,win in pairs(adapter.members[workflow.id] or {}) do
      if not adapter.dead[key] and identity(win)==key then
        local needed=false; local owners={}
        for id in pairs(adapter.members) do if adapter:owns(id,win) then
          owners[id]=true
          local lifecycle=store.data.workflows[id].lifecycle
          if id~=workflow.id and (lifecycle=='ACTIVE' or lifecycle=='WARM') then needed=true end
        end end
        local binding=self.bindings[key]
        if needed or not binding or self.pending[key] then
          log('preserve id='..win:id()..': '..(needed and 'shared ACTIVE/WARM owner' or 'no verified descriptor / close pending'))
        else
          local ctx=context()
          self.bridge:request(ctx,'inspect',binding.session,nil,function(r,why)
            -- Recheck owners/lifecycle after the asynchronous observation.
            local safe=r and B.valid(r.descriptor) and not r.dirty and r.terminals==0 and identity(win)==key
            if safe then
              local mode=hs.fs.attributes(r.descriptor.path,'mode')
              safe=hs.fs.attributes('/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code')
                and ((r.descriptor.kind=='folder' and mode=='directory') or (r.descriptor.kind=='workspace' and mode=='file'))
            end
            for id in pairs(adapter.members) do if adapter:owns(id,win) and store.data.workflows[id].lifecycle~='COLD' then safe=false end end
            if not safe then log('preserve id='..tostring(win:id())..': '..(why or 'workspace changed, dirty editor, terminal or live owner')); complete(ctx); return end
            binding.descriptor=U.copy(r.descriptor)
            local logical=hs.host.uuid()
            local record={state='close_requested',descriptor=U.copy(r.descriptor),owners=owners,layout=state.windows[W.key('vscode',key)]}
            if record.layout then record.layout=U.copy(record.layout); record.layout.windowID=nil; record.layout.pid=nil; record.layout.spaceIDs=nil; record.layout.identity=nil; record.layout.title=nil end
            self.records[logical]=record
            if not store:save() then self.records[logical]=nil; log('preserve: cannot persist close intent'); complete(ctx); return end
            self.pending[key]={ctx=ctx,win=win,record=record,logical=logical}
            log('cold-close logical='..logical..' workflow='..workflow.id)
            self.bridge:request(ctx,'close',binding.session,r.descriptor,function(answer,err)
              if not answer or not answer.accepted then
                if record.state~='warp_cold_closed' then record.state='close_uncertain'; store:save() end
                self.pending[key]=nil; log('preserve/inspect logical='..logical..': '..(err or 'close vetoed')); complete(ctx); return
              end
              ctx:wait('Code graceful close',function() return record.state=='warp_cold_closed' end,function(closed)
                if not closed then
                  -- Do not claim a vetoed or delayed close succeeded, or resurrect on ambiguity.
                  record.state='close_uncertain'; self.pending[key]=nil; store:save(); log('close unconfirmed logical='..logical)
                end
                complete(ctx)
              end,3)
            end)
          end)
        end
      end
    end
  end
  function self:reopen(workflow,ctx,done)
    local queue={}; for id,r in pairs(self.records) do if r.state=='warp_cold_closed' and r.owners[workflow.id] then queue[#queue+1]={id=id,r=r} end end
    local errors={}; local i=0
    local function nextRecord()
      if not ctx:valid() then return end
      i=i+1; local item=queue[i]; if not item then done(errors); return end
      local record=item.r
      local function bind(win,binding)
        local key=identity(win); if not key then errors[#errors+1]='reopen window disappeared'; nextRecord(); return end
        for owner in pairs(record.owners) do if store.data.workflows[owner] then
          adapter.members[owner]=adapter.members[owner] or {}; adapter.members[owner][key]=win
          if record.layout then store.data.workflows[owner].windows[W.key('vscode',key)]=U.copy(record.layout) end
        end end
        adapter.dead[key]=nil; self.bindings[key]=binding
        self.records[item.id]=nil; store:save(); log('rebound logical='..item.id..' id='..win:id()); nextRecord()
      end
      for _,win in ipairs(W.list('vscode')) do
        local binding=self.bindings[identity(win)]
        if binding and B.same(binding.descriptor,record.descriptor) then
          self.bridge:request(ctx,'inspect',binding.session,nil,function(r,why)
            if r and B.same(r.descriptor,record.descriptor) then bind(win,binding)
            else errors[#errors+1]=why or 'live project changed; reopen deferred'; nextRecord() end
          end)
          return
        end
      end
      local function launch()
        local cli='/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
        local mode=hs.fs.attributes(record.descriptor.path,'mode')
        if not hs.fs.attributes(cli) or (record.descriptor.kind=='folder' and mode~='directory') or (record.descriptor.kind=='workspace' and mode~='file') then
          errors[#errors+1]='missing Code CLI or restore path'; nextRecord(); return
        end
        local before={}; for _,w in ipairs(W.list('vscode')) do before[identity(w)]=true end
        -- Persist an uncertain reopen before launch. Cancellation/reload must not duplicate it.
        record.state='reopen_pending'
        if not store:save() then record.state='warp_cold_closed'; errors[#errors+1]='cannot persist reopen intent'; nextRecord(); return end
        log('reopen logical='..item.id..' workflow='..workflow.id)
        ctx:task(cli,{'--new-window',record.descriptor.path},function(code,_,err)
          if code~=0 then errors[#errors+1]='CLI reopen failed: '..err; nextRecord(); return end
          ctx:wait('Code reopened window',function()
            local w=hs.window.focusedWindow(); return identity(w) and not before[identity(w)]
          end,function(ok,why)
            if not ok then errors[#errors+1]=why; nextRecord(); return end
            local win=hs.window.focusedWindow(); local key=identity(win); local epoch=adapter.focusEpoch
            self.bridge:request(ctx,'probe',nil,nil,function(r,reason)
              if r and B.same(r.descriptor,record.descriptor) and identity(hs.window.focusedWindow())==key and epoch==adapter.focusEpoch then bind(win,{session=r.session,descriptor=r.descriptor})
              else errors[#errors+1]=reason or 'reopen binding uncertain'; nextRecord() end
            end)
          end,5)
        end,5)
      end
      -- Unmapped existing windows may already contain this project: do not guess/reopen duplicates.
      local unknown=false
      for _,w in ipairs(W.list('vscode')) do if not self.bindings[identity(w)] then unknown=true end end
      if unknown then
        self.bridge:request(ctx,'inventory',nil,nil,function(response)
          local windows=response and response.windows
          local safe=windows and #windows==#W.list('vscode')
          for _,r in ipairs(windows or {}) do
            if B.same(r.descriptor,record.descriptor) or (not B.valid(r.descriptor) and not r.empty) then safe=false end
          end
          if safe then launch() else errors[#errors+1]='unmapped/matching live Code window: reopen deferred to avoid duplicate'; nextRecord() end
        end)
      else launch() end
    end
    nextRecord()
  end
  function self:debug()
    for id,r in pairs(self.records) do
      local owners={}; for owner in pairs(r.owners) do owners[#owners+1]=owner end; table.sort(owners)
      log('logical='..id..' owners={'..table.concat(owners,',')..'} state='..r.state..' restore='..r.descriptor.kind..':'..r.descriptor.path)
    end
    for key,b in pairs(self.bindings) do log('runtime='..key..' restore='..b.descriptor.kind..':'..b.descriptor.path) end
  end
  return self
end
return M
