local M={}
local function available()
  local ids={}; for uuid,list in pairs(hs.spaces.allSpaces() or {}) do for _,id in ipairs(list) do ids[id]=uuid end end; return ids
end
function M.rebuild(workflow, state, live)
  local valid, entries,seen=available(),{},{}
  local function add(role,identity,id,win)
    if valid[id] and not seen[id] then
      seen[id]=true; entries[#entries+1]={role=role,identity=identity,id=id,screenUUID=valid[id],windowID=win and win:id()}
    end
  end
  -- A shared logical desktop: prefer a live normal managed window, then a live user Space.
  local desktop
  for _,item in ipairs(live) do if not item.win:isFullScreen() then for _,id in ipairs(hs.spaces.windowSpaces(item.win:id()) or {}) do if hs.spaces.spaceType(id)=='user' then desktop=id; break end end end; if desktop then break end end
  local focused=hs.spaces.focusedSpace()
  if not desktop and valid[focused] and hs.spaces.spaceType(focused)=='user' then desktop=focused end
  if not desktop then
    local screen=hs.screen.mainScreen()
    for _,id in ipairs(screen and hs.spaces.spacesForScreen(screen) or {}) do if hs.spaces.spaceType(id)=='user' then desktop=id; break end end
  end
  if desktop then add('desktop','desktop',desktop) end
  local rank={}; for i,role in ipairs(workflow.spaceOrder) do rank[role]=i end
  table.sort(live,function(a,b) local x,y=rank[a.adapter] or 99,rank[b.adapter] or 99; if x==y then return a.identity<b.identity end; return x<y end)
  -- Register primary first for duplicate shared desktop IDs, while keeping desktop as reference.
  for _,item in ipairs(live) do for _,id in ipairs(hs.spaces.windowSpaces(item.win:id()) or {}) do add(item.adapter,item.identity,id,item.win) end end
  state.spaces=entries; return entries
end
function M.navigate(entries, direction)
  if #entries==0 then return false,'no registered Spaces' end
  local valid=available(); local filtered={}
  for _,e in ipairs(entries) do if valid[e.id] then filtered[#filtered+1]=e end end
  if #filtered==0 then return false,'registered Spaces no longer exist' end
  local current=hs.spaces.focusedSpace(); local index=direction>0 and 0 or 1
  for i,e in ipairs(filtered) do if e.id==current then index=i; break end end
  return hs.spaces.gotoSpace(filtered[((index-1+direction)%#filtered)+1].id)
end
function M.primary(workflow, entries,live)
  if workflow.primary=='none' then return true end
  for _,item in ipairs(live) do
    if item.adapter==workflow.primary then
      local ids=hs.spaces.windowSpaces(item.win:id()) or {}
      if ids[1] then local ok,err=hs.spaces.gotoSpace(ids[1]); if not ok then return false,err end end
      item.win:focus(); return true
    end
  end
  if entries[1] then return hs.spaces.gotoSpace(entries[1].id) end
  return false,'primary window and desktop unavailable'
end
return M
