-- Repository-local bootstrap. Does not edit ~/.hammerspoon/init.lua.
local source=debug.getinfo(1,'S').source
assert(source:sub(1,1)=='@','WARP must be loaded from its src/init.lua file')
local root=source:sub(2):match('^(.*)/src/init%.lua$')
assert(root,'Cannot determine WARP repository root')
local prefix=root..'/src/?.lua;'..root..'/src/?/init.lua;'
if not package.path:find(prefix,1,true) then package.path=prefix..package.path end
local config,err=require('warp.config').load(root)
if not config then print('[WARP][ERROR] Config invalid: '..tostring(err)); return end
if _G.WARP and _G.WARP.stop then _G.WARP.stop() end
-- Clear only WARP modules for direct dofile reloads; leave other Hammerspoon utilities alone.
for name in pairs(package.loaded) do if name:match('^warp%.') then package.loaded[name]=nil end end
local manager=require('warp.manager').new(config)
local api={}
api.switchTo=function(id) return manager:switchTo(id) end
api.checkpoint=function(id) return manager:checkpoint(id) end
api.makeCold=function(id) return manager:makeCold(id) end
api.pin=function(id) return manager:pin(id,true) end
api.unpin=function(id) return manager:pin(id,false) end
api.nextSpace=function() return manager:navigate(1) end
api.previousSpace=function() return manager:navigate(-1) end
api.status=function() return manager:diagnostics() end
api.debugFinder=function() return manager:debugFinder() end
api.stop=function() return manager:stop() end
api.reload=function() return dofile(root..'/src/init.lua') end
api.previewWheel=function(enabled) manager.wheel.preview=enabled~=false end
_G.WARP=api
local ok,why=xpcall(function() manager:start() end,debug.traceback)
if not ok then manager:stop(); print('[WARP][ERROR] Startup: '..tostring(why)) end
return api
