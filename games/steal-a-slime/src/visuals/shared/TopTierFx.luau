--!strict
--[[
	TopTierFx (owner: Archer)

	Preset data and curves for the Mythic (tier 6) and Secret (tier 7) looks (contract/slime-odds.md):
	  * FOUNTAIN_BEAM: the beam on the fountain crown while a Secret is wild
	  * eruption(t): camera shake amplitude and sky tint strength over the server-wide Secret "fountain eruption"
	  * pedestal(tier): the light (and the Secret's rising sparkles) under a Mythic / Secret pad slime, nil below
	    Mythic. Its disc is invisible (PEDESTAL_TRANSPARENCY): it only carries them, nothing flat shows on the pad.
	PlotVisuals builds and poses the parts in its existing frame loop. Pure: no services touched at load time.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

export type Pedestal = {
	diameter: number, -- studs, at size 1 (scaled by the slime's Size): the area the sparkles rise from
	brightness: number,
	range: number,
	column: number?, -- RareSparkle particles/s rising from the disc (Secret only)
}

local TopTierFx = {}

TopTierFx.MYTHIC_TIER = Config.SECRET_TIER - 1
TopTierFx.SECRET_TIER = Config.SECRET_TIER

-- A marker on the crown, not a sky pillar: at night a tall Neon beam reads as a glowing streak.
TopTierFx.FOUNTAIN_BEAM = table.freeze({
	height = 24,
	width = 1,
	transparency = 0.7,
})

TopTierFx.ERUPTION_SECONDS = 2
TopTierFx.SHAKE_STUDS = 0.35 -- peak camera offset
TopTierFx.TINT = Config.RARITIES[Config.SECRET_TIER].color
TopTierFx.TINT_SATURATION = 0.25 -- peak ColorCorrection Saturation
TopTierFx.TINT_NAME = "SecretBurstTint"
-- RareSpawnAt older than this when it replicates (late join, stream-in) plays no eruption.
TopTierFx.FRESH_SECONDS = 5

TopTierFx.PEDESTAL_TRANSPARENCY = 1 -- no rarity disc under a slime; the light and sparkles stay

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
	return type(tier) == "number"
		and tier >= TopTierFx.SECRET_TIER
		and type(at) == "number"
		and math.abs(now - at) <= TopTierFx.FRESH_SECONDS
end

return table.freeze(TopTierFx)
