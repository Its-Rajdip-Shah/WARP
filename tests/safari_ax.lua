package.path='./src/?.lua;'..package.path
local A=require('warp.safari_ax')
local R=require('warp.request')
local total=0
local function test(name,fn) fn();total=total+1;print('PASS: '..name) end
local function el(attrs)
  return {attributeValue=function(_,key) return attrs[key] end,performAction=function() return true end}
end
local function picker(group) return el{AXRole='AXMenuButton',AXIdentifier='TabGroupPickerButton?TabGroup='..group,AXDescription=''} end
local order={'Local','ENGG3112','ELEC2602','SOFT2201','SOFT2412','ELEC3609'}
local function menu(titles)
  local children={}
  for _,title in ipairs(titles) do children[#children+1]=el{AXRole='AXMenuItem',AXTitle=title} end
  return el{AXChildren=children}
end
test('empty picker value means Local',function() assert(A.currentFromPicker(picker(''))=='Local') end)
test('named picker value retained',function() assert(A.currentFromPicker(picker('ELEC3609'))=='ELEC3609') end)
test('empty description does not prevent discovery',function() local p=picker('');assert(A.findPicker(el{AXChildren={p}})==p) end)
test('malformed and inaccessible identifiers fail safely',function() assert(not A.currentFromPicker(el{}));assert(not A.attr(nil,'AXRole')) end)
test('numbered tabs normalize to Local',function() assert(A.normalizeTitle('17 Tabs')=='Local') end)
test('menu traversal preserves exact order',function()
  local actual=A.readOrder(menu{'Ignored','17 Tabs','ENGG3112','ELEC2602','SOFT2201','SOFT2412','ELEC3609','New Empty Tab Group','Excluded'})
  assert(table.concat(actual,',')==table.concat(order,','))
end)
test('duplicate menu noise preserves first occurrence',function() assert(table.concat(A.readOrder(menu{'17 Tabs','A','A','17 Tabs','B'}),',')=='Local,A,B') end)
for _,stop in ipairs{'New Empty Tab Group','New Tab Group with 17 Tabs'} do
  test('collection stops at '..stop,function() assert(#A.readOrder(menu{'17 Tabs','A',stop,'B'})==2) end)
end
for _,pair in ipairs{{'Local','SOFT2412'},{'ENGG3112','ELEC3609'},{'ELEC3609','SOFT2201'}} do
  test(pair[1]..' to '..pair[2]..' is PREVIOUS x2',function() local r=A.route(order,pair[1],pair[2]);assert(r.direction=='PREVIOUS' and r.steps==2 and r.key=='up') end)
end
test('tie chooses NEXT',function() local r=A.route(order,'Local','SOFT2201');assert(r.direction=='NEXT' and r.steps==3) end)
test('missing current fails',function() local r,why=A.route(order,'missing','Local');assert(not r and why:find('current')) end)
test('missing target fails',function() local r,why=A.route(order,'Local','missing');assert(not r and why:find('target')) end)
local function fixture(opts)
  opts=opts or {}
  local f={now=0,timers={},keys={},front=not opts.background,lookups={},launches=0,current=opts.current or 'Local',calls=0,presses=0}
  local function later(delay,fn)
    local t={at=f.now+delay,fn=fn,stop=function(self) self.stopped=true end};f.timers[#f.timers+1]=t;return t
  end
  local app={activate=function() f.activated=true end,bundleID=function() return 'com.apple.Safari' end}
  hs={timer={doAfter=later,secondsSinceEpoch=function() return f.now end},application={get=function() if not opts.notRunning then return app end end,launchOrFocus=function(name)
    assert(name=='Safari');f.launches=f.launches+1
    if not opts.focusTimeout then later(opts.focusDelay or 0,function() f.front=true;f.focusedAt=f.now end) end
    return not opts.focusTimeout
  end,frontmostApplication=function() if f.front then return app end end},axuielement={applicationElement=function()
    f.lookups[#f.lookups+1]=f.now
    -- Each unavailable root stays empty, even after the toolbar becomes ready.
    if not f.front or f.now<(opts.pickerDelay or 0) or opts.noPicker or (opts.verifyMissing and #f.keys>1) then return el{} end
    local p=picker(f.current=='Local' and '' or f.current)
    p.performAction=function(_,action) assert(action=='AXPress');f.presses=f.presses+1;if opts.pressError then error('failed') end;if opts.pressNil then return nil,'AX failure' end;f.open=true;return p end
    local titles=opts.titles or {'17 Tabs','ENGG3112','ELEC2602','SOFT2201','SOFT2412','ELEC3609','New Empty Tab Group'}
    -- AX children reflect the menu only after AXPress.
    return {attributeValue=function(_,key) if key=='AXChildren' then return f.open and {p,menu(titles)} or {p} end end}
  end},eventtap={isSecureInputEnabled=function() return opts.secure end,keyStroke=function(mods,key)
    assert(f.front);f.keys[#f.keys+1]={key=key,at=f.now}
    if key=='escape' then assert(#mods==0);f.open=false;return end
    assert(#mods==2 and mods[1]=='cmd' and mods[2]=='shift' and (key=='up' or key=='down'))
    if not opts.mismatch then
      local index;for i,name in ipairs(order) do if name==f.current then index=i end end
      f.current=order[((index-1+(key=='down' and 1 or -1))%#order)+1]
    end
    if opts.loseFocus then f.front=false end
  end},task={new=function() error('production must not execute sqlite or scripts') end}}
  f.parent=R.new(1,function() return 1 end,error)
  f.adapter=require('warp.adapters.safari').new();f.state={}
  function f:start(target) self.adapter:restore({safari={tabGroup=target or 'SOFT2412'}},self.state,self.parent,function(ok,why) self.ok=ok;self.why=why;self.calls=self.calls+1 end) end
  function f:step()
    table.sort(self.timers,function(a,b) return a.at<b.at end)
    local t=table.remove(self.timers,1);if not t then return false end
    self.now=t.at;if not t.stopped then t.fn() end;return true
  end
  function f:run() local n=0;while self:step() do n=n+1;assert(n<200) end end
  return f
end
test('already target completes without menu or navigation',function() local f=fixture{current='SOFT2412'};f:start();f:run();assert(f.ok and #f.keys==0 and f.presses==0 and f.calls==1) end)
test('adapter uses fast AX burst and final verification without database',function()
  local f=fixture();f:start();f:run();assert(f.ok and f.state.safari.verified and f.calls==1 and #f.keys==3)
  assert(f.keys[1].key=='escape' and math.abs(f.keys[1].at-0.32)<0.001)
  assert(f.keys[2].key=='up' and math.abs(f.keys[2].at-0.40)<0.001)
  assert(f.keys[3].key=='up' and math.abs(f.keys[3].at-0.46)<0.001 and math.abs(f.now-0.66)<0.001)
end)
for _,case in ipairs{{noPicker=true},{notRunning=true},{pressError=true},{pressNil=true},{secure=true},{current='absent'},{titles={'17 Tabs','Other','New Empty Tab Group'}}} do
  test('adapter failure completes once safely',function() local f=fixture(case);f:start();f:run();assert(f.ok==false and f.calls==1);for _,key in ipairs(f.keys) do assert(key.key=='escape') end end)
end
test('final mismatch fails within bounded polling',function() local f=fixture{mismatch=true};f:start();f:run();assert(f.ok==false and not f.state.safari.verified and f.why:find('AX verification') and f.now<1.5 and #f.keys==3) end)
test('missing final picker fails verification',function() local f=fixture{verifyMissing=true};f:start();f:run();assert(f.ok==false and f.why:find('AX verification')) end)
test('verification retries until fresh AX target appears',function()
  local f=fixture{mismatch=true};f:start();hs.timer.doAfter(0.8,function() f.current='SOFT2412' end);f:run();assert(f.ok and f.now>=0.8 and #f.keys==3)
end)
test('focus loss cancels remaining hops',function() local f=fixture{loseFocus=true};f:start();f:run();assert(f.ok==false and f.why:find('focus') and #f.keys==2) end)
test('parent cancellation closes open menu and cancels burst',function()
  local f=fixture();f:start();f:step();assert(f.open);local ctx=f.adapter.switcher.active;f.parent:cancel();f:run();assert(#f.keys==1 and not f.open and f.calls==0 and not next(ctx.timers) and not f.adapter.switcher.active)
end)
test('stop cancels pending burst and explicit diagnostics',function()
  local f=fixture();local stopped=0;f.adapter.debugSwitcher={stop=function() stopped=stopped+1 end};f:start();f:step();f:step();f.adapter:stop();f:run();assert(#f.keys==1 and f.calls==0 and stopped==2)
end)
test('background activation precedes polling and foreground alone is insufficient',function()
  local f=fixture{background=true,focusDelay=0.10,pickerDelay=0.65};f:start()
  assert(f.launches==1 and #f.lookups==1 and f.presses==0)
  while f.now<0.60 do assert(f:step());assert(f.presses==0 and #f.keys==0 and f.calls==0) end
  assert(f.front and #f.lookups>5)
  f:run();assert(f.ok and f.calls==1 and f.presses==1)
  assert(f.keys[1].at>=0.77 and f.keys[1].at<0.83)
end)
test('picker readiness timeout is bounded when activation fails',function()
  local f=fixture{background=true,focusTimeout=true};f:start();f:run()
  assert(f.ok==false and f.why:find('readiness timeout') and f.calls==1 and math.abs(f.now-2)<0.001)
  assert(f.launches==1 and #f.lookups>30 and #f.keys==0 and not f.adapter.switcher.active)
end)
test('nominally frontmost with absent picker times out safely',function()
  local f=fixture{background=true,focusDelay=0.25,noPicker=true};f:start();f:run()
  assert(f.front and f.ok==false and f.why:find('picker not found') and f.calls==1 and #f.keys==0 and math.abs(f.now-2)<0.001)
end)
test('already foreground skips activation and retains original settle timing',function()
  local f=fixture();f:start();f:run()
  assert(f.ok and f.launches==0 and not f.activated and math.abs(f.lookups[1]-0.20)<0.001)
end)
test('cancelling readiness wait prevents further AX and navigation',function()
  local f=fixture{background=true,focusTimeout=true};f:start();local ctx=f.adapter.switcher.active
  local reads=#f.lookups;f.parent:cancel();f:run();assert(f.calls==0 and #f.lookups==reads and #f.keys==0 and not next(ctx.timers))
end)
print('PASS: '..total..' Safari AX tests; no live GUI verification')
