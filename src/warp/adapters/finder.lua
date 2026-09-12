local U=require('warp.util')
local W=require('warp.windows')
local S=require('warp.screens')
local M={}
local roles={'left','right'}

-- Read-only Finder dictionary enumeration. Escaped text fields keep tabs/newlines
-- in window names from corrupting the line protocol. Never swallow a partial scan.
M.enumerationScript=[[
on replaceText(needle, replacement, value)
  set AppleScript's text item delimiters to needle
  set pieces to text items of value
  set AppleScript's text item delimiters to replacement
  set value to pieces as text
  set AppleScript's text item delimiters to ""
  return value
end replaceText
on encodeText(value)
  set value to my replaceText("%", "%25", value)
  set value to my replaceText(tab, "%09", value)
  set value to my replaceText(linefeed, "%0A", value)
  return my replaceText(return, "%0D", value)
end encodeText
set output to "WARP_FINDER_V1" & linefeed
tell application "Finder"
  repeat with w in every window
    set windowKind to "other"
    if class of w is Finder window then set windowKind to "finder"
    if class of w is desktop window then set windowKind to "desktop"
    set b to bounds of w
    set output to output & (id of w as text) & tab & windowKind & tab & (item 1 of b as text) & tab & (item 2 of b as text) & tab & (item 3 of b as text) & tab & (item 4 of b as text) & tab & (modal of w as text) & tab & (floating of w as text) & tab & (collapsed of w as text) & tab & my encodeText(name of w as text) & linefeed
  end repeat
end tell
return output
]]

function M.parse(output)
  assert(type(output)=='string','Finder enumeration returned no text')
  output=output:gsub('\r\n','\n')
  assert(output:match('^WARP_FINDER_V1\n'),'invalid Finder enumeration header')
  local rows,seen={},{}
  for line in output:sub(#'WARP_FINDER_V1\n'+1):gmatch('[^\n]+') do
    local id,kind,x,y,right,bottom,modal,floating,collapsed,title=line:match('^(%d+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)$')
    id=tonumber(id); x=tonumber(x); y=tonumber(y); right=tonumber(right); bottom=tonumber(bottom)
    assert(id and not seen[id] and x and y and right and bottom,'invalid/duplicate Finder window row')
    for _,v in ipairs({x,y,right,bottom}) do assert(v==v and math.abs(v)<math.huge,'invalid Finder bounds') end
    for _,v in ipairs({modal,floating,collapsed}) do assert(v=='true' or v=='false','invalid Finder window flag') end
    seen[id]=true
    rows[#rows+1]={finderID=id,kind=kind,frame={x=x,y=y,w=right-x,h=bottom-y},
      modal=modal=='true',floating=floating=='true',collapsed=collapsed=='true',
      title=title:gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end),sources={AppleScript=true}}
  end
  return rows
end
local function sameFrame(a,b)
  if not a or not b then return false end
  for _,k in ipairs({'x','y','w','h'}) do
    if type(a[k])~='number' or type(b[k])~='number' or math.abs(a[k]-b[k])>3 then return false end
  end
  return true
end
local function activeContext()
  local ids={}
  local ok,spaces=pcall(hs.spaces.activeSpaces)
  if ok then for _,id in pairs(spaces or {}) do ids[id]=true end end
  return ids
end
-- Finder IDs and CG/Hammerspoon IDs are independent namespaces. Correlate only
-- unique title+geometry pairs, never numeric coincidence or ordering.
function M.merge(rows,evidence)
  local active=activeContext()
  local matchCounts={}
  for _,row in ipairs(rows) do
    row.matches={}
    for _,e in ipairs(evidence) do
      if row.title==e.title and sameFrame(row.frame,e.frame) then
        row.matches[#row.matches+1]=e; matchCounts[e]=(matchCounts[e] or 0)+1
      end
    end
  end
  local matched={}
  for _,row in ipairs(rows) do
    if #row.matches==1 and matchCounts[row.matches[1]]==1 then
      local e=row.matches[1]; matched[e]=true
      row.win=e.win; row.hsID=e.hsID; row.screenUUID=e.screenUUID; row.spaceIDs=e.spaceIDs; row.fullscreen=e.fullscreen; row.standard=e.standard
      for source in pairs(e.sources) do row.sources[source]=true end
    end
    row.matches=nil
    row.adoptable=row.kind=='finder' and not row.modal and not row.floating and row.frame.w>0 and row.frame.h>0 and row.standard~=false and row.fullscreen~=true
    row.current=false
    for _,id in ipairs(row.spaceIDs or {}) do if active[id] then row.current=true end end
    if row.fullscreen==nil then
      -- Finder's dictionary has no fullscreen property. A screen-filling window
      -- without AX evidence is ambiguous: preserve rather than commandeer it.
      for _,screen in ipairs(hs.screen.allScreens()) do
        if sameFrame(row.frame,screen:fullFrame()) then row.adoptable=false; row.reason='fullscreen status uncertain' end
      end
    end
    if not row.adoptable then row.reason=row.reason or 'not a normal Finder file-viewer window' end
  end
  local unmatched={}
  for _,e in ipairs(evidence) do if not matched[e] then unmatched[#unmatched+1]=e end end
  return rows,unmatched
end
-- Keep healthy session roles. Fill from the active desktop first; among equally
-- preferred candidates choose the leftmost and rightmost, leaving extras alone.
function M.choose(rows,previous)
  local chosen,used={},{}
  for _,role in ipairs(roles) do
    for _,row in ipairs(rows) do
      if previous[role] and row.finderID==previous[role].finderID and row.adoptable and not used[row.finderID] then chosen[role]=row; used[row.finderID]=true; break end
    end
  end
  local remaining={}
  for _,row in ipairs(rows) do if row.adoptable and not used[row.finderID] then remaining[#remaining+1]=row end end
  table.sort(remaining,function(a,b) if a.frame.x==b.frame.x then return a.finderID<b.finderID end; return a.frame.x<b.frame.x end)
  local preferred={}; for _,row in ipairs(remaining) do if row.current then preferred[#preferred+1]=row end end
  if not chosen.left and not chosen.right then
    local pool=#preferred>=2 and preferred or remaining
    if #preferred==1 and #remaining>1 then
      local other=remaining[1]==preferred[1] and remaining[#remaining] or remaining[1]
      pool={preferred[1],other}; table.sort(pool,function(a,b) return a.frame.x<b.frame.x end)
    end
    chosen.left=pool[1]; if #pool>1 then chosen.right=pool[#pool] end
  elseif not chosen.left then chosen.left=(#preferred>0 and preferred or remaining)[1]
  elseif not chosen.right then local pool=#preferred>0 and preferred or remaining; chosen.right=pool[#pool] end
  return chosen
end

function M.new(_,shared)
  local self={id='finder',roles={},pid=nil}
  local function scan(ctx,done)
    ctx:script(M.enumerationScript,function(ok,out,err)
      if not ok then done(nil,'Finder enumeration: '..tostring(err)); return end
      local parsed,rows=pcall(M.parse,out)
      if not parsed then done(nil,rows); return end
      local evidence,errors,pid=W.finderEvidence()
      local merged,unmatched=M.merge(rows,evidence)
      done({rows=merged,unmatched=unmatched,errors=errors,pid=pid})
    end)
  end
  local function remember(role,row)
    shared.finder=shared.finder or {}
    local previous=shared.finder[role] or {}
    local record=U.copy(previous)
    if row.win then record=W.capture(row.win,'finder',role,previous)
    else
      -- Even if AX cannot produce an hs.window, Finder bounds remain usable
      -- layout evidence. Infer the display by greatest geometric overlap.
      local best,area=nil,0; local f=row.frame
      for _,screen in ipairs(hs.screen.allScreens()) do
        local b=screen:frame()
        local overlap=math.max(0,math.min(f.x+f.w,b.x+b.w)-math.max(f.x,b.x))*math.max(0,math.min(f.y+f.h,b.y+b.h)-math.max(f.y,b.y))
        if overlap>area then best=screen; area=overlap end
      end
      if best then
        local b=best:frame()
        record.frame={x=(f.x-b.x)/b.w,y=(f.y-b.y)/b.h,w=f.w/b.w,h=f.h/b.h}; record.screenUUID=best:getUUID()
      end
      record.spaceIDs=nil
    end
    record.finderID=row.finderID; record.windowID=row.hsID; record.pid=self.pid
    record.bounds=U.copy(row.frame); record.title=row.title
    shared.finder[role]=record
    self.roles[role]={finderID=row.finderID,hsID=row.hsID,win=row.win}
  end
  function self:discover(workflow)
    if not workflow.finder then return {} end
    local evidence,_,pid=W.finderEvidence(); local out={}
    if self.pid~=pid then return out end
    for _,role in ipairs(roles) do
      local assigned=self.roles[role]
      for _,e in ipairs(evidence) do
        if assigned and assigned.hsID and e.win and e.hsID==assigned.hsID and e.standard then out[#out+1]={win=e.win,adapter='finder',identity=role}; break end
      end
    end
    return out
  end
  function self:checkpoint(workflow)
    shared.finder=shared.finder or {}
    for _,item in ipairs(self:discover(workflow)) do
      local previous=shared.finder[item.identity]
      local record=W.capture(item.win,'finder',item.identity,previous)
      record.finderID=self.roles[item.identity].finderID
      local f=item.win:frame(); record.bounds={x=f.x,y=f.y,w=f.w,h=f.h}
      shared.finder[item.identity]=record
    end
  end
  function self:debug(ctx,done)
    scan(ctx,function(snapshot,err)
      if not snapshot then
        local evidence,errors,pid=W.finderEvidence(); local windows={}
        for _,row in ipairs(evidence) do
          local entry={}; for k,v in pairs(row) do if k~='win' then entry[k]=U.copy(v) end end
          entry.adoptable=false; entry.reason='Finder scripting enumeration unavailable'; windows[#windows+1]=entry
        end
        done({error=err,windows=windows,sourceErrors=errors,pid=pid}); return
      end
      local chosen=M.choose(snapshot.rows,snapshot.pid and self.pid==snapshot.pid and self.roles or {})
      local result={windows={},sourceErrors=snapshot.errors,wouldAdopt={},pid=snapshot.pid}
      for _,role in ipairs(roles) do result.wouldAdopt[role]=chosen[role] and chosen[role].finderID or 'create missing role (if discovery complete)' end
      local function add(row)
        local entry={}; for k,v in pairs(row) do if k~='win' then entry[k]=U.copy(v) end end
        result.windows[#result.windows+1]=entry
      end
      for _,row in ipairs(snapshot.rows) do add(row) end
      for _,row in ipairs(snapshot.unmatched) do
        local copy={}; for k,v in pairs(row) do copy[k]=v end
        copy.adoptable=false; copy.reason='not uniquely correlated with a Finder scriptable window'; add(copy)
      end
      done(result)
    end)
  end
  function self:restore(workflow,_,ctx,done)
    if not workflow.finder then done(true); return end
    local left,right=workflow.finder.leftRoot,U.path('~/Downloads')
    if not U.directory(left) or not U.directory(right) then done(false,'Finder directory missing: '..left..' or '..right); return end
    local index=0
    local function nextRole()
      index=index+1; local role=roles[index]; if not role then done(true); return end
      -- Rescan before each role: a closed/new window is not mistaken for stale
      -- evidence, and a failed enumeration never licenses window creation.
      scan(ctx,function(snapshot,err)
        if not snapshot then done(false,err); return end
        if not snapshot.pid or self.pid~=snapshot.pid then self.roles={} end; self.pid=snapshot.pid
        local chosen=M.choose(snapshot.rows,self.roles)
        for _,r in ipairs(roles) do if chosen[r] then remember(r,chosen[r]) else self.roles[r]=nil end end
        local row=chosen[role]; local creating=not row
        if creating then
          for _,e in ipairs(snapshot.unmatched) do
            if e.standard and not e.fullscreen then done(false,'Finder discovery ambiguous; refusing to create a duplicate'); return end
          end
        end
        local saved=shared.finder and U.copy(shared.finder[role])
        local path=role=='left' and left or right
        local select
        if row then select='set w to Finder window id '..row.finderID
        else
          local ids={}; for _,r in ipairs(snapshot.rows) do ids[#ids+1]=tostring(r.finderID) end
          -- Fence the fallback against windows opened/closed after our scan.
          select='set expectedIDs to {'..table.concat(ids,', ')..'}\nset liveIDs to id of every window\nif (count liveIDs) is not (count expectedIDs) then error "Finder windows changed; retry switch"\nrepeat with liveID in liveIDs\nif (contents of liveID) is not in expectedIDs then error "Finder windows changed; retry switch"\nend repeat\nset w to make new Finder window'
        end
        local source='tell application "Finder"\n'..select..'\nif class of w is not Finder window then error "Not a Finder file-viewer window"\nset target of w to (POSIX file '..U.as(path)..' as alias)\nreturn id of w\nend tell'
        ctx:script(source,function(ok,out,why)
          if not ok then done(false,'Finder '..role..': '..tostring(why)); return end
          local id=tonumber(out); if not id or (row and id~=row.finderID) then done(false,'Finder returned an unexpected role ID'); return end
          self.roles[role]={finderID=id}
          -- No wait on hs.window.get(Finder ID): those are different namespaces.
          scan(ctx,function(updated,scanErr)
            if not updated then done(false,scanErr); return end
            local actual
            for _,r in ipairs(updated.rows) do if r.finderID==id then actual=r; break end end
            if not actual then done(false,'Finder role disappeared during navigation'); return end
            if creating and saved and saved.frame and actual.win and not actual.win:isFullScreen() then
              S.restore(actual.win,saved.frame,saved.screenUUID)
              local f=actual.win:frame(); actual.frame={x=f.x,y=f.y,w=f.w,h=f.h}
            end
            remember(role,actual)
            U.log('INFO','Finder '..role..' '..(creating and 'created' or 'reused')..' AppleScript ID '..id..' -> '..path)
            nextRole()
          end)
        end)
      end)
    end
    nextRole()
  end
  return self
end
return M
