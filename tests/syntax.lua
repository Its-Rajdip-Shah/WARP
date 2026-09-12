-- Files are enumerated explicitly so paths with spaces remain ordinary Lua strings.
local files={'src/init.lua','config/workflows.lua','config/settings.lua','tests/unit.lua','tests/syntax.lua','tests/finder_global.lua'}
local modules={'util','config','state','request','screens','ownership','windows','spaces','wheel','lifecycle','manager','adapters/owned','adapters/figma','adapters/docker','adapters/vscode','adapters/terminal','adapters/safari'}
for _,name in ipairs(modules) do files[#files+1]='src/warp/'..name..'.lua' end
for _,path in ipairs(files) do assert(loadfile(path)) end
print('PASS: syntax ('..#files..' Lua files)')
