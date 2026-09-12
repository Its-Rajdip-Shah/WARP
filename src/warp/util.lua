local M = {}
function M.copy(v)
  if type(v) ~= 'table' then return v end
  local out = {}; for k, x in pairs(v) do out[k] = M.copy(x) end; return out
end
function M.path(p)
  assert(type(p) == 'string' and p ~= '', 'path must be a nonempty string')
  p = p:gsub('^~/', os.getenv('HOME') .. '/')
  assert(p:sub(1, 1) == '/' and not p:find('[%c]'), 'use an absolute or ~/ path')
  local parts = {}
  for part in p:gmatch('[^/]+') do
    if part == '..' then table.remove(parts) elseif part ~= '.' then parts[#parts + 1] = part end
  end
  return '/' .. table.concat(parts, '/')
end
function M.under(path, root) return path == root or path:sub(1, #root + 1) == root .. '/' or root == '/' end
function M.quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
function M.as(s) return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"' end
function M.directory(p) return hs.fs.attributes(p, 'mode') == 'directory' end
function M.executable(paths)
  for _, p in ipairs(paths) do if hs.fs.attributes(p, 'mode') == 'file' then return p end end
end
function M.app(bundle) return hs.application.get(bundle) end
function M.log(level, message) print('[WARP][' .. level .. '] ' .. tostring(message)) end
function M.try(label, fn)
  local ok, result = xpcall(fn, debug.traceback)
  if not ok then M.log('ERROR', label .. ': ' .. tostring(result)) end
  return ok, result
end
return M
