package.path='./src/?.lua;'..package.path
local Resources=require('warp.vscode_resources')
local W=require('warp.windows')
local total=0
local function test(name,fn) fn();total=total+1;print('PASS: '..name) end
local function fixture()
  local f={live={},launches=0,actions={},focused=nil}
  function f:win(id)
    return {id=function() return id end,application=function() return {pid=function() return 10 end,bundleID=function() return 'com.microsoft.VSCode' end} end}
  end
  hs={window={focusedWindow=function() return f.focused end,filter={windowFocused='focus',windowUnfocused='unfocus',windowDestroyed='destroy',new=function(predicate)
    f.predicate=predicate
    local w={callbacks={}};function w:subscribe(e,fn) self.callbacks[e]=fn end
    function w:unsubscribeAll() self.callbacks={} end;function w:pause() self.paused=true end;return w
  end}},fs={attributes=function(path,mode) if path=='/missing' then return nil end;return mode=='mode' and 'directory' or true end}}
  W.list=function() return f.live end
  f.r=Resources.new();f.r.inventory={}
  f.ctx={valid=function() return true end,onCancel=function() end,task=function(_,path,args,done)
    assert(path:find('/bin/code',1,true) and args[1]=='--new-window' and #args==2);f.launches=f.launches+1
    f.focused=f:win(77);f.live[#f.live+1]=f.focused;done(0,'','')
  end,wait=function(_,_,predicate,done) done(predicate(),'no native window') end}
  f.r.bridge={request=function(_,ctx,action,_,_,done)
    assert(action=='probe' or action=='inventory');f.actions[#f.actions+1]=action
    if action=='inventory' then done({windows=f.inventory or (f.launches>0 and {{session='new',descriptor=f.reply or {kind='folder',path='/project'},focused=true}} or {})})
    else done({session='new',descriptor=f.reply or {kind='folder',path='/project'},focused=true}) end
  end}
  return f
end
test('stable folder/workspace keys do not depend on native window IDs',function()
  assert(Resources.key{kind='folder',path='/project'}=='folder:/project')
  assert(Resources.key{kind='workspace',path='/team.code-workspace'}=='workspace:/team.code-workspace')
  assert(not Resources.key{kind='folder',path='relative'})
end)
test('verified descriptor reopens via CLI argument array and binds new runtime',function()
  local f=fixture();local win
  f.r:reopen(f.ctx,{kind='folder',path='/project'},function(w) win=w end)
  assert(win==f.focused and f.launches==1 and f.r:descriptor(win).path=='/project' and not next(f.r.pending))
end)
test('missing local resource never launches',function()
  local f=fixture();f.r:reopen(f.ctx,{kind='folder',path='/missing'},function(w,why) assert(not w and why:find('missing')) end);assert(f.launches==0)
end)
test('unknown or already matching inventory prevents duplicate launch',function()
  for _,descriptor in ipairs{{kind='folder',path='/project'},{kind='remote',path='host'}} do
    local f=fixture();f.live={f:win(1)};f.r.inventory={{descriptor=descriptor}}
    f.r:reopen(f.ctx,{kind='folder',path='/project'},function(w,why) assert(not w and why:find('deferred')) end);assert(f.launches==0)
  end
end)
test('unavailable or incomplete inventory never guesses missing identity',function()
  for _,inventory in ipairs{false,{}} do
    local f=fixture();f.live={f:win(1)};f.r.inventory=inventory or nil
    f.r:reopen(f.ctx,{kind='folder',path='/project'},function(w) assert(not w) end);assert(f.launches==0)
  end
end)
test('mismatched probe keeps launch uncertain and prevents repeat',function()
  local f=fixture();f.reply={kind='folder',path='/wrong'}
  for _=1,2 do f.r:reopen(f.ctx,{kind='folder',path='/project'},function(w) assert(not w) end) end
  assert(f.launches==1 and f.r.pending['folder:/project'])
end)
test('focus interruption invalidates reopen binding even if focus returns',function()
  local f=fixture();f.r.bridge.request=function(_,_,_,_,_,done) f.r.epoch=f.r.epoch+1;done({windows={{session='new',descriptor={kind='folder',path='/project'},focused=true}}}) end
  f.r:reopen(f.ctx,{kind='folder',path='/project'},function(w) assert(not w) end)
  assert(f.r.pending['folder:/project'])
end)
test('inventory refreshes descriptors without changing another workflow resource key',function()
  local f=fixture();f.r.bindings['10:1']={session='same',descriptor={kind='folder',path='/old'}}
  f.inventory={{session='same',descriptor={kind='folder',path='/new'},focused=false}}
  local done;f.r:prepare(f.ctx,function() done=true end)
  assert(done and f.r.bindings['10:1'].descriptor.path=='/new')
end)
test('descriptor watcher has no qualification loop and stops cleanly',function()
  local f=fixture();f.r:start(function() return false end);local filter=f.r.filter
  filter.callbacks.focus(f:win(1));assert(#f.actions==0 and not f.r.probe)
  filter.callbacks.unfocus();f.r:stop();assert(filter.paused and not next(filter.callbacks) and not next(f.r.bindings))
end)
test('destroyed native handle loses binding without any workflow relevance mutation',function()
  local f=fixture();local w=f:win(1);f.r.bindings['10:1']={session='old',win=w,descriptor={kind='folder',path='/project'}}
  f.r:start(function() return false end);f.r.filter.callbacks.destroy(w)
  assert(not f.r.bindings['10:1'] and f.launches==0);f.r:stop()
end)
test('nil filter focus destroy and learn events are ignored',function()
  local f=fixture();f.r:start(function() return true end)
  assert(f.predicate(nil)==false);f.r.filter.callbacks.focus(nil);f.r.filter.callbacks.destroy(nil);f.r:learn(nil)
  assert(#f.actions==0 and f.r.epoch==0)
end)
test('known live bindings permit reopen despite stale dead inventory session',function()
  local f=fixture();local w=f:win(1);f.live={w}
  f.r.bindings['10:1']={win=w,descriptor={kind='folder',path='/other'}}
  f.r.inventory={{descriptor={kind='folder',path='/project'}}}
  f.r:reopen(f.ctx,{kind='folder',path='/project'},function(win) assert(win and win:id()==77) end)
  assert(f.launches==1)
end)
test('inventory failure does not erase a learned stable binding',function()
  local f=fixture();local w=f:win(1);f.live={w}
  f.r.bindings['10:1']={win=w,session='old',descriptor={kind='folder',path='/project'}}
  f.r.bridge.request=function(_,_,_,_,_,done) done(nil,'companion response timed out') end
  f.r:prepare(f.ctx,function() end);assert(f.r:descriptor(w).path=='/project')
end)
test('late companion activation is retried without launching twice',function()
  local f=fixture();local attempts=0
  f.r.bridge.request=function(_,_,action,_,_,done)
    assert(action=='inventory');attempts=attempts+1
    done({windows=attempts<3 and {} or {{session='new',descriptor={kind='folder',path='/project'},focused=true}}})
  end
  f.r:reopen(f.ctx,{kind='folder',path='/project'},function(w) assert(w) end)
  assert(attempts==3 and f.launches==1)
end)
test('reopen companion errors remain bounded and uncertain launch is not repeated',function()
  local f=fixture();local attempts=0
  f.r.bridge.request=function(_,_,_,_,_,done) attempts=attempts+1;done(nil,'companion response timed out') end
  f.r:reopen(f.ctx,{kind='folder',path='/project'},function(w,why) assert(not w and why:find('timed out')) end)
  assert(attempts==3 and f.launches==1 and f.r.pending['folder:/project'])
end)
print('PASS: '..total..' descriptor resource tests; no live launches')
