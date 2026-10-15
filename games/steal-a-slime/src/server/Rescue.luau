--!strict
--[[
	Rescue (pure)

	Kill-plane safety net: a character whose root falls below KILL_PLANE_Y
	is put back on its plot (or the hub SpawnLocation) instead of dying in
	the void. The adapter sets workspace.FallenPartsDestroyHeight to
	DESTROY_HEIGHT, far below the kill plane, so the engine never deletes a
	falling character before the server catches it (a 0.1 s check at
	terminal fall speed moves well under 100 studs).

	No Roblox APIs: runs unchanged under Lune.
]]

local Rescue = {}

Rescue.KILL_PLANE_Y = -60
Rescue.DESTROY_HEIGHT = -1000

function Rescue.shouldRescue(y: number, alive: boolean): boolean
	return alive and y < Rescue.KILL_PLANE_Y
end

-- Where to put a fallen character: their plot, else the hub spawn, else `fallback`.
function Rescue.target<T>(plotSpawn: T?, hubSpawn: T?, fallback: T): T
	return plotSpawn or hubSpawn or fallback
end

return table.freeze(Rescue)
