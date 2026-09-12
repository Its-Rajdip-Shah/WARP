local U=require('warp.util')
local W=require('warp.windows')
local M={}
-- Bounded AX walk, only named sidebar rows; never click page content or arbitrary text.
local function rows(app,name)
  local root=hs.axuielement.applicationElement(app)
  local queue, matches={{node=root,depth=0}}, {}
  local index=1
  while queue[index] and index<=700 do
    local item=queue[index]; index=index+1; local node=item.node
    local role=node:attributeValue('AXRole')
    if role=='AXRow' then
      local label=node:attributeValue('AXTitle') or node:attributeValue('AXDescription')
      local function hasLabel(n,depth)
        if n:attributeValue('AXValue')==name or n:attributeValue('AXTitle')==name then return true end
        if depth==0 then return false end
        for _,child in ipairs(n:attributeValue('AXChildren') or {}) do if hasLabel(child,depth-1) then return true end end
        return false
      end
      if label==name or hasLabel(node,2) then matches[#matches+1]=node end
    end
    if item.depth<9 and role~='AXWebArea' then for _,child in ipairs(node:attributeValue('AXChildren') or {}) do queue[#queue+1]={node=child,depth=item.depth+1} end end
  end
  return matches
end
function M.new()
  local self={id='safari'}
  function self:discover(workflow)
    if not workflow.safari then return {} end
    local app=U.app('com.apple.Safari'); local main=app and app:mainWindow()
    if main and main:isStandard() then return {{win=main,adapter='safari',identity=workflow.safari.tabGroup}} end
    return {}
  end
  function self:restore(workflow,state,ctx,done)
    local spec=workflow.safari; if not spec then done(true); return end
    if not hs.application.launchOrFocusByBundleID('com.apple.Safari') then done(false,'Safari unavailable'); return end
    ctx:wait('Safari window',function() return #W.list('safari')>0 end,function(ok,err)
      if not ok then done(false,err); return end
      local app=U.app('com.apple.Safari')
      if spec.menuPath then
        if not app:selectMenuItem(spec.menuPath) then done(false,'configured Safari menu path not found'); return end
      else
        local candidates=rows(app,spec.tabGroup)
        if #candidates~=1 then done(false,'Safari Tab Group sidebar row missing/ambiguous; show sidebar or configure exact menuPath'); return end
        local row=candidates[1]
        if row:attributeValue('AXSelected')~=true then
          local changed=row:setAttributeValue('AXSelected',true)
          if not changed then
            local pressed=false
            for _,action in ipairs(row:actionNames() or {}) do if action=='AXPress' then pressed=row:performAction('AXPress') ~= nil end end
            if not pressed then done(false,'Safari row is not selectable'); return end
          end
        end
      end
      ctx:wait('Safari Tab Group verification',function()
        local candidates=rows(app,spec.tabGroup)
        return #candidates==1 and candidates[1]:attributeValue('AXSelected')==true
      end,function(verified,why)
        state.safari={tabGroup=spec.tabGroup,verified=verified}
        done(verified,verified and nil or why..'; group switch could not be verified')
      end,2)
    end)
  end
  return self
end
return M
