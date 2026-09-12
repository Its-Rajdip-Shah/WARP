package.path='./src/?.lua;'..package.path
local total=0
local function test(name,fn) fn(); total=total+1; print('PASS: '..name) end
local U=require('warp.util')
local C=require('warp.config')
local function basic() return {one={label='One',key='1',vscode={allowedRoots={'~/One'}}},two={label='Two',key='2'}} end
local cfg=assert(C.validate(basic()))
for _,name in ipairs({'finder','safari','vscode','terminal','figma','docker'}) do assert(require('warp.adapters.'..name).new) end
local logs={}
hs={fs={attributes=function() return nil end},json={},timer={},application={},spaces={},screen={},window={},eventtap={}}
test('configuration: defaults, stable IDs, normalized roots',function() assert(cfg.list[1].id=='one'); assert(cfg.workflows.one.coldAfterMinutes==30); assert(cfg.workflows.one.vscode.allowedRoots[1]==os.getenv('HOME')..'/One') end)
test('configuration: empty list allowed',function() assert(#assert(C.validate({})).list==0) end)
test('configuration: duplicate number, nonnumeric, unknown global app rejected',function()
  local b=basic(); b.two.key='1'; assert(not C.validate(b)); b.two.key='C'; assert(not C.validate(b)); b=basic(); b.one.apps={{id='chatgpt'}}; assert(not C.validate(b))
end)
test('configuration: overlapping roots, bad paths, injected session, unsupported policies rejected',function()
  local b=basic(); b.two.vscode={allowedRoots={'~/One/sub'}}; assert(not C.validate(b))
  b=basic(); b.one.finder={leftRoot='relative'}; assert(not C.validate(b))
  b=basic(); b.one.terminal={tmuxSession='a; rm'}; assert(not C.validate(b))
  b=basic(); b.one.apps={{id='docker',cold='kill'}}; assert(not C.validate(b))
end)
test('configuration: duplicate tmux and chord collision rejected',function()
  local b=basic(); b.one.terminal={tmuxSession='same'}; b.two.terminal={tmuxSession='same'}; assert(not C.validate(b))
  assert(not C.validate(basic(),{navigation={mods={'ctrl','alt','cmd'},next='right',previous='left'}}))
end)
test('path ownership uses boundaries, never basename',function()
  local O=require('warp.ownership'); assert(O.owner(cfg,os.getenv('HOME')..'/One/project')=='one'); assert(O.owner(cfg,os.getenv('HOME')..'/OneElse')==nil)
  assert(O.vscodePath({title=function() return 'project — Code' end})==nil)
  assert(O.vscodePath({title=function() return '[WARP:/tmp/space project] — file' end})=='/tmp/space project')
end)
test('shell and AppleScript quoting',function() assert(U.quote("a'b") == "'a'\\''b'"); assert(U.as('a"b\\c')=='"a\\"b\\\\c"') end)
local State=require('warp.state')
test('state recovery: one ACTIVE, stale window/Space IDs discarded',function()
  local d=State.sanitize({version=1,active='two',workflows={one={lifecycle='ACTIVE',windows={a={adapter='vscode',identity='/tmp/a',windowID=12,spaceIDs={5}}}},two={lifecycle='ACTIVE'}}},cfg)
  assert(d.workflows.one.lifecycle=='WARM' and d.workflows.two.lifecycle=='ACTIVE'); assert(not d.workflows.one.windows.a.windowID and #d.workflows.one.spaces==0)
end)
test('invalid state schema/frames rejected',function()
  assert(not pcall(State.sanitize,{version=2},cfg))
  assert(not pcall(State.sanitize,{version=1,workflows={one={windows={a={adapter='vscode',identity='a',frame={x=0,y=0,w=-1,h=1}}}}}},cfg))
end)
test('corrupt state is not overwritten',function()
  hs.fs.attributes=function() return 'file' end; hs.json.read=function() error('bad JSON') end
  local store=State.new(cfg); assert(not store.writable); assert(not store:save()); hs.fs.attributes=function() return nil end
end)
test('lifecycle threshold, active immunity and pins',function()
  local L=require('warp.lifecycle'); local w={coldAfterMinutes=30}; local s={lifecycle='WARM',lastActive=0}
  assert(not L.due(w,s,1799)); assert(L.due(w,s,1800)); s.pinned=true; assert(not L.due(w,s,1801)); s.pinned=false; s.lifecycle='ACTIVE'; assert(not L.due(w,s,9999))
end)
local now,timers=0,{}
hs.timer.secondsSinceEpoch=function() return now end
hs.timer.doAfter=function(delay,fn) local t={at=now+delay,fn=fn,stopped=false}; function t:stop() self.stopped=true end; timers[#timers+1]=t; return t end
local function flush(limit)
  for _=1,limit or 100 do
    table.sort(timers,function(a,b) return a.at<b.at end); local t=table.remove(timers,1); if not t then return end
    if not t.stopped then now=t.at; t.fn() end
  end
  error('timer loop did not settle')
end
local R=require('warp.request')
test('newest request wins and cancellation stops timers',function()
  local generation=1; local hits=0; local r=R.new(1,function() return generation end,error)
  r:after(1,function() hits=hits+1 end); generation=2; flush(); assert(hits==0)
  r=R.new(2,function() return generation end,error); r:after(1,function() hits=hits+1 end); r:cancel(); flush(); assert(hits==0 and next(r.timers)==nil)
end)
test('bounded wait times out and cleans timers',function()
  local result; local r=R.new(1,function() return 1 end,error)
  r:wait('test',function() return false end,function(ok) result=ok end,0.5); flush(); assert(result==false and next(r.timers)==nil)
end)
test('adapter callback exceptions are contained',function()
  local err; local r=R.new(1,function() return 1 end,function(e) err=e end); r:after(0,function() error('adapter failure') end); flush(); assert(err:find('adapter failure',1,true))
end)
test('screen fallback clamps frames inside available display',function()
  local screen={getUUID=function() return 'main' end,frame=function() return {x=100,y=20,w=1000,h=700} end}
  hs.screen.allScreens=function() return {screen} end; hs.screen.mainScreen=function() return screen end
  local saved; local win={moveToScreen=function() end,setFrame=function(_,f) saved=f end}
  require('warp.screens').restore(win,{x=2,y=-1,w=3,h=0.5},'missing')
  assert(saved.x==100 and saved.y==20 and saved.w==1000 and saved.h==350)
end)
test('wheel requires exact three modifiers (not shift)',function()
  local Wheel=require('warp.wheel'); assert(Wheel.held({ctrl=true,alt=true,cmd=true})); assert(not Wheel.held({ctrl=true,alt=true})); assert(not Wheel.held({ctrl=true,alt=true,cmd=true,shift=true}))
end)
test('workflow navigation filters destroyed Spaces and excludes other workflows',function()
  local visited; hs.spaces.allSpaces=function() return {display={11,12,99}} end; hs.spaces.focusedSpace=function() return 11 end
  hs.spaces.gotoSpace=function(id) visited=id; return true end
  assert(require('warp.spaces').navigate({{id=11},{id=12},{id=77}},1)); assert(visited==12)
end)
test('settings: navigation can be disabled',function() assert(assert(C.validate(basic(),{navigation=false})).settings.navigation==false) end)
test('state atomic save and failed write preserve previous file',function()
  local path=os.tmpname(); os.remove(path); local dir=path..'-dir'; assert(os.execute('mkdir '..U.quote(dir)))
  local c=assert(C.validate(basic(),{stateDirectory=dir}))
  hs.fs.attributes=function(p) if p==dir then return 'directory' end end
  hs.json.encode=function() return 'complete-state' end
  local store=State.new(c); assert(store:save())
  local f=assert(io.open(store.path)); assert(f:read('*a')=='complete-state'); f:close()
  hs.json.encode=function() error('encoding failure') end; assert(not store:save())
  f=assert(io.open(store.path)); assert(f:read('*a')=='complete-state'); f:close()
  os.remove(store.path); assert(os.execute('rmdir '..U.quote(dir)))
  hs.fs.attributes=function() return nil end
end)
test('request helper timeout and cancellation never invoke stale callback',function()
  local helper, callback, hits
  hs.task={new=function(_,cb) callback=cb; helper={running=false}; function helper:start() self.running=true; return self end; function helper:isRunning() return self.running end; function helper:setCallback(cb2) callback=cb2 end; function helper:terminate() self.running=false end; return helper end}
  local r=R.new(1,function() return 1 end,error); hits=0
  r:task('/helper',{},function(code) assert(code==-1); hits=hits+1 end,0.5); flush(); assert(hits==1 and not helper.running and next(r.tasks)==nil)
  r=R.new(1,function() return 1 end,error); r:task('/helper',{},function() hits=hits+1 end); r:cancel(); assert(callback==nil); flush(); assert(hits==1)
end)
test('wheel interaction: selection, release, Escape, letters, cleanup, dynamic count',function()
  local taps,canvases={},{}
  hs.eventtap.event={types={keyDown=1,flagsChanged=2}}
  hs.eventtap.new=function(_,fn) local t={fn=fn}; function t:start() self.active=true; return self end; function t:stop() self.active=false end; taps[#taps+1]=t; return t end
  hs.keycodes={map={[1]='1',[2]='escape',[3]='c',[4]='9'}}
  hs.mouse={getCurrentScreen=function() return hs.screen.mainScreen() end}
  hs.canvas={windowLevels={overlay=1},new=function(frame)
    local c={frame=frame,elements={}}; for _,method in ipairs({'level','behavior','clickActivating','show'}) do c[method]=function(self) return self end end
    function c:appendElements(e) self.elements[#self.elements+1]=e; return self end
    function c:delete() self.deleted=true end; canvases[#canvases+1]=c; return c
  end}
  local selected; local wheel=require('warp.wheel').new(cfg,function(id) selected=id end); wheel:start()
  local flags={ctrl=true,alt=true,cmd=true}
  local function event(key) return {getFlags=function() return flags end,getKeyCode=function() return key end} end
  wheel.flagsTap.fn(event()); assert(wheel.visible and wheel.keyTap.active)
  assert(wheel.keyTap.fn(event(1))==true and selected=='one'); assert(not wheel.visible and not wheel.keyTap.active and canvases[1].deleted)
  wheel.flagsTap.fn(event()); assert(not wheel.visible)
  flags={}; wheel.flagsTap.fn(event()); flags={ctrl=true,alt=true,cmd=true}; wheel.flagsTap.fn(event())
  assert(wheel.keyTap.fn(event(3))==false and not wheel.visible) -- existing letter binding is untouched
  flags={}; wheel.flagsTap.fn(event()); flags={ctrl=true,alt=true,cmd=true}; wheel.flagsTap.fn(event()); assert(wheel.keyTap.fn(event(2))==true)
  flags={}; wheel.flagsTap.fn(event()); flags={ctrl=true,alt=true,cmd=true}; wheel.flagsTap.fn(event()); flags={ctrl=true}; wheel.flagsTap.fn(event()); assert(not wheel.visible)
  wheel:stop(); assert(not wheel.flagsTap.active and not wheel.keyTap.active)
  local many={}; for i=0,9 do many['w'..i]={label='Workflow '..i,key=tostring(i)} end
  wheel=require('warp.wheel').new(assert(C.validate(many)),function() end); wheel:show(); assert(#wheel.canvas.elements==33); wheel:stop()
  wheel=require('warp.wheel').new(assert(C.validate({})),function() end); wheel:show(); assert(not wheel.visible); wheel:stop()
end)
test('fullscreen restoration migrates displays and registers only new Space',function()
  local main={getUUID=function() return 'main' end,frame=function() return {x=0,y=0,w=1000,h=700} end}
  local external={getUUID=function() return 'external' end,frame=main.frame}
  hs.screen.allScreens=function() return {main,external} end; hs.screen.mainScreen=function() return main end
  local full,screen,space=true,main,51; local transitions={}
  local win={id=function() return 1 end,screen=function() return screen end,isFullScreen=function() return full end,unminimize=function() end,
    setFullScreen=function(_,value) full=value; space=value and 52 or 11; transitions[#transitions+1]=value end,
    moveToScreen=function(_,s) assert(not full); screen=s end,setFrame=function() end}
  hs.spaces.windowSpaces=function() return {space} end; hs.spaces.spaceType=function(id) return id==11 and 'user' or 'fullscreen' end
  local r=R.new(1,function() return 1 end,error); local complete
  require('warp.windows').restore(win,{fullscreen=true,screenUUID='external'},r,function(ok) complete=ok end); flush()
  assert(complete and screen==external and transitions[1]==false and transitions[2]==true and space==52)
  transitions={}; require('warp.windows').restore(win,{fullscreen=true,screenUUID='external'},r,function(ok) assert(ok) end); flush(); assert(#transitions==0)
end)

-- Manager integration with fake adapters and no live desktop calls.
local originalState=package.loaded['warp.state']
package.loaded['warp.state']={new=function(config) local store={data=State.sanitize({version=1,workflows={}},config)}; function store:save() return true end; return store end}
local restored={}
for _,name in ipairs({'safari','finder','vscode','terminal','figma','docker'}) do
  package.loaded['warp.adapters.'..name]={new=function() return {id=name,discover=function() return {} end,restore=function(_,w,_,ctx,done)
    ctx:after(0.5,function() restored[#restored+1]=w.id..':'..name; if name=='figma' then done(false,'unavailable') else done(true) end end)
  end,cold=function() end} end}
end
hs.accessibilityState=function() return true end
hs.spaces.spaceType=function() return 'user' end
hs.spaces.spacesForScreen=function() return {11} end
hs.notify={new=function() return {send=function() end} end}
test('manager rapid switch, partial failure, single ACTIVE and lifecycle',function()
  local m=require('warp.manager').new(cfg)
  assert(m:switchTo('one')); assert(m:switchTo('two')); flush()
  assert(m.store.data.active=='two' and not m.switching)
  assert(m.store.data.workflows.one.lifecycle=='WARM' and m.store.data.workflows.two.lifecycle=='ACTIVE')
  for _,v in ipairs(restored) do assert(v:sub(1,4)=='two:') end
  assert(#m.errors==1 and m.errors[1]:find('figma',1,true))
  assert(m:makeCold('one')); assert(m.store.data.workflows.one.lifecycle=='COLD'); assert(not m:makeCold('two'))
  m:stop(); assert(not m:switchTo('one')); flush()
end)
test('failed Finder restore continues the workflow without Mission Control fallback',function()
  local factory=package.loaded['warp.adapters.finder']
  package.loaded['warp.adapters.finder']={new=function() return {id='finder',discover=function() return {} end,restore=function(_,_,_,_,done) done(false,'Finder enumeration denied') end} end}
  local config=assert(C.validate({one={label='One',key='1',finder={leftRoot='/tmp'},primary='finder'}}))
  local gotoSpace=hs.spaces.gotoSpace; local jumps=0
  hs.spaces.gotoSpace=function() jumps=jumps+1; return true end
  restored={}
  local m=require('warp.manager').new(config); assert(m:switchTo('one')); flush()
  assert(m.store.data.active=='one' and not m.switching and jumps==0)
  local continued=false; for _,entry in ipairs(restored) do if entry=='one:docker' then continued=true end end
  assert(continued and m.errors[1]:find('Finder enumeration denied',1,true))
  m:stop(); hs.spaces.gotoSpace=gotoSpace; package.loaded['warp.adapters.finder']=factory
end)
test('manager start/stop cycles clean owned taps, filter, watcher, hotkeys and timer',function()
  local filters,watchers,keys,periodic,menus={},{},{},{},{}
  hs.window.filter={windowCreated='created',windowDestroyed='destroyed',new=function()
    local f={}; function f:subscribe() self.subscribed=true; return self end; function f:unsubscribeAll() self.subscribed=false end; function f:pause() self.paused=true end
    filters[#filters+1]=f; return f
  end}
  hs.screen.watcher={new=function(fn) local w={fn=fn}; function w:start() self.active=true; return self end; function w:stop() self.active=false end; watchers[#watchers+1]=w; return w end}
  hs.timer.doEvery=function(_,fn) local t={fn=fn}; function t:stop() self.stopped=true end; periodic[#periodic+1]=t; return t end
  hs.keycodes.map.right=10; hs.keycodes.map.left=11
  hs.hotkey={bind=function() local k={}; function k:delete() self.deleted=true end; keys[#keys+1]=k; return k end}
  hs.menubar={new=function() local m={}; function m:setTitle() return self end; function m:setMenu(fn) self.fn=fn; return self end; function m:delete() self.deleted=true end; menus[#menus+1]=m; return m end}
  hs.alert={show=function() end}
  for _=1,2 do
    local m=require('warp.manager').new(cfg); m:start(); assert(m.wheel.flagsTap.active); assert(#m.menu.fn()>0)
    m:stop(); m:stop(); assert(not m.wheel.flagsTap.active and not m.wheel.keyTap.active)
  end
  for _,f in ipairs(filters) do assert(f.paused and not f.subscribed) end
  for _,w in ipairs(watchers) do assert(not w.active) end
  for _,k in ipairs(keys) do assert(k.deleted) end
  for _,t in ipairs(periodic) do assert(t.stopped) end
  for _,m in ipairs(menus) do assert(m.deleted) end
  assert(#keys==4 and #filters==2 and #periodic==2)
end)
package.loaded['warp.state']=originalState
print('PASS: '..total..' behavioral tests; no live GUI actions')
