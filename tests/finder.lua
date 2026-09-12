-- Finder regression suite: real adapter/selection/parser, simulated Apple Events.
-- Never invokes osascript or any live desktop API.
package.path='./src/?.lua;'..package.path
local U=require('warp.util')
local W=require('warp.windows')
local Finder=require('warp.adapters.finder')
local Spaces=require('warp.spaces')
local realFinderEvidence=W.finderEvidence
local total=0
local function test(name,fn) fn(); total=total+1; print('PASS: Finder '..name) end
local screen={getUUID=function() return 'main' end,frame=function() return {x=0,y=25,w=1600,h=975} end,fullFrame=function() return {x=0,y=0,w=1600,h=1000} end}
local desktop,spaceCalls,focusCalls=10,0,{}
hs={screen={allScreens=function() return {screen} end,mainScreen=function() return screen end},
  spaces={activeSpaces=function() return {main=desktop} end,windowSpaces=function() return {desktop} end,
    gotoSpace=function() spaceCalls=spaceCalls+1; return true end},
  fs={attributes=function() return 'directory' end}}
local function make(id,x,space)
  return {finderID=id,hsID=id+1000,title='Folder '..id,kind='finder',frame={x=x,y=80,w=500,h=650},space=space or desktop}
end
local function harness(initial,shared,options)
  options=options or {}; local h={rows=initial,created=0,mutated={},frames=0,moves=0,scripts={},shared=shared or {},pid=99}
  local function hsWindow(r)
    r.win=r.win or {
      id=function() return r.hsID end,title=function() return r.title end,
      application=function() return {pid=function() return h.pid end} end,
      screen=function() return screen end,frame=function() return U.copy(r.frame) end,
      isFullScreen=function() return r.fullscreen==true end,
      moveToScreen=function() h.moves=h.moves+1 end,
      setFrame=function(_,f) h.frames=h.frames+1; r.frame=U.copy(f) end,
      focus=function() focusCalls[#focusCalls+1]=r.finderID end,
    }
    return r.win
  end
  W.finderEvidence=function()
    local out={}
    if not options.noHS then
      for _,r in ipairs(h.rows) do out[#out+1]={win=hsWindow(r),hsID=r.hsID,title=r.title,frame=U.copy(r.frame),standard=r.kind=='finder',fullscreen=r.fullscreen==true,spaceIDs={r.space},screenUUID='main',sources={AX=true}} end
    end
    return out,{},h.pid
  end
  local function escape(s) return (s:gsub('%%','%%25'):gsub('\t','%%09'):gsub('\n','%%0A'):gsub('\r','%%0D')) end
  function h:enumerate()
    local out={'WARP_FINDER_V1'}
    for _,r in ipairs(self.rows) do
      local f=r.frame
      out[#out+1]=table.concat({r.finderID,r.kind,f.x,f.y,f.x+f.w,f.y+f.h,tostring(r.modal==true),tostring(r.floating==true),tostring(r.collapsed==true),escape(r.title)},'\t')
    end
    return table.concat(out,'\n')..'\n'
  end
  h.ctx={valid=function() return true end,script=function(_,source,done)
    h.scripts[#h.scripts+1]=source
    local artifactDir=os.getenv('WARP_TEST_ARTIFACT_DIR')
    if artifactDir then
      local name=source==Finder.enumerationScript and 'enumeration' or (source:find('make new Finder window',1,true) and 'creation' or 'reuse')
      local f=assert(io.open(artifactDir..'/finder-'..name..'.applescript','w')); assert(f:write(source)); f:close()
    end
    if source==Finder.enumerationScript then
      if options.failEnumeration then done(false,'','denied') else done(true,h:enumerate()) end
      return
    end
    assert(not source:find('activate',1,true) and not source:find('set bounds',1,true),'existing navigation must not change layout or activate Finder')
    if options.failMutation then done(false,'','navigation failed'); return end
    local id=tonumber(source:match('set w to Finder window id (%d+)'))
    local r
    if id then for _,entry in ipairs(h.rows) do if entry.finderID==id then r=entry end end; assert(r,'adapter confused Finder and HS IDs')
    else
      assert(source:find('set liveIDs to id of every window',1,true),'creation must fence changed enumeration')
      assert(source:find('set w to make new Finder window',1,true))
      h.created=h.created+1; r=make(100+h.created,400+h.created*50); h.rows[#h.rows+1]=r
    end
    r.target=assert(source:match('set target of w to %(POSIX file (.-) as alias%)'))
    -- Real Finder title changes when its target changes; geometry-based matching
    -- must use fresh evidence and never the stale pre-navigation window title.
    r.title='Navigated '..r.finderID
    h.mutated[#h.mutated+1]=r.finderID
    done(true,tostring(r.finderID))
  end}
  h.adapter=Finder.new({},h.shared)
  function h:restore(root)
    self.result=nil
    self.adapter:restore({finder={leftRoot=root or '/Projects/One'}},{},self.ctx,function(ok,err) self.result=ok; self.error=err end)
    return self.result,self.error
  end
  return h
end

test('two existing windows adopted despite different HS/AppleScript IDs; no creation',function()
  local h=harness({make(7,20),make(8,800)}); assert(h:restore()); assert(h.created==0)
  assert(h.adapter.roles.left.finderID==7 and h.adapter.roles.left.hsID==1007)
  assert(h.adapter.roles.right.finderID==8); assert(h.frames==0 and h.moves==0)
end)
test('one existing window adopts LEFT and creates only RIGHT',function()
  local h=harness({make(7,800)}); assert(h:restore()); assert(h.created==1 and h.adapter.roles.left.finderID==7 and h.adapter.roles.right.finderID==101)
end)
test('zero existing windows creates exactly two',function()
  local h=harness({}); assert(h:restore()); assert(h.created==2 and #h.rows==2)
end)
test('X sorting chooses extremes and leaves extra third window untouched',function()
  local h=harness({make(8,1300),make(9,650),make(7,10)}); assert(h:restore()); assert(h.created==0)
  assert(h.adapter.roles.left.finderID==7 and h.adapter.roles.right.finderID==8)
  assert(h.rows[2].target==nil and h.mutated[1]==7 and h.mutated[2]==8)
end)
test('active desktop is preferred over windows on another Space',function()
  local h=harness({make(1,-200,55),make(2,200),make(3,900),make(4,1500,55)}); assert(h:restore())
  assert(h.adapter.roles.left.finderID==2 and h.adapter.roles.right.finderID==3)
  assert(not h.rows[1].target and not h.rows[4].target)
end)
test('workflow switches retain role identities and only change directories',function()
  local h=harness({make(7,30),make(8,800)}); assert(h:restore('/Projects/One'))
  h.rows[1].frame={x=1100,y=140,w=420,h=570}; h.rows[2].frame={x=20,y=120,w=660,h=800}
  local layout=U.copy(h.rows[1].frame); assert(h:restore('/Projects/Two'))
  assert(h.created==0 and h.adapter.roles.left.finderID==7 and h.adapter.roles.right.finderID==8)
  assert(h.rows[1].target=='"/Projects/Two"' and h.rows[2].target==U.as(U.path('~/Downloads')))
  assert(h.frames==0 and h.moves==0 and h.rows[1].frame.x==layout.x and h.rows[1].frame.w==layout.w)
  assert(h.shared.finder.left.bounds.x==1100 and h.shared.finder.left.frame.w==420/1600)
end)
test('reload discards runtime identities and re-adopts without duplicates',function()
  local h=harness({make(7,30),make(8,800)}); assert(h:restore())
  local C=require('warp.config'); local cfg=assert(C.validate({one={label='One',key='1'}}))
  local recovered=require('warp.state').sanitize({version=1,workflows={},shared=h.shared},cfg)
  assert(recovered.shared.finder.left.finderID==nil and recovered.shared.finder.left.windowID==nil)
  h.adapter=Finder.new({},recovered.shared); assert(h:restore()); assert(h.created==0)
end)
test('existing windows ignore stale saved frames',function()
  local shared={finder={left={frame={x=0,y=0,w=1,h=1},screenUUID='missing'},right={frame={x=0,y=0,w=1,h=1}}}}
  local h=harness({make(1,10),make(2,800)},shared); assert(h:restore()); assert(h.frames==0 and h.moves==0)
end)
test('only reconstructed role receives saved layout',function()
  local saved={frame={x=0.55,y=0.1,w=0.4,h=0.7},screenUUID='main'}
  local h=harness({make(1,10)},{finder={right=saved}}); assert(h:restore()); assert(h.created==1 and h.frames==1 and h.moves==1)
  assert(h.rows[1].frame.x==10 and math.abs(h.rows[2].frame.x-880)<0.001)
end)
test('AppleScript-only discovery reuses windows when all HS sources miss them',function()
  local h=harness({make(7,10),make(8,800)},nil,{noHS=true}); assert(h:restore()); assert(h.created==0 and #h.mutated==2)
  assert(h.adapter.roles.left.hsID==nil and h.shared.finder.left.finderID==7)
end)
test('enumeration failure never creates or mutates windows',function()
  local h=harness({},nil,{failEnumeration=true}); assert(not h:restore()); assert(h.created==0 and #h.mutated==0)
end)
test('desktop, modal, floating and fullscreen windows are excluded',function()
  local a,b,c,d=make(1,0),make(2,20),make(3,50),make(4,80)
  a.kind='desktop'; b.modal=true; c.floating=true; d.fullscreen=true
  local h=harness({a,b,c,d,make(5,200),make(6,900)}); assert(h:restore()); assert(h.created==0)
  assert(h.adapter.roles.left.finderID==5 and h.adapter.roles.right.finderID==6)
  for i=1,4 do assert(not h.rows[i].target) end
end)
test('diagnostics report sources and proposed roles without mutation or adoption',function()
  local h=harness({make(7,10),make(8,800)}); local report
  h.adapter:debug(h.ctx,function(value) report=value end)
  assert(report.wouldAdopt.left==7 and report.wouldAdopt.right==8)
  assert(report.windows[1].sources.AppleScript and report.windows[1].sources.AX and report.windows[1].hsID==1007)
  assert(h.created==0 and #h.mutated==0 and next(h.adapter.roles)==nil and next(h.shared)==nil)
end)
test('escaped window titles round-trip and malformed snapshots fail closed',function()
  local r=make(1,10); r.title='100%\tName\n"quoted"\r'
  local h=harness({r}); assert(Finder.parse(h:enumerate())[1].title==r.title)
  assert(not pcall(Finder.parse,'permission denied')); assert(not pcall(Finder.parse,'WARP_FINDER_V1\ncorrupt\n'))
end)
test('failed or uncorrelated Finder primary never enters Mission Control',function()
  spaceCalls=0; local win={focus=function() error('failed Finder must not focus') end}
  assert(Spaces.primary({primary='finder'},{{id=99}},{{adapter='finder',identity='left',win=win}},{finder=false}))
  assert(Spaces.primary({primary='finder'},{{id=99}},{},{finder=true})); assert(spaceCalls==0)
end)
test('successful Finder primary focuses LEFT directly with no gotoSpace',function()
  spaceCalls=0; local focused
  local live={{adapter='finder',identity='right',win={focus=function() focused='right' end}},{adapter='finder',identity='left',win={focus=function() focused='left' end}}}
  assert(Spaces.primary({primary='finder'},{{id=99}},live,{finder=true})); assert(focused=='left' and spaceCalls==0)
end)
test('independent discovery sources retain AX evidence after application enumeration fails',function()
  local original=hs.application
  local app={bundleID=function() return 'com.apple.finder' end,pid=function() return 99 end,allWindows=function() error('app enumeration unavailable') end}
  local win={application=function() return app end,id=function() return 900 end,title=function() return 'Folder' end,frame=function() return {x=20,y=60,w=500,h=600} end,screen=function() return screen end,isStandard=function() return true end,isFullScreen=function() return false end}
  hs.application={get=function() return app end}
  hs.axuielement={applicationElement=function() return {attributeValue=function() return {{asHSWindow=function() return win end}} end} end}
  local evidence,errors=realFinderEvidence()
  assert(#evidence==1 and evidence[1].sources.AX and evidence[1].hsID==900 and #errors==1)
  hs.application=original
end)
test('ambiguous duplicate geometry never guesses a Hammerspoon identity',function()
  local h=harness({make(1,50),make(2,50)}); h.rows[2].title=h.rows[1].title
  local rows=Finder.merge(Finder.parse(h:enumerate()),W.finderEvidence())
  assert(not rows[1].hsID and not rows[2].hsID)
  assert(h:restore()); assert(h.created==0)
end)
print('PASS: '..total..' Finder regression tests; no live Finder mutation')
