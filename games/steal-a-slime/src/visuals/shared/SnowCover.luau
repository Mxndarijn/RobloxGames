--!strict
--[[
	SnowCover (owner: Archer, FEATURES.Weather + FEATURES.SnowGround, SnowGround v2)

	The ground snow as pure maths, so the Lune tests and the render exporter share it with the client.
	`level` is 0..1: it builds up while it snows (BUILD_SECONDS from bare to full) and melts away after
	(MELT_SECONDS from full to bare).

	v2 draws NO snow layer: SnowGround tints the surfaces that are already there (the Ground, the border
	Terrain's materials, a light frost on paths / plaza / pads), so it adds zero parts and zero mesh slots, and
	nothing can z-fight or clip into a prop. `tints(level, snowing)` gives the 0..1 weight of snow white for each
	surface class; `lerpColor` mixes it into the ORIGINAL colour.

	Settling vs melting differ: while it snows every class follows the same eased level; once it stops the frost
	on paths / plaza / pads melts twice as fast (gone by half level) while the grass and the hills hold their
	snow to the end (a half-melted ground is whiter than a half-settled one).

	Flicker rules (SnowGround relies on them): the level is quantized to 1/QUANT_STEPS before use, so a colour is
	only rewritten when the quantized step (or the phase) changes; colours are always computed from the original
	colour, never the current one; weight 0 gives the original back bit for bit.
]]

local SnowCover = {}

SnowCover.BUILD_SECONDS = 50
SnowCover.MELT_SECONDS = 35

-- Runtime cost, checked against WorldLayout's budgets by tests/SnowCover.spec: v2 tints existing surfaces.
SnowCover.PART_COUNT = 0
SnowCover.MESH_SLOTS = 0

SnowCover.QUANT_STEPS = 128
SnowCover.SNOW_COLOR = table.freeze({ 248 / 255, 250 / 255, 255 / 255 })

-- Max weight of snow white per class at full cover. Grass and Terrain grass go fully white; the hills' rock
-- stays rocky; paths / plaza / pads only get a light frost so they stay readable.
SnowCover.GRASS_WEIGHT = 1
SnowCover.ROCK_WEIGHT = 0.35
SnowCover.FROST_WEIGHT = 0.25
-- While melting the grass and hills hold their snow: the eased level is raised to this power (< 1 keeps it higher
-- than on the way up, same at 0 and 1), so a half-melted ground is whiter than a half-settled one.
SnowCover.MELT_HOLD = 0.6
-- The frost is gone when the level has melted to this (the grass keeps its snow down to 0).
SnowCover.FROST_GONE_AT = 0.5

export type Tints = { grass: number, terrainGrass: number, rock: number, path: number }

function SnowCover.step(level: number, dt: number, snowing: boolean): number
	if snowing then
		return math.min(1, level + dt / SnowCover.BUILD_SECONDS)
	end
	return math.max(0, level - dt / SnowCover.MELT_SECONDS)
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Level snapped to 1/QUANT_STEPS: the only value the client turns into colours.
function SnowCover.quantize(level: number): number
	local steps = SnowCover.QUANT_STEPS
	return math.floor(math.clamp(level, 0, 1) * steps + 0.5) / steps
end

-- Weights of snow white per surface class, 0..1, smooth-stepped so the cover eases in and out. Exactly 0 at level 0.
function SnowCover.tints(level: number, snowing: boolean): Tints
	local e = smooth(level)
	local frostLevel = level
	if not snowing then
		e = e ^ SnowCover.MELT_HOLD
		local gone = SnowCover.FROST_GONE_AT
		frostLevel = (level - gone) / (1 - gone) -- melts first: 0 at half level, 1 at full
	end
	return {
		grass = SnowCover.GRASS_WEIGHT * e,
		terrainGrass = SnowCover.GRASS_WEIGHT * e,
		rock = SnowCover.ROCK_WEIGHT * e,
		path = SnowCover.FROST_WEIGHT * smooth(frostLevel),
	}
end

-- `from` mixed `weight` of the way to snow white (rgb 0..1). Weight <= 0 returns `from` unchanged (restore is
-- exact), weight >= 1 returns SNOW_COLOR.
function SnowCover.lerpColor(r: number, g: number, b: number, weight: number): (number, number, number)
	if weight <= 0 then
		return r, g, b
	end
	local snow = SnowCover.SNOW_COLOR
	if weight >= 1 then
		return snow[1], snow[2], snow[3]
	end
	return r + (snow[1] - r) * weight, g + (snow[2] - g) * weight, b + (snow[3] - b) * weight
end

-- Which tint class a BasePart belongs to: "grass" (the Ground and other big flat grass), "path" (path tiles,
-- the plaza disc, the pads) or nil (leave it alone). Hidden parts (Transparency 1: mesh slots) and small decor
-- (grass blades, bushes) are skipped on purpose.
function SnowCover.classify(
	name: string,
	material: string,
	inPaths: boolean,
	sizeX: number,
	sizeZ: number,
	transparency: number
): string?
	if transparency >= 1 then
		return nil
	end
	if inPaths or string.match(name, "^Pad_%d+$") then
		return "path"
	end
	if (material == "Grass" or material == "LeafyGrass") and sizeX * sizeZ >= 400 then
		return "grass"
	end
	return nil
end

-- True while there is something to show.
function SnowCover.visible(level: number): boolean
	return level > 0.001
end

-- Level a client starts at, and the phase. The server stamps when the current weather began (`startedAt`) and
-- when Snow last ended (`endedAt`), both in server time (workspace:GetServerTimeNow), so a late joiner lands
-- inside the build-up or the melt. Snow lasts at least 120 s (> BUILD_SECONDS), so a melt always starts from 1.
-- Missing stamps fall back sanely: snowing without a start counts as full, melting without an end as bare.
-- `pinned` (the SnowCoverDebug pin or the WeatherDebug preview) ignores the stamps and starts from 0.
-- The phase is just `snowing`: a joiner mid-melt gets (level, false) and so sees the frost cleared first.
function SnowCover.levelAt(snowing: boolean, startedAt: any, endedAt: any, now: number, pinned: boolean?): number
	if pinned then
		return 0
	end
	if snowing then
		if type(startedAt) ~= "number" then
			return 1
		end
		return math.clamp((now - startedAt) / SnowCover.BUILD_SECONDS, 0, 1)
	end
	if type(endedAt) ~= "number" then
		return 0
	end
	return math.clamp(1 - (now - endedAt) / SnowCover.MELT_SECONDS, 0, 1)
end

-- Level and phase for a late joiner in one call: ("settling" | "melting", level).
function SnowCover.phaseAt(
	snowing: boolean,
	startedAt: any,
	endedAt: any,
	now: number,
	pinned: boolean?
): (string, number)
	return if snowing then "settling" else "melting", SnowCover.levelAt(snowing, startedAt, endedAt, now, pinned)
end

-- True while level still has to move (Heartbeat can stop otherwise).
function SnowCover.settled(level: number, snowing: boolean): boolean
	return (snowing and level >= 1) or (not snowing and level <= 0)
end

return table.freeze(SnowCover)
