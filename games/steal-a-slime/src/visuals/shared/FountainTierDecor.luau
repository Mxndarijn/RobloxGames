--!strict
--[[
	FountainTierDecor (owner: Archer, FEATURES.FountainTiers)

	Where the fountain's tier decor stands. Pure: no Roblox APIs (Lune-safe, used by the render export).
	The look itself (ring / crest / tint / glow per tier) is FountainTiers.LOOKS; this only turns it into
	poses over WorldLayout's fountain.

	  ring   fountain_tier_ring on the ground round the silo axis (its posts sit at r 14.6, outside the
	         plinth r 13.1); the mesh's bbox centre is half its height up.
	  crest  fountain_tier_crest floating over the goo crown, spinning (SPIN rad/s) and bobbing (BOB studs).
]]

local FountainTiers = if script
	then require(script.Parent.Parent.Shared.FountainTiers)
	else require("../../shared/FountainTiers")
local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

export type Pose = { mesh: string, size: { number }, position: { number }, color: { number }, material: string }

local FountainTierDecor = {}

FountainTierDecor.CREST_GAP = 3 -- studs between the mesh top of the fountain and the crest's underside
FountainTierDecor.SPIN = 0.5 -- rad/s
FountainTierDecor.BOB = 0.35 -- studs, amplitude (one cycle every ~4 s)

local function pose(mesh: string, y: number, look: FountainTiers.Look): Pose
	local entry = MeshAssets.get(mesh)
	local size = if entry and entry.size then entry.size else { 1, 1, 1 }
	local c = WorldLayout.FOUNTAIN_CENTRE
	return {
		mesh = mesh,
		size = size,
		position = { c[1], c[2] + y + size[2] / 2, c[3] },
		color = look.color,
		material = look.material,
	}
end

-- The ring and the crest to show at `tier` (either may be nil; tier 1 shows neither).
function FountainTierDecor.poses(tier: number): { ring: Pose?, crest: Pose? }
	local look = FountainTiers.look(tier)
	return {
		ring = if look.ring then pose("fountain_tier_ring", 0, look) else nil,
		crest = if look.crest
			then pose("fountain_tier_crest", WorldLayout.FOUNTAIN_HEIGHT + FountainTierDecor.CREST_GAP, look)
			else nil,
	}
end

-- Crest height offset and yaw (radians) at time `t` seconds.
function FountainTierDecor.crestMotion(t: number): (number, number)
	return math.sin(t * math.pi / 2) * FountainTierDecor.BOB, (t * FountainTierDecor.SPIN) % (math.pi * 2)
end

return table.freeze(FountainTierDecor)
