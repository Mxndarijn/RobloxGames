--!strict
--[[
	TopTierFx (owner: Archer)

	Preset data and curves for the Mythic (tier 6) and Secret (tier 7) looks (contract/slime-odds.md):
	  * FOUNTAIN_BEAM: the beam on the fountain crown while a Secret is wild
	  * eruption(t): camera shake amplitude and sky tint strength over the server-wide Secret "fountain eruption"
	  * pedestal(tier): the glow under a Mythic / Secret pad slime (nil below Mythic)
	PlotVisuals builds and poses the parts in its existing frame loop. Pure: no services touched at load time.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local RareSpawn = if script then require(script.Parent.RareSpawn) else require("./RareSpawn")

export type Pedestal = {
	diameter: number, -- studs, at size 1 (scaled by the slime's Size)
	brightness: number,
	range: number,
	column: number?, -- RareSparkle particles/s rising from the disc (Secret only)
}

local TopTierFx = {}

TopTierFx.MYTHIC_TIER = Config.SECRET_TIER - 1
TopTierFx.SECRET_TIER = Config.SECRET_TIER

-- Under the shared beam cap so it reads as a marker on the crown, not a sky pillar.
TopTierFx.FOUNTAIN_BEAM = table.freeze({
	height = RareSpawn.MAX_BEAM_HEIGHT,
	width = RareSpawn.MAX_BEAM_WIDTH,
	transparency = RareSpawn.BEAM_TRANSPARENCY,
})

TopTierFx.ERUPTION_SECONDS = 2
TopTierFx.SHAKE_STUDS = 0.35 -- peak camera offset
TopTierFx.TINT = Config.RARITIES[Config.SECRET_TIER].color
TopTierFx.TINT_SATURATION = 0.25 -- peak ColorCorrection Saturation
TopTierFx.TINT_NAME = "SecretBurstTint"
-- RareSpawnAt older than this when it replicates (late join, stream-in) plays no eruption.
TopTierFx.FRESH_SECONDS = 5

local PEDESTALS: { [number]: Pedestal } = {
	[6] = table.freeze({ diameter = 4, brightness = 1.5, range = 10 }),
	[7] = table.freeze({ diameter = 4.6, brightness = 2.2, range = 12, column = 6 }),
}

function TopTierFx.pedestal(tier: number): Pedestal?
	return PEDESTALS[tier]
end

-- (shake studs, tint 0..1) at `t` seconds into the eruption: a fast rise, then a linear fade to 0 at
-- ERUPTION_SECONDS. Outside 0..ERUPTION_SECONDS both are 0.
function TopTierFx.eruption(t: number): (number, number)
	local total = TopTierFx.ERUPTION_SECONDS
	if t < 0 or t >= total then
		return 0, 0
	end
	local rise = math.min(1, t / 0.15)
	local fade = 1 - t / total
	local k = rise * fade
	return TopTierFx.SHAKE_STUDS * k, k
end

-- Whether a RareSpawn drop (workspace RareSpawnTier / RareSpawnAt) should play the eruption at server time `now`.
function TopTierFx.erupts(tier: any, at: any, now: number): boolean
	return tier == TopTierFx.SECRET_TIER and type(at) == "number" and math.abs(now - at) <= TopTierFx.FRESH_SECONDS
end

return table.freeze(TopTierFx)
