-- Finder location context has no window ownership, geometry, or Space records.
package.path='./src/?.lua;'..package.path
local C=require('warp.config')
local State=require('warp.state')
local Finder=require('warp.adapters.finder')
local total=0
local function test(name,fn) fn();total=total+1;print('PASS: '..name) end
local cfg=assert(C.validate({one={label='One',key='1',finder='/project'},two={label='Two',key='2'}}))
test('Finder path normalized; legacy ownership blocks ignored',function()
  assert(cfg.workflows.one.finder=='/project' and cfg.workflows.general.finder==os.getenv('HOME'))
  local c=assert(C.validate({one={label='One',key='1',finder={leftRoot='old'},primary='finder',spaceOrder={'finder','desktop'}}}))
  assert(c.workflows.one.finder==nil and c.workflows.one.primary=='none' and #c.warnings==1)
  assert(not C.validate({one={label='One',key='1',finder='relative'}}))
end)
test('Finder state never persists and old records are removed',function()
  local raw={version=1,shared={finder={id=42}},workflows={one={windows={['finder:left']='obsolete',x={adapter='finder'}},spaces={{role='finder',id=42}}}}}
  local d=State.sanitize(raw,cfg);assert(not d.shared.finder and not next(d.workflows.one.windows) and #d.workflows.one.spaces==0)
  d.workflows.one.windows.x={adapter='finder'};d.workflows.one.finder={id=42}
  local saved=State.persistable(d);assert(not saved.workflows.one.windows.x and not saved.workflows.one.finder)
  assert(d.workflows.one.windows.x)
end)
test('Finder excluded from window ownership and discovery',function()
  assert(require('warp.ownership').bundles.finder==nil)
  assert(#Finder.new():discover(cfg.workflows.one)==0)
end)
local R=require('warp.request')
local function fixture(failClose,failOpen)
  local f={now=0,timers={},events={}}
  hs={fs={attributes=function(path) return path=='/project' and 'directory' or nil end},osascript={applescript=function(script)
    assert(script:find('close every Finder window',1,true) and not script:find('quit') and not script:find('make new'))
    f.events[#f.events+1]='close';return not failClose,'close failed'
  end},timer={doAfter=function(delay,fn)
    local t={at=f.now+delay,fn=fn,stop=function(self) self.stopped=true end};f.timers[#f.timers+1]=t;return t
  end},task={new=function(path,callback,args)
    assert(path=='/usr/bin/open' and #args==1 and args[1]=='/project' and f.now==0.3)
    f.events[#f.events+1]='open'
    return {start=function() hs.timer.doAfter(0,function() callback(failOpen and 1 or 0,'','open failed') end);return true end}
  end}}
  f.ctx=R.new(1,function() return 1 end,error)
  function f:run()
    while #self.timers>0 do
      table.sort(self.timers,function(a,b) return a.at<b.at end);local t=table.remove(self.timers,1)
      if not t.stopped then self.now=t.at;t.fn() end
    end
  end
  return f
end
test('Finder closes then waits 300ms before argument-array open, including reselection',function()
  for _=1,2 do
    local f=fixture();Finder.new():restore(cfg.workflows.one,{},f.ctx,function(ok) assert(ok);f.done=true end)
    assert(#f.events==1 and not f.done);f:run();assert(f.done and table.concat(f.events,',')=='close,open')
  end
end)
test('missing path and absent config cause no desktop actions',function()
  local f=fixture();local a=Finder.new()
  a:restore({finder='/missing'},{},f.ctx,function(ok) assert(not ok) end)
  a:restore(cfg.workflows.two,{},f.ctx,function(ok) assert(ok) end);assert(#f.events==0)
end)
test('close failure does not open and open failure reaches completion',function()
  for _,close in ipairs{true,false} do
    local f=fixture(close,not close);local result
    Finder.new():restore(cfg.workflows.one,{},f.ctx,function(ok) result=ok end);f:run()
    assert(result==false and #f.events==(close and 1 or 2))
  end
end)
test('cancel during Finder settle prevents stale open',function()
  local f=fixture();Finder.new():restore(cfg.workflows.one,{},f.ctx,function() error('stale callback') end)
  f.ctx:cancel();f:run();assert(#f.events==1)
end)
print('PASS: '..total..' Finder location tests; no live GUI actions')
