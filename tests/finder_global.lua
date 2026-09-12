package.path='./src/?.lua;'..package.path
local C=require('warp.config')
local State=require('warp.state')
local U=require('warp.util')
local count=0
local function test(name,fn) fn(); count=count+1; print('PASS: '..name) end
local config
local legacy={one={label='One',key='1',finder={leftRoot='invalid',rightRoot=false},primary='finder',spaceOrder={'finder','desktop','finder','vscode'},terminal={tmuxSession='one'}},two={label='Two',key='2',primary='none'}}
test('legacy Finder config is ignored with one warning and no primary navigation',function()
  config=assert(C.validate(legacy)); local w=config.workflows.one
  assert(w.finder==nil and w.primary=='none' and #config.warnings==1)
  assert(#w.spaceOrder==2 and w.spaceOrder[2]=='vscode')
  assert(w.terminal.root==os.getenv('HOME'))
  assert(legacy.one.primary=='finder' and legacy.one.finder.leftRoot=='invalid')
  for _,value in ipairs({false,42,'old'}) do
    local c=assert(C.validate({one={label='One',key='1',finder=value}})); assert(#c.warnings==1 and c.workflows.one.finder==nil)
  end
end)
local raw={version=1,active='one',shared={finder={left={finderID=42}},other={keep=true}},workflows={one={lifecycle='ACTIVE',lastActive=12,pinned=true,finder={leftRoot='/old'},retained={finder='old',docker='keep'},spaces={{role='finder',id=42}},windows={['finder:left']='malformed obsolete record',strange={adapter='finder',frame={w=-1}},['vscode:project']={adapter='vscode',identity='project',windowID=8,frame={x=0,y=0,w=1,h=1}}}},two={lifecycle='WARM'}}}
test('version 1 migration drops Finder data and preserves unrelated state',function()
  local d=State.sanitize(raw,config); local w=d.workflows.one
  assert(d.version==1 and d.active=='one' and w.lifecycle=='ACTIVE' and w.pinned and w.lastActive==12)
  assert(d.shared.finder==nil and d.shared.other.keep and w.finder==nil and w.retained.finder==nil and w.retained.docker=='keep')
  assert(w.windows['finder:left']==nil and w.windows.strange==nil and w.windows['vscode:project'].identity=='project' and not w.windows['vscode:project'].windowID and #w.spaces==0)
  assert(raw.shared.finder.left.finderID==42 and raw.workflows.one.windows['vscode:project'].windowID==8)
end)
local function forbidden() error('unexpected desktop/Finder operation') end
local timers={}
hs={accessibilityState=function() return true end,timer={secondsSinceEpoch=function() return 20 end,doAfter=function(_,fn) local t={fn=fn}; function t:stop() self.stopped=true end; timers[#timers+1]=t; return t end},application={get=forbidden},osascript={applescript=forbidden},task={new=forbidden},spaces={allSpaces=function() return {screen={11}} end,focusedSpace=function() return 11 end,spaceType=function() return 'user' end,gotoSpace=forbidden},window={}}
local function flush() for _=1,100 do local t=table.remove(timers,1); if not t then return end; if not t.stopped then t.fn() end end; error('unsettled timers') end
test('Finder excluded from ownership, discovery and window filter',function()
  local O=require('warp.ownership'); assert(O.bundles.finder==nil)
  local W=require('warp.windows'); assert(#W.list('finder')==0 and W.finderEvidence==nil)
  hs.window.filter={new=function(predicate)
    assert(not predicate({application=function() return {bundleID=function() return 'com.apple.finder' end} end,isStandard=forbidden}))
    assert(predicate({application=function() return {bundleID=function() return O.bundles.vscode end} end,isStandard=function() return true end}))
    return {subscribe=function() end,unsubscribeAll=function() end,pause=function() end}
  end}
  W.start(); W.stop()
end)
test('activation checkpoint WARM COLD and reload never instantiate or operate Finder',function()
  package.preload['warp.adapters.finder']=forbidden
  package.loaded['warp.state']={new=function(c) return {data=State.sanitize(raw,c),save=function() return true end} end}
  local calls={}
  for _,name in ipairs({'safari','vscode','terminal','figma','docker'}) do
    calls[name]={restore=0,cold=0,discover=0}
    package.loaded['warp.adapters.'..name]={new=function() return {id=name,discover=function() calls[name].discover=calls[name].discover+1; return {} end,restore=function(_,_,_,_,done) calls[name].restore=calls[name].restore+1; done(true) end,cold=function() calls[name].cold=calls[name].cold+1 end} end}
  end
  local m=require('warp.manager').new(config)
  assert(m.debugFinder==nil and #m.adapters==5)
  assert(m:switchTo('one')); flush(); assert(#m.errors==0)
  assert(m:checkpoint()); assert(m:switchTo('two')); flush(); assert(#m.errors==0)
  assert(m.store.data.workflows.one.lifecycle=='WARM'); m:pin('one',false)
  assert(m:makeCold('one')); assert(m.store.data.workflows.one.lifecycle=='COLD')
  assert(m:switchTo('one')); flush(); assert(m.store.data.workflows.one.lifecycle=='ACTIVE' and #m.errors==0)
  for _,c in pairs(calls) do assert(c.restore==3 and c.cold==1 and c.discover>0) end
  for _,w in pairs(m.store.data.workflows) do for _,e in ipairs(w.spaces) do assert(e.role~='finder') end end
  m:stop(); m=require('warp.manager').new(config); m:stop()
end)
test('config loader emits a single deprecation warning per workflow',function()
  local oldLoad,oldLog=loadfile,U.log; local warnings={}
  hs.fs={attributes=function() return nil end}
  loadfile=function() return function() return legacy end end
  U.log=function(level,message) assert(level=='WARN'); warnings[#warnings+1]=message end
  assert(C.load('/fixture')); assert(#warnings==1 and warnings[1]:find('Finder is global',1,true))
  loadfile=oldLoad; U.log=oldLog
end)
print('PASS: '..count..' Finder-global regression tests; no live GUI actions')
