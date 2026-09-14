package.path='./src/?.lua;'..package.path
local W=require('warp.windows')
local predicate
hs={window={filter={new=function(fn)
  predicate=fn
  return {subscribe=function() end,unsubscribeAll=function() end,pause=function() end}
end}}}
W.start()
assert(predicate(nil)==false)
print('PASS: transient nil filter event is ignored')
assert(not predicate({application=function() return nil end}))
print('PASS: destroyed window without application is ignored')
local function window(bundle,standard)
  return {application=function() return {bundleID=function() return bundle end} end,isStandard=function() return standard end}
end
assert(predicate(window('com.microsoft.VSCode',true)))
assert(not predicate(window('com.microsoft.VSCode',false)))
assert(not predicate(window('unmanaged.app',true)))
W.stop()
print('PASS: managed standard-window filtering is unchanged')
print('PASS: 3 windows helper tests; no live GUI actions')
