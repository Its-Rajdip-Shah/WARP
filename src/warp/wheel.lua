local U=require('warp.util')
local M={}
function M.held(flags) return flags.ctrl and flags.alt and flags.cmd and not flags.shift end
function M.new(config,select)
  local self={visible=false,latched=false,preview=false}
  function self:dismiss()
    self.visible=false
    if self.keyTap then self.keyTap:stop() end
    if self.canvas then self.canvas:delete(); self.canvas=nil end
  end
  function self:show()
    if self.visible or #config.list==0 then return end
    local screen=hs.mouse.getCurrentScreen() or hs.screen.mainScreen(); if not screen then return end
    local b=screen:frame(); local size=math.min(620,b.w-40,b.h-40)
    local c=hs.canvas.new({x=b.x+(b.w-size)/2,y=b.y+(b.h-size)/2,w=size,h=size})
    c:level(hs.canvas.windowLevels.overlay)
    c:behavior({'canJoinAllSpaces','fullScreenAuxiliary','stationary','ignoresCycle'})
    c:clickActivating(false)
    c:appendElements({type='circle',action='fill',fillColor={white=0.07,alpha=0.94},frame={x=8,y=8,w=size-16,h=size-16}})
    c:appendElements({type='text',text=self.preview and 'WARP · PREVIEW' or 'WARP',textSize=20,textColor={white=0.9},textAlignment='center',frame={x=size/2-100,y=size/2-24,w=200,h=30}})
    c:appendElements({type='text',text='Hold ⌃ ⌥ ⌘ · Choose a number',textSize=11,textColor={white=0.6},textAlignment='center',frame={x=size/2-130,y=size/2+10,w=260,h=24}})
    local count=#config.list; local radius=size*0.33
    local width=math.min(150,2*radius*math.sin(math.pi/math.max(count,3))*0.92)
    for i,w in ipairs(config.list) do
      local angle=-math.pi/2+(i-1)*2*math.pi/count
      local x,y=size/2+radius*math.cos(angle),size/2+radius*math.sin(angle)
      c:appendElements({type='rectangle',action='fill',roundedRectRadii={xRadius=12,yRadius=12},fillColor={white=0.19,alpha=0.9},frame={x=x-width/2,y=y-32,w=width,h=64}})
      c:appendElements({type='text',text=w.key,textSize=21,textAlignment='center',textColor={red=0.4,green=0.78,blue=1},frame={x=x-width/2,y=y-29,w=width,h=27}})
      c:appendElements({type='text',text=w.label,textSize=count>6 and 10 or 12,textAlignment='center',textColor={white=0.95},frame={x=x-width/2+3,y=y+2,w=width-6,h=30}})
    end
    self.canvas=c; self.visible=true; c:show(); self.keyTap:start()
  end
  self.keyTap=hs.eventtap.new({hs.eventtap.event.types.keyDown},function(event)
    if not self.visible then return false end
    local key=hs.keycodes.map[event:getKeyCode()]
    if key=='escape' then self.latched=true; self:dismiss(); return true end
    if not M.held(event:getFlags()) then return false end
    local id=config.selectors[key]
    if id then
      self.latched=true; self:dismiss()
      if self.preview then U.log('INFO','Wheel preview selected '..id) else select(id) end
      return true
    end
    -- Letter hotkeys pass through unchanged; hide overlay while the other utility runs.
    self.latched=true; self:dismiss(); return false
  end)
  self.flagsTap=hs.eventtap.new({hs.eventtap.event.types.flagsChanged},function(event)
    local held=M.held(event:getFlags())
    if not held then self.latched=false; self:dismiss()
    elseif not self.latched then
      local ok=U.try('wheel',function() self:show() end)
      if not ok then self:dismiss(); self.latched=true end
    end
    return false
  end)
  function self:start() self.flagsTap:start() end
  function self:stop() self:dismiss(); self.flagsTap:stop() end
  return self
end
return M
