-- Production native Tab Group switching. All state comes from the toolbar picker.
local Request=require('warp.request')
local U=require('warp.util')
local M={}
function M.attr(el,name)
  local ok,value=pcall(function() return el:attributeValue(name) end)
  if ok then return value end
end
local function walk(el,visit,depth)
  depth=depth or 0
  if depth>12 then return end
  if visit(el) then return true end
  local children=M.attr(el,'AXChildren')
  if type(children)=='table' then
    for _,child in ipairs(children) do if walk(child,visit,depth+1) then return true end end
  end
end
function M.findPicker(app)
  local found
  walk(app,function(el)
    local id=M.attr(el,'AXIdentifier')
    if M.attr(el,'AXRole')=='AXMenuButton' and type(id)=='string' and id:match('^TabGroupPickerButton') then
      found=el; return true
    end
  end)
  return found
end
function M.currentFromPicker(picker)
  local id=M.attr(picker,'AXIdentifier')
  local group=type(id)=='string' and id:match('^TabGroupPickerButton%?TabGroup=(.*)$') or nil
  if group=='' then return 'Local' end
  return group
end
function M.normalizeTitle(title)
  if type(title)~='string' then return nil end
  return title:match('^%d+ Tabs$') and 'Local' or title
end
function M.readOrder(app)
  local order,seen,collecting,checked={},{},false,nil
  walk(app,function(el)
    if M.attr(el,'AXRole')~='AXMenuItem' then return end
    local title=M.attr(el,'AXTitle')
    if type(title)~='string' then return end
    if title:match('^%d+ Tabs$') then collecting=true end
    if collecting and (title=='New Empty Tab Group' or title:match('^New Tab Group with ')) then return true end
    if collecting and title~='' then
      title=M.normalizeTitle(title)
      if M.attr(el,'AXMenuItemMarkChar')=='✓' then checked=title end
      if not seen[title] then seen[title]=true; order[#order+1]=title end
    end
  end)
  return order,checked
end
function M.route(order,current,target)
  local a,b
  for i,name in ipairs(order) do if name==current then a=i end; if name==target then b=i end end
  if not a then return nil,'current group not in picker order' end
  if not b then return nil,'target group not in picker order' end
  local forward,backward=(b-a)%#order,(a-b)%#order
  if forward<=backward then return {direction='NEXT',key='down',steps=forward} end
  return {direction='PREVIOUS',key='up',steps=backward}
end
function M.new()
  local self={}
  function self:stop() if self.active then self.active:cancel(); self.active=nil end end
  function self:switch(target,done,parent)
    if self.active then return false,'Safari switch already active' end
    if type(target)~='string' or not target:find('%S') then return false,'target must be a non-empty string' end
    local ctx,ended,menuOpen
    local function frontmost()
      local app=hs.application.frontmostApplication()
      return app and app:bundleID()=='com.apple.Safari'
    end
    local function closeMenu()
      if menuOpen and frontmost() then hs.eventtap.keyStroke({},'escape'); menuOpen=false end
    end
    local function finish(ok,message)
      if ended then return end; ended=true
      ctx:cancel(); if self.active==ctx then self.active=nil end
      if done then done(ok,message) end
    end
    ctx=Request.new(1,function() return self.active==ctx and (not parent or parent:valid()) and 1 or 0 end,function(err) finish(false,err) end)
    self.active=ctx
    ctx:onCancel(closeMenu)
    if parent then parent:onCancel(function() ctx:cancel(); if self.active==ctx then self.active=nil end end) end
    local function ready()
      if not frontmost() then finish(false,'Safari lost focus'); return false end
      if hs.eventtap.isSecureInputEnabled() then finish(false,'secure input enabled'); return false end
      return true
    end
    ctx:guard(function()
      local safari=hs.application.get('com.apple.Safari')
      if not safari then finish(false,'Safari not running'); return end
      local function root() return hs.axuielement.applicationElement(safari) end
      local function verify(deadline)
        if not ready() then return end
        local final=M.currentFromPicker(M.findPicker(root()))
        if final==target then finish(true,'reached '..target)
        elseif hs.timer.secondsSinceEpoch()>=deadline then finish(false,'AX verification expected '..target..', got '..tostring(final))
        else ctx:after(0.05,function() verify(deadline) end) end
      end
      local function burst(route,hop)
        if not ready() then return end
        hs.eventtap.keyStroke({'cmd','shift'},route.key)
        if hop<route.steps then ctx:after(0.06,function() burst(route,hop+1) end)
        else ctx:after(0.20,function() verify(hs.timer.secondsSinceEpoch()+0.75) end) end
      end
      local function lookup(app,picker)
        if not ready() then return end
        local current=M.currentFromPicker(picker)
        if not current then finish(false,'could not read current group'); return end
        if current==target then finish(true,'reached '..target); return end
        menuOpen=true
        local ok,result=pcall(function() return picker:performAction('AXPress') end)
        if not ok or not result then finish(false,'picker AXPress failed'); return end
        ctx:after(0.12,function()
          if not ready() then return end
          local order=M.readOrder(app)
          closeMenu()
          local route,why=M.route(order,current,target)
          if not route then finish(false,why); return end
          U.log('SAFARI',current..' -> '..target..': '..route.direction..' x'..route.steps)
          ctx:after(0.08,function() burst(route,1) end)
        end)
      end
      -- Foreground status can precede toolbar readiness during a Space transition.
      -- Recreate the AX root on every attempt; retain only the successful tree.
      local deadline=hs.timer.secondsSinceEpoch()+2.0
      local function waitForPicker()
        local app=root(); local picker=M.findPicker(app)
        if picker and frontmost() then lookup(app,picker); return end
        local remaining=deadline-hs.timer.secondsSinceEpoch()
        if remaining<=0 then finish(false,'picker not found before readiness timeout')
        else ctx:after(math.min(0.05,remaining),waitForPicker) end
      end
      if frontmost() then ctx:after(0.20,waitForPicker)
      else
        hs.application.launchOrFocus('Safari')
        waitForPicker()
      end
    end)
    return true
  end
  return self
end
return M
