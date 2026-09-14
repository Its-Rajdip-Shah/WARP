local U=require('warp.util')
local M={}
function M.new()
  local self={id='safari',switcher=require('warp.safari_ax').new()}
  function self:discover(workflow)
    if not workflow.safari then return {} end
    local app=U.app('com.apple.Safari'); local main=app and app:mainWindow()
    if main and main:isStandard() then return {{win=main,adapter='safari',identity=workflow.safari.tabGroup}} end
    return {}
  end
  function self:restore(workflow,state,ctx,done)
    if not workflow.safari then done(true); return end
    self:stop()
    local target=workflow.safari.tabGroup
    local accepted,why=self.switcher:switch(target,function(ok,message)
      if not ctx:valid() then return end
      state.safari={tabGroup=target,verified=ok}
      U.log('SAFARI',target..' -> '..(ok and ('reached '..target) or message))
      done(ok,message)
    end,ctx)
    if not accepted then done(false,why) end
  end
  function self:stop()
    self.switcher:stop()
    if self.debugSwitcher then self.debugSwitcher:stop() end
  end
  return self
end
return M
