--!strict
--[[
	BatRules (pure, CONTRACT.md §26 "Bat")

	Which player a Bat swing hits. The client sends NO target: the server takes the swinger's own root position and
	look vector and picks the nearest slime carrier inside SLAP_REACH and in front (Config.BAT.FACING_DOT; closer than
	CLOSE_STUDS the facing check is skipped). Reach, cooldown and the drop itself are CarryDrop.slap's (the shared
	slap rules), so the Bat can never do more than the old Slap button did. No Roblox APIs, so Lune tests it.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Vec = { X: number, Y: number, Z: number }
export type Candidate = { userId: number, position: Vec, carrying: boolean }

local BatRules = {}

-- Nearest slime carrier (not `selfUserId`) within reach and in front of `look` (a unit-ish horizontal vector), or nil.
-- `reach` defaults to SLAP_REACH (the boss uses Config.BOSS.HIT_REACH: it is far wider than a player).
function BatRules.pickTarget(
	origin: Vec,
	look: Vec,
	candidates: { Candidate },
	selfUserId: number,
	reach: number?
): (number?, number)
	local maxReach = reach or Config.SLAP_REACH
	local lookLength = math.sqrt(look.X * look.X + look.Z * look.Z)
	local best, bestDistance = nil :: number?, math.huge
	for _, c in candidates do
		if c.userId ~= selfUserId and c.carrying then
			local dx, dy, dz = c.position.X - origin.X, c.position.Y - origin.Y, c.position.Z - origin.Z
			local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
			if distance == distance and distance <= maxReach and distance < bestDistance then
				local flat = math.sqrt(dx * dx + dz * dz)
				local facing = distance <= Config.BAT.CLOSE_STUDS
					or (
						lookLength > 1e-6
						and flat > 1e-6
						and (look.X * dx + look.Z * dz) / (lookLength * flat) >= Config.BAT.FACING_DOT
					)
				if facing then
					best, bestDistance = c.userId, distance
				end
			end
		end
	end
	return best, bestDistance
end

return BatRules
