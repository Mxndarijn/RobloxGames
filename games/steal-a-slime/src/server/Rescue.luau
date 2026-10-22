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
-- PvP guard (FEATURES.PvP): while under PvP control / just launched, the safe floor is this much higher, so a
-- launched player is put back well before the void and no PvP item can ever kill (fall / void).
Rescue.PVP_SAFE_Y = -20

function Rescue.shouldRescue(y: number, alive: boolean): boolean
	return alive and y < Rescue.KILL_PLANE_Y
end

-- `pvpActive` = under PvP control or within Config.PVP.LAUNCH_GUARD_SECONDS of a PvP launch.
function Rescue.shouldRescuePvp(y: number, alive: boolean, pvpActive: boolean): boolean
	if not alive or y ~= y then
		return false
	end
	return y < Rescue.KILL_PLANE_Y or (pvpActive and y < Rescue.PVP_SAFE_Y)
end

-- Is the void guard armed for a player: under PvP control, or `guardSeconds` after their last PvP launch.
function Rescue.pvpActive(now: number, lastLaunchAt: number?, controlUntil: number?, guardSeconds: number): boolean
	return (controlUntil ~= nil and now < controlUntil) or (lastLaunchAt ~= nil and now - lastLaunchAt <= guardSeconds)
end

-- Where to put a fallen character: their plot, else the hub spawn, else `fallback`.
function Rescue.target<T>(plotSpawn: T?, hubSpawn: T?, fallback: T): T
	return plotSpawn or hubSpawn or fallback
end

-- A rescue lands the player on their own plot, so only a plain wild catch may stay in their arms: a stolen slime
-- or the boss would be "delivered" by the fall itself.
function Rescue.dropsCarry(kind: string, boss: boolean?): boolean
	return kind == "stolen" or boss == true
end

return table.freeze(Rescue)
