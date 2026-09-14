package.path='./src/?.lua;'..package.path
local D=require('warp.safari_debug')
local R=require('warp.request')
local total=0
local function test(name,fn) fn(); total=total+1; print('PASS: '..name) end
local function row(window,id,title) return {window=tostring(window),id=tostring(id),title=title} end
local function encode(rows)
  local out={}
  for _,r in ipairs(rows) do out[#out+1]=r.window..'\t'..r.id..'\t'..r.title:gsub('.',function(c) return string.format('%02X',c:byte()) end) end
  return table.concat(out,'\n')..'\n'
end
local function fixture(options)
  options=options or {}
  local f={now=0,timers={},tasks={},logs={},front=false,launches=0,hops=0,reads=0,keys=0,rows={row(19,1,'Local'),row(21,2,'ELEC3609')}}
  local function later(delay,fn)
    local t={at=f.now+delay,fn=fn}; function t:stop() self.stopped=true end
    f.timers[#f.timers+1]=t; return t
  end
  f.later=later; f.hopTimes={}
  hs={application={frontmostApplication=function() if f.front then return {bundleID=function() return 'com.apple.Safari' end} end end,
    launchOrFocus=function(name) assert(name=='Safari'); f.launches=f.launches+1
      if f.launches>=(options.focusAttempt or 1) then later(options.focusDelay or 0,function() f.front=true end) end
      return true
    end},timer={secondsSinceEpoch=function() return f.now end,doAfter=later},eventtap={isSecureInputEnabled=function() return false end,
    keyStroke=function(mods,key,...)
      assert(select('#',...)==0); f.keys=f.keys+1
      assert(f.front and mods[1]=='cmd')
      if key=='l' then assert(#mods==1); if options.loseOnL and not f.lost then f.lost=true; f.front=false end
      else
        assert(key=='down' and #mods==2 and mods[2]=='shift'); f.hops=f.hops+1; f.hopTimes[#f.hopTimes+1]=f.now
        if options.onHop then options.onHop(f) end
      end
    end},task={new=function(path,callback,args)
      assert(path=='/usr/bin/sqlite3' and args[1]=='-readonly' and args[#args]==D.query)
      assert(not D.query:upper():match('UPDATE') and not D.query:upper():match('INSERT'))
      f.reads=f.reads+1
      if f.reads==1 then assert(f.front) end
      local t={callback=callback}; f.tasks[#f.tasks+1]=t
      function t:start()
        self.running=true
        later(0.001,function() if self.running and self.callback then self.running=false
          if options.dbFailure then self.callback(1,'','denied') else self.callback(0,encode(f.rows),'') end
        end end); return true
      end
      function t:isRunning() return self.running end
      function t:terminate() self.running=false end
      function t:setCallback(cb) self.callback=cb end
      return t
    end}}
  function f:step()
    table.sort(self.timers,function(a,b) return a.at<b.at end)
    local t=table.remove(self.timers,1); if not t then return false end
    if not t.stopped then self.now=t.at; t.fn() end
    return true
  end
  function f:run() for _=1,3000 do if not self:step() then return end end; error('unbounded timers') end
  function f:start(target,parent)
    self.core=D.new(); assert(self.core:switch(target,function(ok,why) self.ok=ok; self.why=why; self.finished=self.now end,parent)); return self.core
  end
  function f:clean()
    assert(self.core.active==nil)
    for _,t in ipairs(self.tasks) do assert(not t.running) end
  end
  return f
end
local function change(f,title,window)
  for _,r in ipairs(f.rows) do if r.window==tostring(window or 19) then r.id=tostring(100+f.hops);r.title=title end end
end
test('sqlite parser handles escaped title bytes and rejects malformed rows',function()
  local rows=assert(D.parse('19\t2\t4C6F63616C\n21\t1\t4109420A43\n'))
  assert(rows[2].title=='A\tB\nC' and D.parse('21\t\t\n')[1].title=='')
  for _,s in ipairs({'','bad','21\t1\tA\n','21\t1\tGG\n','21\t1\t41\n21\t2\t42\n'}) do assert(not D.parse(s)) end
end)
test('snapshot comparison detects actual row changes without title-based selection',function()
  local before={row(19,1,'Local'),row(21,2,'ELEC3609')}
  local changes=assert(D.changed(before,{row(19,3,'ELEC2602'),row(21,2,'ELEC3609')}))
  assert(#changes==1 and changes[1].after.window=='19')
  assert(not D.changed(before,{row(21,2,'ELEC3609')}))
end)
test('two Local rows bind by window/group IDs, not title or position',function()
  local before={row(19,39936,'Local'),row(21,44997,'Local')}
  local changes=assert(D.changed(before,{row(19,39936,'Local'),row(21,46183,'SOFT2201')}))
  assert(#changes==1 and changes[1].after.window=='21' and changes[1].before.id=='44997' and changes[1].after.id=='46183')
  changes=assert(D.changed(before,{row(19,39936,'Local'),row(21,46183,'Local')}))
  assert(#changes==1 and changes[1].after.window=='21')
  assert(#assert(D.changed(before,{row(19,39936,'Renamed'),row(21,44997,'Local')}))==0)
end)
test('delayed commits use fresh processes and never trigger a premature keyboard retry',function()
  for _,delay in ipairs({0.85,2.8,4.5}) do
    local f=fixture({onHop=function(f)
      assert(f.hops==1,'keyboard retried before delayed commit')
      f.later(delay,function() f.rows[2]=row(21,46183,'SOFT2201') end)
    end})
    f.rows={row(19,39936,'Local'),row(21,44997,'Local')}
    f:start('SOFT2201'); f:run()
    assert(f.ok and f.hops==1 and f.keys==2 and f.reads>5 and #f.tasks==f.reads)
    assert(f.finished-f.hopTimes[1]>=delay+0.4 and f.finished-f.hopTimes[1]<delay+0.65)
    f:clean()
  end
end)
test('unchanged DB gets full six-second observation window before each retry',function()
  local f=fixture();f:start('missing');f:run()
  assert(not f.ok and f.hops==3)
  assert(f.hopTimes[2]-f.hopTimes[1]>=6 and f.hopTimes[3]-f.hopTimes[2]>=6)
  assert(f.finished-f.hopTimes[3]>=6); f:clean()
end)
test('transient target is not accepted until the latest group stabilizes',function()
  local f=fixture({onHop=function(f)
    if f.hops==1 then
      f.later(0.2,function() f.rows[2]=row(21,46115,'SOFT2412') end)
      f.later(0.4,function() f.rows[2]=row(21,46152,'ELEC2602') end)
    else
      assert(f.now-f.hopTimes[1]>=0.8,'next hop raced stabilization')
      f.later(3.5,function() f.rows[2]=row(21,46115,'SOFT2412') end)
    end
  end})
  f:start('SOFT2412');f:run()
  assert(f.ok and f.hops==2 and f.finished-f.hopTimes[2]>=3.9);f:clean()
end)
test('continuously unstable transition aborts without another keyboard hop',function()
  local f=fixture({onHop=function(f)
    assert(f.hops==1)
    for i=1,24 do f.later(i*0.25,function() f.rows[2]=row(21,50000+i,'transient'..i) end) end
  end})
  f:start('missing');f:run();assert(not f.ok and f.hops==1 and f.why:find('stabilize'));f:clean()
end)
test('transition reverting to baseline times out without no-progress keyboard retry',function()
  local f=fixture({onHop=function(f)
    assert(f.hops==1)
    f.later(0.2,function() f.rows[2]=row(21,999,'transient') end)
    f.later(0.4,function() f.rows[2]=row(21,2,'ELEC3609') end)
  end})
  f:start('missing');f:run();assert(not f.ok and f.hops==1 and f.why:find('stabilize'));f:clean()
end)
test('several delayed stable hops follow the same row without the old outer cutoff',function()
  local f=fixture({onHop=function(f)
    if f.hops>1 then assert(f.hopTimes[f.hops]-f.hopTimes[f.hops-1]>=4.4) end
    local n=f.hops
    f.later(4,function() f.rows[2]=row(21,60000+n,n==6 and 'target' or ('group'..n)) end)
  end})
  f:start('target');f:run()
  assert(f.ok and f.hops==6 and f.finished>25 and f.finished<90 and f.rows[1].title=='Local');f:clean()
end)
test('focus launcher confirms delayed foreground and binds changed Local row',function()
  local f=fixture({focusDelay=0.2,onHop=function(f) change(f,'SOFT2412') end})
  f:start('SOFT2412'); f:run(); assert(f.ok and f.launches==1 and f.hops==1);f:clean()
end)
test('focus retries once then succeeds',function()
  local f=fixture({focusAttempt=2,onHop=function(f) change(f,'target') end})
  f:start('target');f:run();assert(f.ok and f.launches==2);f:clean()
end)
test('inability to focus fails before database or keyboard actions',function()
  local f=fixture({focusAttempt=99});f:start('target');f:run()
  assert(not f.ok and f.launches==2 and f.reads==0 and f.keys==0);f:clean()
end)
test('arbitrary target in another DB row does not short-circuit discovery',function()
  local f=fixture({onHop=function(f) change(f,f.hops==1 and 'ELEC2602' or 'ELEC3609') end})
  f:start('ELEC3609');f:run();assert(f.ok and f.hops==2 and f.rows[2].title=='ELEC3609');f:clean()
end)
test('initially active controlled target cycles away and back',function()
  local f=fixture({onHop=function(f) if f.hops==1 then change(f,'Next') else f.rows[1]=row(19,1,'Local') end end})
  f:start('Local');f:run();assert(f.ok and f.hops==2);f:clean()
end)
test('zero progress refocuses and retries then succeeds',function()
  local f=fixture({onHop=function(f) if f.hops==2 then change(f,'target') end end})
  f:start('target');f:run();assert(f.ok and f.hops==2 and f.launches==2);f:clean()
end)
test('repeated zero progress is bounded to initial hop plus two retries',function()
  local f=fixture();f:start('target');f:run()
  assert(not f.ok and f.hops==3 and f.launches==3 and f.why:find('no DB progress'));f:clean()
end)
test('multiple changed DB rows abort without further hops',function()
  local f=fixture({onHop=function(f) change(f,'A',19);change(f,'B',21) end})
  f:start('target');f:run();assert(not f.ok and f.hops==1 and f.why:find('ambiguous'));f:clean()
end)
test('bound window never silently changes to another DB row',function()
  local f=fixture({onHop=function(f) change(f,'group'..f.hops,f.hops==1 and 19 or 21) end})
  f:start('target');f:run();assert(not f.ok and f.hops==2 and f.why:find('different'));f:clean()
end)
test('focus loss between hops is reacquired',function()
  local f=fixture({onHop=function(f) change(f,f.hops==1 and 'Next' or 'target');if f.hops==1 then f.front=false end end})
  f:start('target');f:run();assert(f.ok and f.launches==2);f:clean()
end)
test('focus loss during Cmd-L delay is reacquired and sequence restarted',function()
  local f=fixture({loseOnL=true,onHop=function(f) change(f,'target') end})
  f:start('target');f:run();assert(f.ok and f.launches==2 and f.hops==1 and f.keys==3);f:clean()
end)
test('maximum eight keyboard hops bounds a nonrepeating cycle',function()
  local f=fixture({onHop=function(f) change(f,'group'..f.hops) end})
  f:start('missing');f:run();assert(not f.ok and f.hops==8 and f.why:find('max hops'));f:clean()
end)
test('full cycle without target aborts',function()
  local f=fixture({onHop=function(f) if f.hops==1 then change(f,'Next') else f.rows[1]=row(19,1,'Local') end end})
  f:start('missing');f:run();assert(not f.ok and f.hops==2 and f.why:find('full cycle'));f:clean()
end)
test('parent cancellation clears Safari task and timer ownership immediately',function()
  local f=fixture();local parent=R.new(1,function() return 1 end,error);local core=f:start('target',parent)
  while f.reads==0 do assert(f:step()) end
  local ctx=core.active;parent:cancel();f:run()
  assert(f.keys==0 and next(ctx.tasks)==nil and next(ctx.timers)==nil);f:clean()
end)
test('stop/reload cleanup cancels pending work without another key',function()
  local f=fixture();local core=f:start('target');local ctx=core.active;core:stop();f:run()
  assert(f.keys==0 and next(ctx.tasks)==nil and next(ctx.timers)==nil);f:clean()
end)
test('normal Safari restore and debug instance use exactly the shared core',function()
  local f=fixture({onHop=function(f) change(f,'target') end})
  local adapter=require('warp.adapters.safari').new();f.core=adapter.switcher;local state={}
  adapter:restore({safari={tabGroup='target'}},state,R.new(1,function() return 1 end,error),function(ok) f.ok=ok end)
  f:run();assert(f.ok and state.safari.verified and f.hops==1);f:clean()
  local file=assert(io.open('src/init.lua'));local source=file:read('*a');file:close()
  assert(source:find('local safariDebug=manager.safari.switcher',1,true))
end)
test('read failure is graceful and normal adapter invokes completion',function()
  local f=fixture({dbFailure=true});local adapter=require('warp.adapters.safari').new();f.core=adapter.switcher
  adapter:restore({safari={tabGroup='target'}},{},R.new(1,function() return 1 end,error),function(ok) f.ok=ok end)
  f:run();assert(f.ok==false and f.keys==0);f:clean()
end)
test('concurrent calls rejected and invalid target creates no transaction',function()
  local f=fixture();local core=D.new();assert(not core:switch('  '));assert(core.active==nil)
  f.core=core;assert(core:switch('target'));assert(not core:switch('other'));core:stop();f:run();f:clean()
end)
print('PASS: '..total..' Safari focus/discovery tests; no live GUI verification')
