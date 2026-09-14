local M = {bundles={docker='com.docker.docker',vscode='com.microsoft.VSCode',terminal='com.apple.Terminal',figma='com.figma.Desktop',safari='com.apple.Safari'}}
function M.appOwners(config,adapter)
  local ids={}; for id,w in pairs(config.workflows) do for _,a in ipairs(w.apps) do if a.id==adapter then ids[#ids+1]=id end end end
  return ids
end
function M.spec(w,adapter) for _,a in ipairs(w.apps) do if a.id==adapter then return a end end end
return M
