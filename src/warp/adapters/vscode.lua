local U=require('warp.util')
local O=require('warp.ownership')
local W=require('warp.windows')
local M={}
function M.new(config)
  local self={id='vscode'}
  function self:discover(workflow)
    local out,counts={},{}; if not workflow.vscode then return out end
    for _,win in ipairs(W.list('vscode')) do
      local path=O.vscodePath(win)
      if path and O.owner(config,path)==workflow.id then counts[path]=(counts[path] or 0)+1; out[#out+1]={win=win,adapter='vscode',identity=path} end
    end
    local unique={}; for _,item in ipairs(out) do if counts[item.identity]==1 then unique[#unique+1]=item end end
    return unique
  end
  function self:restore(workflow,state,ctx,done)
    if not workflow.vscode then done(true); return end
    local targets,seen={},{}
    local function add(p) if O.owner(config,p)==workflow.id and not seen[p] then seen[p]=true; targets[#targets+1]=p end end
    for _,item in ipairs(self:discover(workflow)) do add(item.identity) end
    for _,r in pairs(state.windows) do if r.adapter=='vscode' then add(r.identity) end end
    for _,p in ipairs(workflow.vscode.openRoots) do add(p) end
    table.sort(targets)
    local cli=U.executable({workflow.vscode.cliPath or '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code',os.getenv('HOME')..'/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code','/opt/homebrew/bin/code','/usr/local/bin/code'})
    local index=0
    local function nextRoot()
      index=index+1; local path=targets[index]; if not path then
        if #targets==0 then done(false,'no identifiable VS Code projects; configure [WARP:${rootPath}] title and open projects or set openRoots') else done(true) end
        return
      end
      local function find()
        for _,item in ipairs(self:discover(workflow)) do if item.identity==path then return item.win end end
      end
      local matches=0
      for _,candidate in ipairs(W.list('vscode')) do if O.vscodePath(candidate)==path then matches=matches+1 end end
      if matches>1 then done(false,'multiple VS Code windows expose the same root; preserved: '..path); return end
      local function restore(win)
        local r=state.windows[W.key('vscode',path)] or W.capture(win,'vscode',path)
        W.restore(win,r,ctx,function(ok,err) if ok then nextRoot() else done(false,err) end end)
      end
      local win=find(); if win then restore(win); return end
      if not cli then done(false,'VS Code CLI unavailable'); return end
      if not hs.fs.attributes(path) then done(false,'missing VS Code root: '..path); return end
      ctx:task(cli,{'--new-window',path},function(code,_,err)
        if code~=0 then done(false,'VS Code launch: '..err); return end
        ctx:wait('VS Code path '..path,find,function(ok,why) if ok then restore(find()) else done(false,why..'; check window.title marker') end end)
      end)
    end
    nextRoot()
  end
  function self:cold(_,state) state.retained=state.retained or {}; state.retained.vscode='safety_unknown: all editor windows preserved' end
  return self
end
return M
