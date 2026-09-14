-- Finder is refreshed by location, never snapshotted or owned.
local U=require('warp.util')
local M={}
function M.new()
  local self={id='finder'}
  function self:discover() return {} end
  function self:restore(workflow,_,ctx,done)
    local path=workflow.finder
    if not path then done(true);return end
    if not U.directory(path) then done(false,'missing Finder directory: '..path);return end
    if not ctx:valid() then return end
    local ok,result=hs.osascript.applescript([[
with timeout of 3 seconds
  tell application "Finder"
    close every Finder window
  end tell
end timeout]])
    if not ok then done(false,'Finder close: '..tostring(result));return end
    U.log('FINDER','close windows ok')
    ctx:after(0.3,function()
      U.log('FINDER','open path='..path)
      ctx:task('/usr/bin/open',{path},function(code,_,err)
        U.log('FINDER','open exit='..code)
        done(code==0,code~=0 and ('Finder open: '..err) or nil)
      end,3)
    end)
  end
  return self
end
return M
