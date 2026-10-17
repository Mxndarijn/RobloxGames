-- Server datamodel (play): workspace.Terrain:Clear() for the terrain-off A/B. Play session only, nothing is saved.
local ok, err = pcall(function()
	workspace.Terrain:Clear()
end)
return { cleared = ok, error = if ok then nil else tostring(err):sub(1, 200) }
