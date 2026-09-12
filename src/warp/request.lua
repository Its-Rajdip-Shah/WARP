-- Owns all bounded asynchronous work for one switch. No idle polling.
local U = require('warp.util')
local M = {}
function M.new(id, current, onError)
  local self = {id=id,timers={},tasks={},cancelled=false}
  function self:valid() return not self.cancelled and current() == self.id end
  function self:guard(fn)
    if not self:valid() then return end
    local ok, err=xpcall(fn,debug.traceback); if not ok then onError(tostring(err)) end
  end
  function self:after(seconds, fn)
    if not self:valid() then return end
    local timer
    timer=hs.timer.doAfter(seconds,function() self.timers[timer]=nil; self:guard(fn) end)
    self.timers[timer]=true; return timer
  end
  function self:wait(label, predicate, done, timeout)
    local deadline=hs.timer.secondsSinceEpoch()+(timeout or 12)
    local function poll()
      if predicate() then done(true)
      elseif hs.timer.secondsSinceEpoch() >= deadline then done(false,label .. ' timed out')
      else self:after(0.25,poll) end
    end
    self:guard(poll)
  end
  function self:task(path, args, done, timeout)
    if not self:valid() then return end
    local task, timer, completed
    local function finish(code,out,err)
      if completed then return end; completed=true
      if timer then timer:stop(); self.timers[timer]=nil end
      if task then self.tasks[task]=nil end
      self:guard(function() done(code,out or '',err or '') end)
    end
    task=hs.task.new(path,finish,args)
    if not task then finish(-1,'','could not create task'); return end
    self.tasks[task]=true
    if not task:start() then finish(-1,'','could not start task'); return end
    timer=self:after(timeout or 15,function()
      -- Only terminate our short-lived helper, never the app/tmux/process tree.
      task:setCallback(nil); task:terminate(); finish(-1,'','helper timed out')
    end)
  end
  function self:script(source, done)
    self:task('/usr/bin/osascript',{'-e',source},function(code,out,err) done(code == 0,out,err) end)
  end
  function self:cancel()
    self.cancelled=true
    for t in pairs(self.timers) do t:stop() end; self.timers={}
    for t in pairs(self.tasks) do t:setCallback(nil); if t:isRunning() then t:terminate() end end; self.tasks={}
  end
  return self
end
return M
