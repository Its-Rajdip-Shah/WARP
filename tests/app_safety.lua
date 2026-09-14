package.path='./src/?.lua;'..package.path
local C=require('warp.config')
local W=require('warp.windows')
local total=0
local function test(name,fn) fn();total=total+1;print('PASS: '..name) end
local cfg=assert(C.validate({one={label='One',key='1',apps={{id='docker'},{id='figma'}}},two={label='Two',key='2',apps={{id='figma'}}}}))
local function win(id,full)
  local w={minimized=false,full=full}
  function w:id() return id end
  function w:title() return 'Document '..id end
  function w:isFullScreen() return self.full end
  function w:isMinimized() return self.minimized end
  function w:minimize() self.minimized=true end
  function w:unminimize() self.minimized=false end
  function w:close() error('must not close') end
  function w:setFullScreen() error('must not exit fullscreen') end
  return w
end
local live,launches={},0
W.list=function() return live end
hs={application={launchOrFocusByBundleID=function(bundle)
  assert(bundle=='com.docker.docker');launches=launches+1;live={win(99)};return true
end},task={new=function() error('no engine/session commands') end}}
local ctx={valid=function() return true end,wait=function(_,_,predicate,done) done(predicate()) end}
test('Docker irrelevant UI minimizes normals, preserves fullscreen, never launches',function()
  live={win(1),win(2,true)};local a=require('warp.adapters.docker').new()
  a:restore(cfg.workflows.two,{windows={}},ctx,function(ok) assert(ok) end)
  assert(live[1].minimized and not live[2].minimized and launches==0)
end)
test('Docker relevant UI restores; missing UI launches only when required',function()
  local a=require('warp.adapters.docker').new();live={win(1)};live[1].minimized=true
  a:restore(cfg.workflows.one,{windows={}},ctx,function(ok) assert(ok) end);assert(not live[1].minimized)
  live={};a:restore(cfg.workflows.two,{windows={}},ctx,function(ok) assert(ok) end);assert(launches==0)
  a:restore(cfg.workflows.one,{windows={}},ctx,function(ok) assert(ok) end);assert(launches==1 and not a.cold)
end)
test('Figma can be shared by configured workflows; irrelevant windows minimize without closing',function()
  live={win(1),win(2,true)};local a=require('warp.adapters.figma').new(cfg)
  assert(#a:discover(cfg.workflows.one)==2 and #a:discover(cfg.workflows.two)==2)
  a:restore(cfg.workflows.general,{windows={}},ctx,function(ok) assert(ok) end)
  assert(live[1].minimized and not live[2].minimized)
end)
test('Figma ambiguous live documents are preserved without invented reopen',function()
  live={win(1),win(1)};local a=require('warp.adapters.figma').new(cfg)
  a:restore(cfg.workflows.one,{windows={}},ctx,function(ok,why) assert(not ok and why:find('ambiguous')) end)
  assert(not live[1].minimized and not live[2].minimized)
end)
test('Figma does not apply a missing document layout to an unrelated open document',function()
  live={win(7)};local capture,restore=W.capture,W.restore;local restored
  W.capture=function(_,adapter,id) return {adapter=adapter,identity=id,frame={x=0,y=0,w=1,h=1}} end
  W.restore=function(_,r,_,done) restored=r.identity;done(true) end
  require('warp.adapters.figma').new(cfg):restore(cfg.workflows.one,{windows={old={adapter='figma',identity='Missing document',frame={x=9,y=9,w=9,h=9}}}},ctx,function(ok,why) assert(not ok and why:find('exact reopen')) end)
  assert(restored=='Document 7');W.capture,W.restore=capture,restore
end)
test('Terminal disabled context and COLD retain sessions without commands',function()
  local a=require('warp.adapters.terminal').new();local state={}
  a:restore(cfg.workflows.general,state,ctx,function(ok) assert(ok) end)
  a:cold(cfg.workflows.general,state);assert(state.retained.terminal:find('preserved'))
end)
print('PASS: '..total..' app safety tests; no live GUI actions')
