-- Never send lifecycle commands to the Docker engine. resource_aware currently
-- retains everything because container ownership/build safety is not provable.
return {new=function(config) return require('warp.adapters.owned').new('docker',config) end}
