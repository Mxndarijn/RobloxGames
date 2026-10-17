-- Server datamodel (play): the BorderTerrain flag. src/server/BorderTerrainView.luau sets it on workspace.Terrain:
-- nil before place() starts, false while the tiles are written, true when done.
local terrain = workspace.Terrain
local v = terrain:GetAttribute("BorderTerrain")
return { value = v, set = v == true, started = v ~= nil, workspace_value = workspace:GetAttribute("BorderTerrain") }
