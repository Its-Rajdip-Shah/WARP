local M={}
function M.due(workflow,state,now)
  return state.lifecycle=='WARM' and not state.pinned and not workflow.pinned and now-state.lastActive>=workflow.coldAfterMinutes*60
end
function M.new(manager)
  local self={}
  self.timer=hs.timer.doEvery(60,function()
    require('warp.util').try('lifecycle',function()
      if manager.switching then return end
      for id,w in pairs(manager.config.workflows) do if M.due(w,manager.store.data.workflows[id],hs.timer.secondsSinceEpoch()) then manager:makeCold(id) end end
    end)
  end)
  function self:stop() self.timer:stop() end
  return self
end
return M
