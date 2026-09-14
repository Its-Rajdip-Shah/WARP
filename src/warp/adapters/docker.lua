-- Docker Desktop presentation only; no engine, container, or quit commands.
local W=require('warp.windows')
local O=require('warp.ownership')
local M={}
function M.new()
  local self={id='docker'}
  function self:discover(workflow)
    if not O.spec(workflow,'docker') then return {} end
    local out={};for _,win in ipairs(W.list('docker')) do out[#out+1]={win=win,adapter='docker',identity=tostring(win:id())} end
    return out
  end
  function self:restore(workflow,state,ctx,done)
    local relevant=O.spec(workflow,'docker')~=nil
    local function apply()
      local live=W.list('docker');local errors={}
      for _,win in ipairs(live) do
        local ok,why=pcall(function()
          if win:isFullScreen() then return end
          if relevant then
            win:unminimize()
            local saved=state.windows[W.key('docker',tostring(win:id()))]
            if saved then require('warp.screens').restore(win,saved.frame,saved.screenUUID) end
          else win:minimize() end
          if win:isMinimized()==relevant then error('Docker UI visibility not verified') end
        end)
        if not ok then errors[#errors+1]=tostring(why) end
      end
      done(#errors==0,table.concat(errors,'; '))
    end
    if relevant and #W.list('docker')==0 then
      if not hs.application.launchOrFocusByBundleID('com.docker.docker') then done(false,'Docker Desktop UI unavailable');return end
      ctx:wait('Docker Desktop UI',function() return #W.list('docker')>0 end,function(ok,why) if ok then apply() else done(false,why) end end,3)
    else apply() end
  end
  return self
end
return M
