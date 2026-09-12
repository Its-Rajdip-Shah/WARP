local U=require('warp.util')
local S=require('warp.screens')
local O=require('warp.ownership')
local M={}
local filter
function M.start()
  if filter then return end
  local allowed={}; for _,bundle in pairs(O.bundles) do allowed[bundle]=true end
  filter=hs.window.filter.new(function(win)
    local app=win:application()
    return app and allowed[app:bundleID()] and win:isStandard()
  end)
  -- Keep the cross-Space cache alive through native Accessibility events.
  filter:subscribe({hs.window.filter.windowCreated,hs.window.filter.windowDestroyed},function() end)
end
function M.stop()
  if filter then filter:unsubscribeAll(); filter:pause(); filter=nil end
end
function M.list(adapter)
  local app=U.app(O.bundles[adapter]); if not app then return {} end
  local out,seen={},{}
  local function add(win)
    if win and win:id() and not seen[win:id()] and win:application() and win:application():bundleID()==O.bundles[adapter] and win:isStandard() then
      seen[win:id()]=true; out[#out+1]=win
    end
  end
  if filter then for _,win in ipairs(filter:getWindows()) do add(win) end end
  for _,win in ipairs(app:allWindows()) do add(win) end
  -- AXWindows may expose windows not yet observed by the filter after reload.
  if hs.axuielement then
    local ok,ax=pcall(hs.axuielement.applicationElement,app)
    if ok and ax then for _,element in ipairs(ax:attributeValue('AXWindows') or {}) do add(element:asHSWindow()) end end
  end
  return out
end
-- Finder-specific evidence collection. Keep source failures independent and retain
-- rejected AX windows for diagnostics; do not change discovery for other adapters.
function M.finderEvidence()
  local records,byID,errors={},{},{}
  local function attempt(source,fn)
    local ok,err=pcall(fn)
    if not ok then errors[#errors+1]=source..': '..tostring(err) end
  end
  local function add(win,source)
    if not win then return end
    attempt(source..' window',function()
      local app=win:application()
      if not app or app:bundleID()~=O.bundles.finder then return end
      local id=win:id(); if not id then return end
      local r=byID[id]
      if not r then
        local f=win:frame(); local screen=win:screen()
        r={win=win,hsID=id,title=win:title(),frame={x=f.x,y=f.y,w=f.w,h=f.h},
          standard=win:isStandard(),fullscreen=win:isFullScreen(),screenUUID=screen and screen:getUUID(),sources={}}
        byID[id]=r; records[#records+1]=r
        attempt('Finder windowSpaces',function() r.spaceIDs=hs.spaces.windowSpaces(id) end)
      end
      r.sources[source]=true
    end)
  end
  attempt('window filter',function() if filter then for _,win in ipairs(filter:getWindows()) do add(win,'window filter') end end end)
  local app=U.app(O.bundles.finder)
  if app then
    attempt('application',function() for _,win in ipairs(app:allWindows()) do add(win,'application') end end)
    attempt('AX',function()
      local ax=hs.axuielement.applicationElement(app)
      for _,element in ipairs(ax:attributeValue('AXWindows') or {}) do
        attempt('AX conversion',function()
          local win=element:asHSWindow()
          if win then add(win,'AX') else
            local p,s=element:attributeValue('AXPosition'),element:attributeValue('AXSize')
            records[#records+1]={title=element:attributeValue('AXTitle'),
              frame=p and s and {x=p.x,y=p.y,w=s.w,h=s.h} or nil,
              standard=element:attributeValue('AXSubrole')=='AXStandardWindow',
              fullscreen=element:attributeValue('AXFullScreen'),sources={AX=true},
              reason='AX element could not be converted to a Hammerspoon window'}
          end
        end)
      end
    end)
  end
  return records,errors,app and app:pid()
end
function M.key(adapter,identity) return adapter .. ':' .. identity end
function M.capture(win,adapter,identity,previous)
  local r={adapter=adapter,identity=identity,windowID=win:id(),pid=win:application():pid(),title=win:title(),fullscreen=win:isFullScreen()}
  r.screenUUID=win:screen() and win:screen():getUUID()
  if not r.fullscreen then r.frame=S.capture(win) elseif previous then r.frame=previous.frame end
  local ok,ids=pcall(hs.spaces.windowSpaces,win:id()); if ok then r.spaceIDs=ids end
  return r
end
function M.warm(win) if not win:isFullScreen() and not win:isMinimized() then win:minimize() end end
function M.restore(win,r,ctx,done)
  if not ctx:valid() then return end
  win:unminimize()
  local target,present=S.find(r.screenUUID)
  local moving=present and win:screen() and target:getUUID() ~= win:screen():getUUID()
  local function finish()
    ctx:wait('full-screen Space registration',function()
      if not win:id() then return false end
      if win:isFullScreen() ~= (r.fullscreen == true) then return false end
      if not r.fullscreen then return true end
      for _,id in ipairs(hs.spaces.windowSpaces(win:id()) or {}) do if hs.spaces.spaceType(id)=='fullscreen' then return true end end
      return false
    end,done)
  end
  local function place()
    S.restore(win,r.frame,r.screenUUID)
    if r.fullscreen then win:setFullScreen(true) end
    finish()
  end
  if win:isFullScreen() and (moving or not r.fullscreen) then
    win:setFullScreen(false)
    ctx:wait('exit full-screen',function() return not win:isFullScreen() end,function(ok,err) if ok then place() else done(false,err) end end)
  elseif win:isFullScreen() then finish()
  else place() end
end
return M
