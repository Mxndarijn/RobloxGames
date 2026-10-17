-- Server datamodel (play): is the border terrain done? Since #267 BorderTerrainView sets the Workspace attribute
-- BorderTerrainReady = true when the last budgeted chunk is written (preferred signal). Older builds only have the
-- workspace.Terrain attribute BorderTerrain: nil before place() starts, false while the tiles are written, true when
-- done (still set by #267, used as the fallback).
local terrain = workspace.Terrain
local v = terrain:GetAttribute("BorderTerrain")
local ready = workspace:GetAttribute("BorderTerrainReady")
local source = if ready == true then "BorderTerrainReady" elseif v == true then "BorderTerrain" else nil
return {
	value = v,
	ready = ready,
	set = source ~= nil,
	source = source,
	started = v ~= nil or ready ~= nil,
	workspace_value = workspace:GetAttribute("BorderTerrain"),
}
