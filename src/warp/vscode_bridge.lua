-- Optional zero-project-config companion transport. Bounded request polling only.
local M={}
function M.valid(d)
  return type(d)=='table' and (d.kind=='folder' or d.kind=='workspace') and type(d.path)=='string' and d.path:sub(1,1)=='/' and not d.path:find('[%c]')
end
function M.same(a,b) return M.valid(a) and M.valid(b) and a.kind==b.kind and a.path==b.path end
function M.new()
  local root=os.getenv('HOME')..'/.workflow-manager/vscode-bridge'
  local self={}
  function self:request(ctx,action,session,descriptor,done)
    if not hs.fs.attributes(root) then done(nil,'workspace companion unavailable'); return end
    local nonce=hs.host.uuid():gsub('-',''):lower()
    local request=root..'/request-'..nonce..'.json'
    local paths={request}
    local function cleanup() for _,p in ipairs(paths) do os.remove(p) end end
    ctx:onCancel(cleanup)
    local ok=hs.json.write({nonce=nonce,action=action,session=session,descriptor=descriptor,expires=math.floor(hs.timer.secondsSinceEpoch()*1000)+4000},request..'.tmp',true,true)
    if not ok or not os.rename(request..'.tmp',request) then os.remove(request..'.tmp'); done(nil,'companion request write failed'); return end
    local deadline=hs.timer.secondsSinceEpoch()+2
    local function poll()
      local responses={}
      for name in hs.fs.dir(root) do
        if name:match('^response%-'..nonce..'%-%x+%.json$') then
          local p=root..'/'..name; paths[#paths+1]=p
          local good,r=pcall(hs.json.read,p)
          if good and type(r)=='table' and r.nonce==nonce and (not session or r.session==session) then
            if action~='probe' or r.focused then responses[#responses+1]=r end
          end
        end
      end
      if action=='inventory' then
        if hs.timer.secondsSinceEpoch()>=deadline then cleanup(); done({windows=responses}); return end
        ctx:after(0.1,poll); return
      end
      if #responses==1 and (action~='probe' or hs.timer.secondsSinceEpoch()>=deadline) then cleanup(); done(responses[1]); return end
      if #responses>1 then cleanup(); done(nil,'ambiguous companion response'); return end
      if hs.timer.secondsSinceEpoch()>=deadline then cleanup(); done(nil,'companion response timed out'); return end
      ctx:after(0.1,poll)
    end
    ctx:after(0.15,poll)
  end
  return self
end
return M
