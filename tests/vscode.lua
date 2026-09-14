package.path='./src/?.lua;'..package.path
local C=require('warp.config')
local State=require('warp.state')
local W=require('warp.windows')
local A=require('warp.adapters.vscode')
local R=require('warp.request')
local U=require('warp.util')
local cfg=assert(C.validate({one={label='One',key='1'},two={label='Two',key='2'}}))
local total=0
local function test(name,fn) fn();total=total+1;print('PASS: '..name) end
local function fixture()
  local f={now=0,timers={},live={},actions={}}
  local screen={getUUID=function() return 'screen' end}
  function f:window(id,minimized,full)
    local w={number=id,minimized=minimized or false,full=full or false,rect={x=23,y=44,w=1440,h=900}}
    function w:id() if not self.closed then return self.number end end
    function w:application() return {pid=function() return 10 end,bundleID=function() return 'com.microsoft.VSCode' end} end
    function w:title() return 'Code '..id end
    function w:isMinimized() return self.minimized end
    function w:isFullScreen() return self.full end
    function w:frame() return U.copy(self.rect) end
    function w:screen() return screen end
    local function action(name) f.actions[#f.actions+1]=id..':'..name end
    function w:minimize() action('minimize');if not self.ignore then self.minimized=true end end
    function w:unminimize() action('unminimize');if not self.ignore then self.minimized=false end end
    function w:setFrame(r) action('frame');if self.throw then error('frame failed') end;if not self.ignore then self.rect=U.copy(r) end end
    function w:setFullScreen(value)
      action(value and 'fullscreen' or 'exit-fullscreen')
      if self.ignore then return end
      if self.fullDelay then hs.timer.doAfter(self.fullDelay,function() self.full=value end)
      else self.full=value end
    end
    function w:close() error('no closes') end
    f.live[#f.live+1]=w
    if f.a then f.a.resources.bindings['10:'..id]={session='s'..id,descriptor={kind='folder',path='/project/'..id}} end
    return w
  end
  hs={timer={secondsSinceEpoch=function() return f.now end,doAfter=function(delay,fn)
    local t={at=f.now+delay,fn=fn,stop=function(self) self.stopped=true end};f.timers[#f.timers+1]=t;return t
  end},window={filter={new=function() error('no adoption watcher') end}},application={get=function() error('no app-wide operations') end}}
  W.list=function(adapter) assert(adapter=='vscode');return f.live end
  f.a=A.new(cfg)
  f.a.prepare=function(_,_,done) done() end
  f.a.resources.reopen=function(_,_,descriptor,done)
    f.reopens=(f.reopens or 0)+1
    local w=f:window(100+f.reopens)
    f.a.resources.bindings['10:'..w.number]={session='new',descriptor=descriptor};done(w)
  end
  function f:run()
    for _=1,200 do
      table.sort(self.timers,function(a,b) return a.at<b.at end)
      local t=table.remove(self.timers,1);if not t then return end
      if not t.stopped then self.now=t.at;t.fn() end
    end
    error('unbounded timers')
  end
  function f:restore(id)
    self.ok=nil;self.calls=0;self.ctx=R.new(1,function() return 1 end,error)
    self.a:restore(cfg.workflows[id],{},self.ctx,function(ok,why) self.ok=ok;self.why=why;self.calls=self.calls+1 end)
  end
  return f
end
test('first use exposes normal candidates and preserves fullscreen without configuring',function()
  local f=fixture();f:window(1);f:window(2,true);f:window(3,false,true)
  f:restore('one');f:run();assert(f.ok and #f.actions==2 and not f.live[2].minimized and f.live[3].full and not f.a.configured.one and not f.a.snapshots.one and #f.timers==0)
end)
test('capture includes all windows with independent pixel frames and monitor ID',function()
  local f=fixture();local w=f:window(1);f:window(2,true);f:window(3,false,true)
  f.a:checkpoint(cfg.workflows.one);local s=f.a.snapshots.one
  assert(s['folder:/project/1'].windowId==1 and s['folder:/project/1'].frame.x==23 and s['folder:/project/1'].screen=='screen' and s['folder:/project/2'].minimized and s['folder:/project/3'].fullscreen)
  w.rect.x=100;assert(s['folder:/project/1'].frame.x==23 and #f.actions==0)
end)
test('visible snapshot unminimizes and restores exact frame',function()
  local f=fixture();local w=f:window(1);f.a:checkpoint(cfg.workflows.one)
  w.rect={x=100,y=100,w=700,h=500};w.minimized=true
  f:restore('one');f:run();assert(f.ok and not w.minimized and w.rect.x==23 and w.rect.w==1440)
  assert(table.concat(f.actions,',')=='1:unminimize,1:frame')
end)
test('minimized snapshot restores frame before minimizing',function()
  local f=fixture();local w=f:window(1,true);f.a:checkpoint(cfg.workflows.one)
  w.rect={x=100,y=100,w=700,h=500};w.minimized=false
  f:restore('one');f:run();assert(f.ok and w.minimized and w.rect.x==23 and w.rect.w==1440)
  assert(table.concat(f.actions,',')=='1:unminimize,1:frame,1:minimize')
end)
test('native fullscreen preserved both in and absent from snapshot',function()
  local f=fixture();f:window(1,false,true);f.a:checkpoint(cfg.workflows.one);f:window(2,false,true)
  f:restore('one');f:run();assert(f.ok and #f.actions==0)
end)
test('relevant fullscreen resource enters fullscreen without tearing down existing Spaces',function()
  local f=fixture();local w=f:window(1,false,true);f.a:checkpoint(cfg.workflows.one);w.full=false
  f:restore('one');f:run();assert(f.ok and w.full)
  f.actions={};f:restore('one');assert(f.ok and #f.actions==0)
end)
test('live normal absent from existing snapshot minimizes without closing',function()
  local f=fixture();f.a:checkpoint(cfg.workflows.one);local w=f:window(1)
  f:restore('one');f:run();assert(f.ok and w.minimized and not w.closed and #f.actions==1)
end)
test('closing in another workflow retains descriptor relevance and reopens visible resource',function()
  local f=fixture();local w=f:window(1);f.a:checkpoint(cfg.workflows.one)
  f.live={};w.closed=true;f.a:checkpoint(cfg.workflows.two)
  assert(f.a.configured.two and not next(f.a.snapshots.two) and f.a.snapshots.one['folder:/project/1'])
  f:restore('one');assert(f.ok and f.reopens==1 and f.live[1].number~=1 and f.live[1].rect.x==23)
end)
test('missing minimized resource is retained but not reopened',function()
  local f=fixture();f:window(1,true);f.a:checkpoint(cfg.workflows.one);f.live={}
  f:restore('one');assert(f.ok and not f.reopens and f.a.snapshots.one['folder:/project/1'].minimized)
end)
test('missing fullscreen resource reopens then enters fullscreen',function()
  local f=fixture();f:window(1,false,true);f.a:checkpoint(cfg.workflows.one);f.live={}
  f:restore('one');assert(f.ok and f.reopens==1 and f.live[1].full)
end)
test('descriptor is independent of runtime ID and shared across workflows',function()
  local f=fixture();local w=f:window(1);f.a:checkpoint(cfg.workflows.one);w.minimized=true;f.a:checkpoint(cfg.workflows.two)
  f.live={};local replacement=f:window(77);f.a.resources.bindings['10:77'].descriptor={kind='folder',path='/project/1'}
  f:restore('two');assert(f.ok and replacement.minimized and not f.reopens)
  f:restore('one');assert(f.ok and not replacement.minimized)
end)
test('unknown closed runtime fallback never guesses a reopen path',function()
  local f=fixture();f:window(1);f.a.resources.bindings={};f.a:checkpoint(cfg.workflows.one);f.live={}
  f:restore('one');assert(f.ok and not next(f.a.snapshots.one) and not f.reopens)
end)
test('same live window has independent state in each workflow including GENERAL',function()
  local f=fixture();local w=f:window(1);f.a:checkpoint(cfg.workflows.one)
  w.rect.x=100;f.a:checkpoint(cfg.workflows.two)
  w.minimized=true;f.a:checkpoint(cfg.workflows.general)
  f:restore('one');assert(f.ok and w.rect.x==23 and not w.minimized)
  f:restore('two');assert(f.ok and w.rect.x==100 and not w.minimized)
  f:restore('general');assert(f.ok and w.rect.x==100 and w.minimized)
end)
test('ignored state changes fail bounded verification without reporting success',function()
  local f=fixture();local w=f:window(1);f.a:checkpoint(cfg.workflows.one);w.minimized=true;w.ignore=true
  f:restore('one');assert(f.ok==nil);f:run();assert(f.ok==false and f.calls==1 and f.now>=0.75 and f.now<0.81)
end)
test('delayed native state can satisfy short verification poll',function()
  local f=fixture();local w=f:window(1);f.a:checkpoint(cfg.workflows.one);w.minimized=true;w.ignore=true
  f:restore('one');hs.timer.doAfter(0.2,function() w.minimized=false end);f:run();assert(f.ok and f.now<0.3)
end)
test('one window error does not prevent remaining windows restoring',function()
  local f=fixture();local a=f:window(1);local b=f:window(2);f.a:checkpoint(cfg.workflows.one)
  a.throw=true;b.minimized=true;f:restore('one');f:run();assert(f.ok==false and not b.minimized)
end)
test('request cancellation stops verification without late completion',function()
  local f=fixture();local w=f:window(1);f.a:checkpoint(cfg.workflows.one);w.ignore=true;w.minimized=true
  f:restore('one');f.ctx:cancel();f:run();assert(f.calls==0 and not next(f.ctx.timers))
end)
test('reload/new adapter is empty and has no ownership qualification hooks',function()
  local f=fixture();f:window(1);f.a:checkpoint(cfg.workflows.one);f.a:stop();local a=A.new(cfg)
  assert(not next(a.snapshots) and not a.focus and not a.owns and not a.members and #f.timers==0 and #f.actions==0)
end)
test('failed enumeration preserves last snapshot rather than fabricating empty state',function()
  local f=fixture();f:window(1);f.a:checkpoint(cfg.workflows.one);W.list=function() error('AX unavailable') end
  assert(not pcall(function() f.a:checkpoint(cfg.workflows.one) end));assert(f.a.snapshots.one['folder:/project/1'])
end)
test('explicit opt-out skips capture and restore',function()
  local f=fixture();f:window(1);local w={id='off',vscode=false}
  f.a:checkpoint(w);f.a:restore(w,{},R.new(1,function() return 1 end,error),function(ok) assert(ok) end)
  assert(not f.a.snapshots.off and #f.actions==0)
end)
test('diagnostics expose configured-empty separately from unconfigured and return copies',function()
  local f=fixture();f.a:checkpoint(cfg.workflows.one)
  local d=f.a:debug();assert(d.configured.one==true and not d.configured.two and not next(d.resources.one))
  d.configured.one=false;d.resources.one.fake={};assert(f.a.configured.one and not next(f.a.snapshots.one))
end)
-- Native fullscreen changes are asynchronous; target presentation wins.
for _,transition in ipairs({
  {'fullscreen','minimized'}, {'fullscreen','normal'},
  {'normal','fullscreen'}, {'minimized','fullscreen'},
  {'normal','minimized'}, {'minimized','normal'},
}) do
  test(transition[1]..' -> '..transition[2]..' respects target presentation and ordering',function()
    local f=fixture();local from,target=transition[1],transition[2]
    local w=f:window(1,target=='minimized',target=='fullscreen')
    f.a:checkpoint(cfg.workflows.one)
    w.full=from=='fullscreen';w.minimized=from=='minimized';w.rect.x=999;w.fullDelay=0.2
    f:restore('one')
    if from=='fullscreen' then
      assert(table.concat(f.actions,',')=='1:exit-fullscreen' and f.ok==nil and w.rect.x==999)
      hs.timer.doAfter(0.1,function() assert(#f.actions==1 and w.full and w.rect.x==999) end)
    elseif target=='fullscreen' then
      assert(table.concat(f.actions,',')=='1:unminimize,1:fullscreen' and f.ok==nil and not w.minimized)
    end
    f:run();assert(f.ok and f.calls==1 and w.full==(target=='fullscreen') and w.minimized==(target=='minimized'))
    if target~='fullscreen' then
      assert(w.rect.x==23)
      local expected='1:unminimize,1:frame'..(target=='minimized' and ',1:minimize' or '')
      assert(table.concat(f.actions,',')==(from=='fullscreen' and '1:exit-fullscreen,' or '')..expected)
    end
    assert(f.a.snapshots.one['folder:/project/1'].descriptor.path=='/project/1' and not f.reopens)
  end)
end
test('GENERAL -> SOFT -> GENERAL -> SOFT retains identity and independent presentation',function()
  local f=fixture();local w=f:window(1,true)
  f.a:checkpoint(cfg.workflows.general)
  w.minimized=false;w.full=true;f.a:checkpoint(cfg.workflows.one)
  w.fullDelay=0.2
  for _,target in ipairs({'general','one','general','one'}) do
    f:restore(target);f:run();assert(f.ok)
    assert(w.full==(target=='one') and w.minimized==(target=='general'))
    f.a:checkpoint(cfg.workflows[target])
    assert(f.a.resources.bindings['10:1'].descriptor.path=='/project/1' and not f.reopens)
  end
  assert(f.a.snapshots.general['folder:/project/1'].minimized and f.a.snapshots.one['folder:/project/1'].fullscreen)
end)
for _,entering in ipairs({false,true}) do
  test('fullscreen '..(entering and 'entry' or 'exit')..' timeout is isolated and bounded',function()
    local f=fixture();local w=f:window(1,false,entering);local other=f:window(2)
    f.a:checkpoint(cfg.workflows.one);w.full=not entering;w.ignore=true;other.minimized=true
    f:restore('one');f:run()
    assert(f.ok==false and f.calls==1 and f.now>=2 and f.now<2.1 and not other.minimized)
    for _,action in ipairs(f.actions) do assert(action~='1:frame' and action~='1:minimize') end
  end)
end
test('cancelled fullscreen exit never applies frame or minimizes later',function()
  local f=fixture();local w=f:window(1,true);f.a:checkpoint(cfg.workflows.one)
  w.full=true;w.minimized=false;w.fullDelay=0.2
  f:restore('one');f.ctx:cancel();f:run()
  assert(f.calls==0 and table.concat(f.actions,',')=='1:exit-fullscreen')
end)
test('minimized fullscreen intent survives repeated GENERAL/SOFT capture and restore',function()
  local f=fixture();local w=f:window(1,false,true);local key='folder:/project/1'
  f.a:checkpoint(cfg.workflows.general)
  w.full=false;w.minimized=true;f.a:checkpoint(cfg.workflows.general)
  assert(f.a.snapshots.general[key].visibility=='minimized' and f.a.snapshots.general[key].restorePresentation=='fullscreen')
  w.minimized=false;w.full=true;f.a:checkpoint(cfg.workflows.one);w.fullDelay=0.2
  for _=1,4 do
    f:restore('general');assert(w.full);f.a:checkpoint(cfg.workflows.general)
    assert(f.a.snapshots.general[key].visibility=='minimized')
    f:run();assert(f.ok and w.minimized and not w.full)
    f.a:checkpoint(cfg.workflows.general)
    assert(f.a.snapshots.general[key].restorePresentation=='fullscreen')
    f:restore('one');f:run();assert(f.ok and w.full and not w.minimized)
    f.a:checkpoint(cfg.workflows.one)
    assert(f.a.snapshots.one[key].restorePresentation=='fullscreen' and not f.reopens)
  end
end)
test('normal minimized intent stays independent from another workflow fullscreen intent',function()
  local f=fixture();local w=f:window(1,true);local key='folder:/project/1'
  f.a:checkpoint(cfg.workflows.general);w.minimized=false;w.full=true;f.a:checkpoint(cfg.workflows.one)
  f:restore('general');f:run();f.a:checkpoint(cfg.workflows.general)
  assert(f.ok and w.minimized and f.a.snapshots.general[key].restorePresentation=='normal')
  w.minimized=false;f.a:checkpoint(cfg.workflows.general);f.actions={}
  f:restore('general');f:run();assert(f.ok and not w.full)
  for _,a in ipairs(f.actions) do assert(a~='1:fullscreen') end
end)
test('genuine visible normal curation replaces fullscreen intent',function()
  local f=fixture();local w=f:window(1,false,true);f.a:checkpoint(cfg.workflows.one)
  w.full=false;w.rect.x=81;f.a:checkpoint(cfg.workflows.one)
  local saved=f.a.snapshots.one['folder:/project/1']
  assert(saved.restorePresentation=='normal' and saved.visibility=='visible' and saved.frame.x==81)
end)
test('fullscreen entry waits for asynchronous unminimize',function()
  local f=fixture();local w=f:window(1,false,true);f.a:checkpoint(cfg.workflows.one)
  w.full=false;w.minimized=true
  function w:unminimize() hs.timer.doAfter(0.2,function() self.minimized=false end) end
  local enter=w.setFullScreen
  function w:setFullScreen(value) assert(not self.minimized);enter(self,value) end
  f:restore('one');assert(#f.actions==0 and f.ok==nil)
  f:run();assert(f.ok and w.full and f.now>=0.2)
end)
test('cancelled intermediate normal state does not contaminate same-workflow capture',function()
  local f=fixture();local w=f:window(1,false,true);local key='folder:/project/1'
  f.a:checkpoint(cfg.workflows.one)
  local saved=f.a.snapshots.one[key];saved.visibility='minimized';saved.minimized=true
  w.fullDelay=0.2;f:restore('one');f.ctx:cancel();f:run()
  assert(not w.full and not w.minimized)
  f.a:checkpoint(cfg.workflows.one)
  assert(f.a.snapshots.one[key].visibility=='minimized' and f.a.snapshots.one[key].restorePresentation=='fullscreen')
  f:restore('one');f:run();assert(f.ok and w.minimized)
end)
test('missing minimized fullscreen-intent resource never reopens',function()
  local f=fixture();local w=f:window(1,false,true);f.a:checkpoint(cfg.workflows.one)
  w.full=false;w.minimized=true;f.a:checkpoint(cfg.workflows.one);f.live={}
  f:restore('one');assert(f.ok and not f.reopens)
end)
test('three-window fullscreen entry and exit transitions are serialized',function()
  local f=fixture();local a=f:window(1,false,true);local b=f:window(2,false,true);local c=f:window(3,false,true)
  f.a:checkpoint(cfg.workflows.general)
  local key='folder:/project/3';f.a.snapshots.general[key].visibility='minimized';f.a.snapshots.general[key].minimized=true
  a.full=false;a.minimized=true;b.full=false;b.minimized=true
  local active,started=0,0
  for _,w in ipairs({a,b,c}) do
    function w:setFullScreen(value)
      assert(active==0,'overlapping fullscreen transitions')
      active=active+1;started=started+1
      hs.timer.doAfter(0.2,function() self.full=value;active=active-1 end)
    end
  end
  f:restore('general');assert(started==1)
  f:run();assert(f.ok and started==3 and a.full and b.full and c.minimized and not c.full)
  f.a.snapshots.one=U.copy(f.a.snapshots.general);f.a.configured.one=true
  for key,saved in pairs(f.a.snapshots.one) do
    saved.visibility=key=='folder:/project/3' and 'visible' or 'minimized'
    saved.minimized=saved.visibility=='minimized'
  end
  for _=1,3 do
    f:restore('one');f:run();assert(f.ok and a.minimized and b.minimized and c.full)
    f:restore('general');f:run();assert(f.ok and a.full and b.full and c.minimized)
  end
  assert(started==21 and not f.reopens)
end)
test('cancellation discards remaining fullscreen queue and preserves queued target capture',function()
  local f=fixture();local started=0
  for id=1,3 do
    local w=f:window(id,false,true)
    function w:setFullScreen(value) started=started+1;hs.timer.doAfter(0.2,function() self.full=value end) end
  end
  f.a:checkpoint(cfg.workflows.one)
  for _,w in ipairs(f.live) do w.full=false;w.minimized=true end
  f:restore('one');assert(started==1);f.ctx:cancel();f:run()
  assert(started==1 and f.calls==0)
  f.a:checkpoint(cfg.workflows.one)
  for _,saved in pairs(f.a.snapshots.one) do assert(saved.visibility=='visible' and saved.restorePresentation=='fullscreen') end
end)
test('failed queued transition reports failure and permits following resource',function()
  local f=fixture();local a=f:window(1,false,true);local b=f:window(2,false,true)
  f.a:checkpoint(cfg.workflows.one);a.full=false;b.full=false;a.ignore=true
  f:restore('one');f:run();assert(f.ok==false and f.calls==1 and b.full)
end)
test('configured capture merges closed resources and preserves independent workflow presentation',function()
  local f=fixture();local w=f:window(1,false,true);f:window(2);local key='folder:/project/1'
  f.a:checkpoint(cfg.workflows.general)
  w.full=false;w.minimized=true;f.a:checkpoint(cfg.workflows.one)
  f.live={f.live[2]};w.closed=true
  f.a:checkpoint(cfg.workflows.one);f.a:checkpoint(cfg.workflows.general)
  assert(f.a.snapshots.general[key].visibility=='visible' and f.a.snapshots.general[key].restorePresentation=='fullscreen')
  assert(f.a.snapshots.one[key].visibility=='minimized' and f.a.snapshots.one[key].restorePresentation=='fullscreen')
  assert(f.a.snapshots.general['folder:/project/2'])
  f:restore('one');f:run();assert(f.ok and not f.reopens)
  f:restore('general');f:run();assert(f.ok and f.reopens==1 and f.live[2].number~=1 and f.live[2].full)
  assert(f.a.snapshots.one[key].visibility=='minimized')
end)
test('first curation does not inherit closed historical resources',function()
  local f=fixture();f:window(1);f.a:checkpoint(cfg.workflows.general);f.live={}
  f.a:checkpoint(cfg.workflows.one);assert(not next(f.a.snapshots.one))
end)
test('reopen failure preserves configured resources across later capture',function()
  local f=fixture();f:window(1,false,true);f.a:checkpoint(cfg.workflows.one);f.live={}
  f.a.resources.reopen=function(_,_,_,done) done(nil,'companion response timed out') end
  f:restore('one');f:run();assert(f.ok==false)
  f.a:checkpoint(cfg.workflows.one)
  assert(f.a.snapshots.one['folder:/project/1'].restorePresentation=='fullscreen')
end)
-- Exercise real manager ordering/checkpoints with the real Code adapter.
test('manager captures departure, curates first visits, and never overwrites inactive snapshots during COLD',function()
  local f=fixture();local w=f:window(1);local sequence={}
  package.loaded['warp.state']={new=function(c) return {data=State.sanitize({version=1,workflows={}},c),save=function() end} end}
  package.loaded['warp.spaces']={rebuild=function() return {} end,primary=function() return true end}
  for _,name in ipairs{'finder','safari','terminal','figma','docker'} do
    package.loaded['warp.adapters.'..name]={new=function() return {id=name,discover=function() return {} end,restore=function(_,target,_,_,done)
      sequence[#sequence+1]=name..':'..target.id
      if name=='safari' and target.id=='general' then assert(target.safari.tabGroup=='Local') end
      done(name~='finder','Finder isolated error')
    end} end}
  end
  hs.accessibilityState=function() return true end;cfg.settings.notifications=false
  local m=require('warp.manager').new(cfg)
  m.vscode=f.a;m.adapters[1]=f.a
  assert(m.store.data.active=='general' and not next(m.vscode.snapshots) and #f.actions==0)
  assert(m.adapters[1].id=='vscode' and m.adapters[2].id=='finder' and m.adapters[3].id=='safari')
  m:switchTo('one');f:run();assert(not m.vscode.snapshots.one and m.vscode.snapshots.general['folder:/project/1'] and #f.actions==1)
  m:checkpoint('one');assert(not m.vscode.snapshots.one)
  w.minimized=true;w.rect.x=100;m:switchTo('two');f:run();assert(m.vscode.snapshots.one['folder:/project/1'].minimized and not m.vscode.snapshots.two)
  w.minimized=false;w.rect.x=200
  m:makeCold('one');assert(m.vscode.snapshots.one['folder:/project/1'].frame.x==100 and m.vscode.snapshots.one['folder:/project/1'].minimized)
  m:switchTo('one');f:run();assert(w.minimized and w.rect.x==100 and m.vscode.snapshots.two['folder:/project/1'].frame.x==200)
  m:switchTo('general');f:run();assert(not w.minimized and w.rect.x==23 and not m.switching)
  assert(sequence[1]=='finder:one' and sequence[2]=='safari:one' and #m.errors==1)
  m:stop();assert(not next(m.vscode.snapshots))
end)
test('reload startup curates GENERAL without capturing it and still invokes Finder/Safari',function()
  local f=fixture();local normal=f:window(1,true);local full=f:window(2,false,true)
  local starts={}
  W.start=function() end
  package.loaded['warp.wheel']={new=function() return {start=function() end,stop=function() end} end}
  package.loaded['warp.lifecycle']={new=function() return {stop=function() end} end}
  hs.screen={watcher={new=function() return {start=function(self) return self end,stop=function() end} end}}
  hs.menubar={new=function() return nil end};hs.alert={show=function() end};hs.accessibilityState=function() return true end
  cfg.settings.navigation=false
  local m=require('warp.manager').new(cfg);m.vscode=f.a;m.adapters[1]=f.a
  f.a.start=function() end -- descriptor watcher behavior is tested separately
  for _,a in ipairs(m.adapters) do if a.id=='finder' or a.id=='safari' then
    a.restore=function(self,w,_,_,done) starts[self.id]=w.id;done(true) end
  end end
  m:start();f:run()
  assert(m.store.data.active=='general' and not m.vscode.configured.general and not m.vscode.snapshots.general)
  assert(not normal.minimized and full.full and starts.finder=='general' and starts.safari=='general' and not m.switching)
  m:stop()
end)
print('PASS: '..total..' VS Code snapshot tests; no live GUI actions')
