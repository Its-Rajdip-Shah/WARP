-- No stable document URL is inferred from a Figma window title.
local O=require('warp.ownership')
local W=require('warp.windows')
return {new=function(config)
  local adapter=require('warp.adapters.owned').new('figma',config)
  local restore=adapter.restore
  function adapter:restore(workflow,state,ctx,done)
    if O.spec(workflow,'figma') then restore(self,workflow,state,ctx,done);return end
    local errors={}
    for _,win in ipairs(W.list('figma')) do
      local ok,why=pcall(function() W.warm(win) end)
      if not ok then errors[#errors+1]=tostring(why) end
    end
    done(#errors==0,table.concat(errors,'; '))
  end
  return adapter
end}
