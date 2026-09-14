-- Experimental module tests only: production never instantiates this close/reopen helper.
package.path='./src/?.lua;'..package.path
local Cold=require('warp.vscode_cold')
local C=require('warp.config')
local State=require('warp.state')
local W=require('warp.windows')
local total=0
local function test(name,fn) fn(); total=total+1; print('PASS: '..name) end
local cfg=assert(C.validate({one={label='One',key='1',vscode=true},two={label='Two',key='2',vscode=true}}))
local now,timers,focused,live,launched=0,{},nil,{},0
local function win(id) return {id=function() return id end,application=function() return {pid=function() return 100 end} end} end
local function identity(w) return w and '100:'..w:id() end
hs={host={uuid=function() return 'logical-test' end},timer={secondsSinceEpoch=function() return now end,doAfter=function(delay,fn) local t={at=now+delay,fn=fn}; function t:stop() self.stopped=true end; timers[#timers+1]=t; return t end},window={focusedWindow=function() return focused end},fs={attributes=function(path,field) return field=='mode' and 'directory' or true end}}
W.list=function() return live end
local function flush()
  for _=1,200 do table.sort(timers,function(a,b) return a.at<b.at end); local t=table.remove(timers,1); if not t then return end
    if not t.stopped then now=t.at;t.fn() end
  end
  error('unbounded work')
end
local descriptor={kind='folder',path='/safe/project'}
local function fixture(shared)
  timers={}; now=0; launched=0; local w=win(142); focused=w;live={w}
  local store={data=State.sanitize({version=1,workflows={}},cfg),saves=0}
  store.data.workflows.one.lifecycle='COLD'; store.data.workflows.two.lifecycle=shared or 'COLD'
  function store:save() self.saves=self.saves+1; return not self.fail end
  local a={members={one={['100:142']=w}},dead={},focusEpoch=0}
  if shared then a.members.two={['100:142']=w} end
  function a:owns(id,window) return self.members[id] and self.members[id][identity(window)] and not self.dead[identity(window)] end
  local c=Cold.new(a,store,identity); c.bindings['100:142']={session='session',descriptor=descriptor}
  local calls={}
  c.bridge={request=function(_,_,action,_,d,done)
    calls[#calls+1]=action
    if action=='close' then
      assert(store.saves>0 and c.records['logical-test'].state=='close_requested')
      c:destroyed(w); a.dead['100:142']=true; live={}; done({accepted=true})
    else done({session='session',descriptor=descriptor,dirty=false,terminals=0}) end
  end}
  return c,a,store,w,calls
end
test('exclusive verified cold close persists intent and confirmed logical owners',function()
  local c,a,store,w,calls=fixture(); c:close(cfg.workflows.one,store.data.workflows.one); flush()
  assert(calls[1]=='inspect' and calls[2]=='close' and c.records['logical-test'].state=='warp_cold_closed')
  assert(c.records['logical-test'].owners.one and store.saves>=2 and next(c.tasks)==nil)
end)
test('ACTIVE and WARM shared windows never close',function()
  for _,state in ipairs({'ACTIVE','WARM'}) do local c,a,store,w,calls=fixture(state)
    c:close(cfg.workflows.one,store.data.workflows.one); assert(#calls==0 and #live==1 and next(c.records)==nil)
  end
end)
test('no descriptor and failed persistence preserve window',function()
  local c,a,store,w,calls=fixture(); c.bindings={}; c:close(cfg.workflows.one,store.data.workflows.one); assert(#calls==0)
  c,a,store,w,calls=fixture(); store.fail=true; c:close(cfg.workflows.one,store.data.workflows.one); assert(#calls==1 and #live==1 and next(c.records)==nil)
end)
test('dirty editors and terminals preserve windows',function()
  for _,field in ipairs({'dirty','terminals'}) do local c,a,store=fixture(); local closed=false
    c.bridge.request=function(_,_,action,_,_,done) assert(action~='close'); local r={descriptor=descriptor,dirty=false,terminals=0}; r[field]=field=='dirty' and true or 1; done(r) end
    c:close(cfg.workflows.one,store.data.workflows.one); assert(#live==1 and next(c.records)==nil)
  end
end)
test('unconfirmed graceful close never becomes a reopenable record',function()
  local c,a,store=fixture()
  c.bridge.request=function(_,_,action,_,_,done) if action=='close' then done({accepted=true}) else done({descriptor=descriptor,dirty=false,terminals=0}) end end
  c:close(cfg.workflows.one,store.data.workflows.one); flush(); assert(c.records['logical-test'].state=='close_uncertain' and #live==1)
end)
test('confirmed cold record reopens and binds new runtime ID',function()
  local c,a,store,w=fixture(); c:close(cfg.workflows.one,store.data.workflows.one); flush()
  local new=win(500); local ctx={valid=function() return true end,onCancel=function() end}
  function ctx:task(path,args,done) assert(args[1]=='--new-window' and args[2]=='/safe/project'); launched=launched+1; live={new};focused=new;done(0,'','') end
  function ctx:wait(_,predicate,done) done(predicate()) end
  c.bridge.request=function(_,_,action,_,_,done) assert(action=='probe');done({session='new',descriptor=descriptor}) end
  local errors; c:reopen(cfg.workflows.one,ctx,function(e) errors=e end)
  assert(launched==1 and #errors==0 and a.members.one['100:500']==new and next(c.records)==nil)
end)
test('user closure cannot create cold restore intent',function()
  local c,a,store,w=fixture(); c:destroyed(w); live={}; a.dead['100:142']=true
  assert(next(c.records)==nil); c:reopen(cfg.workflows.one,{valid=function() return true end},function(errors) assert(#errors==0) end); assert(launched==0)
end)
test('reload discards experimental close intents',function()
  local c,a,store=fixture(); c:close(cfg.workflows.one,store.data.workflows.one); flush()
  local r=c.records['logical-test']; r.runtimeID=142; r.layout={frame={x=0,y=0,w=1,h=1},windowID=142,pid=100}
  local d=State.sanitize(store.data,cfg); assert(d.shared.vscodeCold==nil and State.persistable(store.data).shared.vscodeCold==nil)
  local fresh={members={},dead={}}; assert(next(Cold.new(fresh,{data=d},identity).bindings)==nil)
end)
test('unmapped live window defers reopen rather than duplicates',function()
  local c,a,store,w=fixture(); c:close(cfg.workflows.one,store.data.workflows.one); flush(); live={win(999)}
  c:reopen(cfg.workflows.one,{valid=function() return true end},function(errors) assert(#errors==1) end); assert(launched==0)
end)
test('cancelled close intent cannot classify a later user close as WARP closure',function()
  local c,a,store,w=fixture()
  c.bridge.request=function(_,_,action,_,_,done) if action=='inspect' then done({descriptor=descriptor,dirty=false,terminals=0}) end end
  c:close(cfg.workflows.one,store.data.workflows.one); assert(next(c.pending))
  c:stop(); assert(next(c.pending)==nil and c.records['logical-test'].state=='close_uncertain')
  c:destroyed(w); assert(c.records['logical-test'].state=='close_uncertain')
end)
test('verified existing matching window is reused without CLI launch',function()
  local c,a,store=fixture(); c:close(cfg.workflows.one,store.data.workflows.one); flush()
  local new=win(777); live={new}; c.bindings['100:777']={session='new',descriptor=descriptor}
  c:reopen(cfg.workflows.one,{valid=function() return true end},function(errors) assert(#errors==0) end)
  assert(a.members.one['100:777']==new and launched==0 and next(c.records)==nil)
end)
test('stop cancels temporary requests; lifecycle 30 minute boundary calls cold',function()
  local c,a,store=fixture(); c.bridge.request=function() end; c:learn(focused); assert(next(c.tasks)); c:stop(); assert(next(c.tasks)==nil)
  local callback; hs.timer.doEvery=function(_,fn) callback=fn; return {stop=function() end} end
  store.data.workflows.one.lifecycle='WARM';store.data.workflows.one.lastActive=0
  local count=0;local manager={config=cfg,store=store,makeCold=function(_,id) count=count+1; assert(id=='one') end}
  local timer=require('warp.lifecycle').new(manager); now=1799;callback();assert(count==0);now=1800;callback();assert(count==1);timer:stop()
end)
print('PASS: '..total..' cold/descriptor tests; no live Code close performed')
