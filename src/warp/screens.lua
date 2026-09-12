local M = {}
function M.find(uuid)
  for _, s in ipairs(hs.screen.allScreens()) do if s:getUUID() == uuid then return s,true end end
  return hs.screen.mainScreen() or hs.screen.primaryScreen(),false
end
function M.capture(win)
  local s=win:screen(); if not s then return end
  local f,b=win:frame(),s:frame()
  return {x=(f.x-b.x)/b.w,y=(f.y-b.y)/b.h,w=f.w/b.w,h=f.h/b.h},s:getUUID()
end
function M.restore(win, frame, uuid)
  local screen=M.find(uuid); if not screen then return end
  win:moveToScreen(screen,false,true,0)
  if frame then
    local b=screen:frame()
    local w=math.min(b.w,math.max(160,frame.w*b.w)); local h=math.min(b.h,math.max(100,frame.h*b.h))
    win:setFrame({x=b.x+math.max(0,math.min(b.w-w,frame.x*b.w)),y=b.y+math.max(0,math.min(b.h-h,frame.y*b.h)),w=w,h=h},0)
  end
end
return M
