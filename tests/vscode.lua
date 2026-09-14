package.path='./src/?.lua;'..package.path
local C=require('warp.config')
local State=require('warp.state')
local cfg=assert(C.validate({one={label='One',key='1',vscode=true,primary='none'},two={label='Two',key='2',vscode={},primary='none'}}))
local total=0
local function test(name,fn) fn(); total=total+1; print('PASS: '..name) end
local active,focused,timers,filters,listed='one',nil,{},{},{}
local function win(id)
  local w={number=id,label='arbitrary title',minimized=false}
  function w:id() if not self.closed then return self.number end end
  function w:application() return {bundleID=function() return self.other and 'other' or 'com.microsoft.VSCode' end,pid=function() return 100 end} end
  function w:title() return self.label end
  function w:isFullScreen() return false end
  function w:isMinimized() return self.minimized end
  function w:minimize() self.minimized=true end
  return w
end
hs={window={focusedWindow=function() return focused end,filter={windowFocused='focus',windowUnfocused='unfocus',windowDestroyed='destroy',new=function()
  local f={callbacks={}}; function f:subscribe(event,fn) self.callbacks[event]=fn end
  function f:unsubscribeAll() self.callbacks={} end; function f:pause() self.paused=true end
  filters[#filters+1]=f; return f
end}},timer={doAfter=function(delay,fn) assert(delay==10); local t={fn=fn}; function t:stop() self.stopped=true end; timers[#timers+1]=t; return t end}}
local W=require('warp.windows'); W.list=function() return listed end
local function tick()
  while #timers>0 do local t=table.remove(timers,1); if not t.stopped then t.fn(); return end end
end
local function checks(n) for _=1,n do tick() end end
local function fixture()
  timers={}; active='one'; focused=nil; listed={}
  local a=require('warp.adapters.vscode').new(cfg); a:start(function() return active end); return a,win(142)
end
local function focus(a,w) focused=w; a.filter.callbacks.focus(w) end
local function qualify(a,w) focus(a,w); checks(6) end
test('focus starts one timer, six checks adopt, owned focus starts none',function()
  local a,w=fixture(); assert(#timers==0); focus(a,w); assert(a.candidate and #timers==1)
  checks(5); assert(not a:owns('one',w)); tick(); assert(a:owns('one',w) and not a.candidate and #timers==0)
  focus(a,w); assert(#timers==0); a:stop()
end)
test('failed checks 1 through 6 cancel without accumulating partial time',function()
  for failure=1,6 do local a,w=fixture(); focus(a,w); checks(failure-1); focused=win(99); tick()
    assert(not a.candidate and not a:owns('one',w) and #timers==0)
    qualify(a,w); assert(a:owns('one',w)); a:stop()
  end
end)
test('focus departure cancels immediately and replacing candidate restarts',function()
  local a,w=fixture(); focus(a,w); checks(3); a.filter.callbacks.unfocus(w); assert(not a.candidate)
  local b=win(2910); focus(a,b); checks(5); assert(not a:owns('one',b)); tick(); assert(a:owns('one',b) and not a:owns('one',w)); a:stop()
end)
test('workflow change, close and wrong app cancel qualification',function()
  for _,cause in ipairs({'workflow','close','app'}) do local a,w=fixture(); focus(a,w)
    if cause=='workflow' then active='two' elseif cause=='close' then w.closed=true else w.other=true end
    tick(); assert(not a.candidate and not a:owns('one',w)); a:stop()
  end
end)
test('membership survives focus loss, other apps, title/folder change and minimization',function()
  local a,w=fixture(); qualify(a,w); focused=nil; a.filter.callbacks.unfocus(w)
  w.label='a completely different workspace'; w.minimized=true
  a:checkpoint(cfg.workflows.one,{windows={}}); assert(a:owns('one',w)); assert(#a:discover(cfg.workflows.one)==1); a:stop()
end)
test('second workflow adds membership without stealing first',function()
  local a,w=fixture(); qualify(a,w); active='two'; qualify(a,w)
  assert(a:owns('one',w) and a:owns('two',w)); a:stop()
end)
test('checkpoint preserves absent hidden window; closure removes only checkpointed owner',function()
  local a,w=fixture(); qualify(a,w); active='two'; qualify(a,w); listed={}
  a:checkpoint(cfg.workflows.one,{windows={}}); assert(a:owns('one',w))
  a.filter.callbacks.destroy(w)
  local k='100:142'; local s={windows={['vscode:'..k]={}}}
  a:checkpoint(cfg.workflows.one,s); assert(a.members.one[k]==nil and a.members.two[k]==w and next(s.windows)==nil)
  a:checkpoint(cfg.workflows.two,{windows={}}); assert(a.members.two[k]==nil); a:stop()
end)
test('destroy event cancels candidate immediately',function()
  local a,w=fixture(); focus(a,w); a.filter.callbacks.destroy(w); assert(not a.candidate); checks(6); assert(not a:owns('one',w)); a:stop()
end)
test('stop/restart cleans watcher timer and runtime memberships',function()
  local a,w=fixture(); focus(a,w); local f=a.filter; a:stop(); assert(f.paused and next(f.callbacks)==nil and not a.candidate)
  checks(6); assert(next(a.members)==nil); focused=nil; a:start(function() return active end); assert(not a.candidate); a:stop()
end)
test('old root config ignored; obsolete VS Code state dropped before validation',function()
  local c=assert(C.validate({one={label='One',key='1',vscode={allowedRoots='bad old value',openRoots={'relative'}}}}))
  assert(c.workflows.one.vscode==true and #c.warnings==1)
  local d=State.sanitize({version=1,workflows={one={windows={['vscode:/old']='obsolete',x={adapter='vscode'},keep={adapter='terminal',identity='session'}}}}},cfg)
  assert(d.workflows.one.windows.x==nil and d.workflows.one.windows.keep)
  d.workflows.one.windows.runtime={adapter='vscode',identity='100:142'}
  assert(State.persistable(d).workflows.one.windows.runtime==nil and d.workflows.one.windows.runtime)
end)
test('uncertain window access preserves ownership, explicit invalid handle removes it',function()
  local a,w=fixture(); qualify(a,w); local method=w.application
  w.application=function() error('temporary AX failure') end
  a:checkpoint(cfg.workflows.one,{windows={}}); assert(a.members.one['100:142']==w)
  w.application=method; w.closed=true; a:checkpoint(cfg.workflows.one,{windows={}})
  assert(a.members.one['100:142']==nil); a:stop()
end)
test('destroyed runtime ID cannot donate old membership to a replacement',function()
  local a,w=fixture(); qualify(a,w); a.filter.callbacks.destroy(w)
  local replacement=win(142); focus(a,replacement); assert(not a:owns('one',replacement)); checks(6)
  assert(a:owns('one',replacement) and a.recycled['100:142']); a:stop()
end)
test('live destination restore uses generic windows without path reconstruction',function()
  local a,w=fixture(); qualify(a,w); local capture,restore=W.capture,W.restore; local hits=0
  W.capture=function() return {} end; W.restore=function(got,_,_,done) assert(got==w); hits=hits+1; done(true) end
  local completed; a:restore(cfg.workflows.one,{windows={}},{valid=function() return true end},function(ok) completed=ok end)
  assert(completed and hits==1); a:stop(); W.capture,W.restore=capture,restore
end)
test('one restore failure does not prevent other target windows restoring',function()
  local a,w=fixture(); qualify(a,w); local other=win(222); qualify(a,other)
  local capture,restore=W.capture,W.restore; local hits=0
  W.capture=function() return {} end
  W.restore=function(got,_,_,done) hits=hits+1; done(got==other,'test failure') end
  local result
  a:restore(cfg.workflows.one,{windows={}},{valid=function() return true end},function(ok) result=ok end)
  assert(result==false and hits==2);a:stop(); W.capture,W.restore=capture,restore
end)
-- Real manager and VS Code adapter; unrelated adapters/window geometry are inert mocks.
test('manager shared windows skip warm, source-only warm and destination restores',function()
  local a,w=fixture(); a:stop(); focused=nil; timers={}
  local source,shared=win(1),win(2)
  local capture,restore,warm=W.capture,W.restore,W.warm
  W.capture=function(_,adapter,id) return {adapter=adapter,identity=id} end
  local warmed,restored={},{}
  W.warm=function(got) warmed[got.number]=true end
  W.restore=function(got,_,_,done) restored[got.number]=true; done(true) end
  package.loaded['warp.state']={new=function() return {data=State.sanitize({version=1,workflows={}},cfg),save=function() end} end}
  package.loaded['warp.spaces']={rebuild=function() return {} end,primary=function() return true end}
  for _,name in ipairs({'safari','terminal','figma','docker'}) do package.loaded['warp.adapters.'..name]={new=function() return {id=name,discover=function() return {} end,restore=function(_,_,_,_,done) done(true) end} end} end
  hs.accessibilityState=function() return true end; hs.timer.secondsSinceEpoch=function() return 1 end
  hs.timer.doAfter=function(_,fn) local t={fn=fn}; function t:stop() self.stopped=true end; timers[#timers+1]=t; return t end
  local m=require('warp.manager').new(cfg); m.store.data.active='one'
  m.vscode.members={one={['100:1']=source,['100:2']=shared},two={['100:2']=shared}}
  assert(m:switchTo('two')); for _=1,20 do tick() end
  listed={source,shared,win(3)}
  assert(m:switchTo('two')); for _=1,20 do tick() end
  assert(source.minimized and not shared.minimized and listed[3].minimized and restored[2] and not m.switching)
  m:stop(); assert(not m.vscode.running and next(m.vscode.members)==nil); W.capture,W.restore,W.warm=capture,restore,warm
end)
print('PASS: '..total..' dynamic VS Code tests; no live GUI verification')
