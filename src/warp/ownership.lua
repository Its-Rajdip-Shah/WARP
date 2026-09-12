local U = require('warp.util')
local M = {bundles={vscode='com.microsoft.VSCode',terminal='com.apple.Terminal',figma='com.figma.Desktop',docker='com.docker.docker',safari='com.apple.Safari'}}
function M.owner(config,path)
  for id,w in pairs(config.workflows) do for _,root in ipairs(w.vscode and w.vscode.allowedRoots or {}) do if U.under(path,root) then return id end end end
end
function M.appOwners(config,adapter)
  local ids={}; for id,w in pairs(config.workflows) do for _,a in ipairs(w.apps) do if a.id==adapter then ids[#ids+1]=id end end end
  return ids
end
function M.spec(w,adapter) for _,a in ipairs(w.apps) do if a.id==adapter then return a end end end
-- Deliberate path protocol: no basename/title guesses or active-file -> project inference.
function M.vscodePath(win)
  local path=(win:title() or ''):match('%[WARP:(.-)%]')
  if path then local ok,p=pcall(U.path,path); if ok then return p end end
end
return M
