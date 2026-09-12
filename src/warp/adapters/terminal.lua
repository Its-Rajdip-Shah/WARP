local U=require('warp.util')
local W=require('warp.windows')
local M={}
function M.new()
  local self={id='terminal'}
  function self:discover(workflow)
    local out={}; if not workflow.terminal then return out end
    local marker='[WARP:tmux:'..workflow.terminal.tmuxSession..']'
    for _,win in ipairs(W.list('terminal')) do if (win:title() or ''):find(marker,1,true) then out[#out+1]={win=win,adapter='terminal',identity=workflow.terminal.tmuxSession} end end
    return out
  end
  function self:restore(workflow,state,ctx,done)
    local spec=workflow.terminal; if not spec then done(true); return end
    local function restore()
      local item=self:discover(workflow)[1]
      local r=state.windows[W.key('terminal',spec.tmuxSession)] or W.capture(item.win,'terminal',spec.tmuxSession)
      W.restore(item.win,r,ctx,done)
    end
    local tmux=U.executable({spec.tmuxPath or '/opt/homebrew/bin/tmux','/usr/local/bin/tmux','/usr/bin/tmux'})
    if not tmux then done(false,'tmux missing; install or set terminal.tmuxPath'); return end
    -- Inspect pane commands for diagnostics only; never terminate shell children.
    local function inspect()
      ctx:task(tmux,{'list-panes','-a','-F','#{session_name}\t#{pane_current_command}'},function(code,out)
        if code==0 then
          state.terminalProcesses={}
          for session,command in out:gmatch('([^\n\t]+)\t([^\n]+)') do if session==spec.tmuxSession then state.terminalProcesses[#state.terminalProcesses+1]=command end end
        end
        if #self:discover(workflow)>0 then restore(); return end
        local command=U.quote(tmux)..' attach-session -t '..U.quote('='..spec.tmuxSession)
        local script='tell application "Terminal"\nset t to do script '..U.as(command)..'\nset custom title of t to '..U.as('[WARP:tmux:'..spec.tmuxSession..']')..'\nend tell'
        ctx:script(script,function(ok,_,err)
          if not ok then done(false,'Terminal: '..err); return end
          ctx:wait('Terminal tmux viewer',function() return #self:discover(workflow)>0 end,function(found,why) if found then restore() else done(false,why) end end)
        end)
      end)
    end
    ctx:task(tmux,{'has-session','-t','='..spec.tmuxSession},function(code)
      if code==0 then inspect(); return end
      if not U.directory(spec.root) then done(false,'missing terminal root: '..spec.root); return end
      ctx:task(tmux,{'new-session','-d','-s',spec.tmuxSession,'-c',spec.root},function(result,_,err) if result==0 then inspect() else done(false,'tmux: '..err) end end)
    end)
  end
  function self:cold(_,state) state.retained=state.retained or {}; state.retained.terminal='tmux sessions and all child processes preserved' end
  return self
end
return M
