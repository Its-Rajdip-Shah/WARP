-- Legacy DB/keyboard experiment, invoked only by explicit debugSafariSwitch calls.
-- Production workflow restore uses safari_ax.lua and never reads this database.
local Request=require('warp.request')
local M={}
-- Hex encodes titles so tabs/newlines cannot corrupt the row protocol.
M.query=[[SELECT w.id, COALESCE(w.active_tab_group_id, ''), hex(COALESCE(b.title, ''))
FROM windows w LEFT JOIN bookmarks b ON b.id = w.active_tab_group_id
WHERE w.date_closed IS NULL ORDER BY w.id;]]
function M.parse(output)
  local rows,seen={},{}
  for line in output:gmatch('[^\n]+') do
    local window,group,title=line:match('^(%d+)\t(%d*)\t(%x*)$')
    if not window or #title%2~=0 or seen[window] then return nil,'invalid sqlite row output' end
    seen[window]=true
    title=title:gsub('%x%x',function(pair) return string.char(tonumber(pair,16)) end)
    rows[#rows+1]={window=window,id=group,title=title}
  end
  if #rows==0 then return nil,'no open Safari windows' end
  return rows
end
-- Titles are display metadata; native window/group IDs identify transitions.
local function state(row) return row.window..':'..row.id end
function M.changed(before,after)
  local old,seen,changed={},{},{}
  for _,r in ipairs(before) do old[r.window]=r end
  for _,r in ipairs(after) do
    if not old[r.window] then return nil,'Safari DB window set changed' end
    seen[r.window]=true
    if state(r)~=state(old[r.window]) then changed[#changed+1]={before=old[r.window],after=r} end
  end
  for id in pairs(old) do if not seen[id] then return nil,'Safari DB window disappeared' end end
  return changed
end
local function log(message)
  print('[WARP][SAFARI] '..message:gsub('[%c]',function(c) return string.format('\\x%02x',c:byte()) end))
end
function M.new()
  local self={active=nil}
  function self:stop()
    if self.active then self.active:cancel(); self.active=nil; log('ABORT cancelled') end
  end
  function self:switch(target,done,parent)
    if self.active then return false,'Safari switch already active' end
    if type(target)~='string' or not target:find('%S') then return false,'target must be a non-empty string' end
    local ctx,ended
    local function finish(ok,message)
      if ended then return end; ended=true
      log(ok and ('reached '..target) or ('ABORT '..message))
      ctx:cancel(); if self.active==ctx then self.active=nil end
      if done then done(ok,message) end
    end
    ctx=Request.new(1,function() return self.active==ctx and (not parent or parent:valid()) and 1 or 0 end,function(err) finish(false,err) end)
    self.active=ctx
    if parent and parent.onCancel then parent:onCancel(function()
      ctx:cancel(); if self.active==ctx then self.active=nil end
    end) end
    local function frontmost()
      local app=hs.application.frontmostApplication()
      return app and app:bundleID()=='com.apple.Safari'
    end
    local function focus(force,callback)
      if not force and frontmost() then callback(); return end
      local attempts=0
      local function launch()
        attempts=attempts+1
        -- Same underlying action as the user's hyper+S app launcher.
        hs.application.launchOrFocus('Safari')
        local deadline=hs.timer.secondsSinceEpoch()+1
        local function check()
          if frontmost() then log('Safari focused'); callback()
          elseif hs.timer.secondsSinceEpoch()<deadline then ctx:after(0.05,check)
          elseif attempts<2 then launch()
          else finish(false,'cannot focus Safari after bounded retry') end
        end
        check()
      end
      launch()
    end
    local path=os.getenv('HOME')..'/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db'
    local function read(callback)
      ctx:task('/usr/bin/sqlite3',{'-readonly','-batch','-noheader','-separator','\t',path,M.query},function(code,out,err)
        if code~=0 then finish(false,'database read failed: '..err); return end
        local rows,why=M.parse(out)
        if not rows then finish(false,why); return end
        callback(rows)
      end,3)
    end
    local bound,original,seen=nil,nil,{}
    local hops,retries=0,0
    local hop
    hop=function(before,force)
      if hops>=8 then finish(false,'max hops reached'); return end
      focus(force,function()
        local interruptions=0
        local function keys()
          if hs.eventtap.isSecureInputEnabled() then finish(false,'secure input enabled'); return end
          hs.eventtap.keyStroke({'cmd'},'l')
          ctx:after(0.15,function()
            if not frontmost() then
              interruptions=interruptions+1
              if interruptions>2 then finish(false,'cannot retain Safari focus after bounded retry'); return end
              focus(true,keys); return
            end
            if hs.eventtap.isSecureInputEnabled() then finish(false,'secure input enabled'); return end
            hops=hops+1
            if not bound then log('discovery hop') end
            hs.eventtap.keyStroke({'cmd','shift'},'down')
            local started=hs.timer.secondsSinceEpoch()
            local deadline=started+6
            local candidate,candidateSince,sawTransition
            log('keyboard hop '..hops..' sent')
            log('waiting for DB transition...')
            local function poll()
              read(function(after)
                local changes,why=M.changed(before,after)
                if not changes then finish(false,why); return end
                if #changes>1 then finish(false,'multiple Safari DB rows changed; ambiguous'); return end
                local now=hs.timer.secondsSinceEpoch()
                if #changes==0 then
                  candidate=nil; candidateSince=nil
                  if hs.timer.secondsSinceEpoch()<deadline then ctx:after(0.1,poll)
                  else
                    if sawTransition then finish(false,'DB transition did not stabilize before timeout'); return end
                    log('no DB transition after '..math.floor((now-started)*1000)..'ms')
                    if retries<2 and hops<8 then
                      retries=retries+1; log('no DB progress; refocus/retry '..retries..'/2'); hop(before,true)
                    else finish(false,'no DB progress after bounded retry') end
                  end
                  return
                end
                local change=changes[1]; local row=change.after
                if bound and row.window~=bound then finish(false,'different Safari DB row changed; ambiguous'); return end
                sawTransition=true
                local observed=state(row)
                if candidate~=observed then
                  candidate=observed; candidateSince=now
                  log('DB changed after '..math.floor((now-started)*1000)..'ms: window='..row.window..' '..change.before.id..'/'..change.before.title..' -> '..row.id..'/'..row.title)
                  log('confirming stable state...')
                end
                if now>deadline then finish(false,'DB transition did not stabilize before timeout'); return end
                if now-candidateSince<0.4 then ctx:after(0.1,poll); return end
                log('stable after '..math.floor((now-candidateSince)*1000)..'ms')
                -- Only a stabilized, freshly read transition can authorize success or another hop.
                if not bound then
                  bound=row.window; original=state(change.before); seen[original]=true
                  log('bound db window='..bound..' '..change.before.id..'/'..change.before.title..' -> '..row.id..'/'..row.title)
                else log('hop '..hops..' '..change.before.id..'/'..change.before.title..' -> '..row.id..'/'..row.title) end
                retries=0
                if row.title==target then finish(true,'reached '..target); return end
                local current=state(row)
                if current==original then finish(false,'target not found after full cycle'); return end
                if seen[current] then finish(false,'repeated group state'); return end
                seen[current]=true; hop(after,false)
              end)
            end
            ctx:after(0.1,poll)
          end)
        end
        keys()
      end)
    end
    ctx:guard(function()
      log('target='..target)
      ctx:after(90,function() finish(false,'transaction timed out') end)
      focus(true,function()
        read(function(rows)
          local summary={}; for _,r in ipairs(rows) do summary[#summary+1]=r.window..':'..r.id..'/'..r.title end
          log('before={'..table.concat(summary,',')..'}')
          hop(rows,false)
        end)
      end)
    end)
    return true
  end
  return self
end
return M
