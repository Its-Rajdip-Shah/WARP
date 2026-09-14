-- Existing Figma window presentation. Titles identify only unambiguous live windows.
local U=require('warp.util')
local O=require('warp.ownership')
local W=require('warp.windows')
local M={}
function M.new(adapter,config)
  local self={id=adapter}
  function self:discover(workflow)
    if not O.spec(workflow,adapter) then return {} end
    local out,counts={},{}
    for _,win in ipairs(W.list(adapter)) do
      local identity=win:title() or ''; counts[identity]=(counts[identity] or 0)+1
      out[#out+1]={win=win,adapter=adapter,identity=identity}
    end
    local unique={}; for _,item in ipairs(out) do if counts[item.identity]==1 then unique[#unique+1]=item end end
    return unique
  end
  function self:restore(workflow,state,ctx,done)
    local spec=O.spec(workflow,adapter); if not spec then done(true); return end
    local function restoreAll()
      local live=self:discover(workflow); local i=0
      local function nextWindow()
        i=i+1; local item=live[i]; if not item then
          for _,saved in pairs(state.windows) do
            if saved.adapter==adapter then
              local found=false;for _,entry in ipairs(live) do if entry.identity==saved.identity then found=true end end
              if not found then done(false,'missing '..adapter..' document; exact reopen identity unavailable');return end
            end
          end
          done(true);return
        end
        local r=state.windows[W.key(adapter,item.identity)]
        if not r then
          -- An unfamiliar title is not proof that a missing document reopened.
          r=W.capture(item.win,adapter,item.identity)
          r.fullscreen=r.fullscreen or spec.preferredFullscreen == true
        end
        W.restore(item.win,r,ctx,function(ok,err) if not ok then done(false,err) else nextWindow() end end)
      end
      nextWindow()
    end
    if #self:discover(workflow)>0 then restoreAll(); return end
    if #W.list(adapter)>0 then done(false,'ambiguous '..adapter..' window titles; preserved');return end
    if not hs.application.launchOrFocusByBundleID(O.bundles[adapter]) then done(false,adapter..' unavailable'); return end
    ctx:wait(adapter..' window',function() return #self:discover(workflow)>0 end,function(ok,err) if ok then restoreAll() else done(false,err) end end)
  end
  function self:cold(_,state)
    state.retained=state.retained or {}; state.retained[adapter]='safety_unknown: UI and backend preserved'
  end
  return self
end
return M
