--!strict
--[[
	Habitats (pure, FEATURES.Habitats, HABITATS.md)

	Data table: slime type / family -> habitat id, and each habitat's overlay.
	The pad itself never changes: a pad whose slime sits on it gets that
	slime's habitat overlay (a themed frame ring and rim props on the cork stand's dish);
	an empty pad is BASE (no overlay). Habitat ids are never saved.

	  Habitats.forSlime(slime)     type (SlimeRoster id) > tier family > BASE
	  Habitats.resolve(id)         known id, else BASE (server and client)
	  Habitats.overlayMesh(id)     the overlay's uploaded mesh (MeshAssets),
	                               nil = draw the primitive placeholder
	  Habitats.transition(prev, target, now)
	                               server pad state; a change restamps `at`
	  Habitats.initialWeights(id)  client, first sight: final state, no tween
	  Habitats.stepWeights(w, id, dt)
	                               client: current id -> 1, every other -> 0
	                               at 1 / TRANSFORM_SECONDS

	No Roblox APIs at load time.
]]

local MeshAssets = if script then require(script.Parent.MeshAssets) else require("./MeshAssets")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

export type Habitat = {
	id: string,
	name: string,
	overlay: string?, -- shared/modeling-kit overlay mesh (habitat_<id>_overlay); nil = BASE, no overlay
	drop: number, -- studs the overlay hangs below the dish rim (drips down the stand); 0 = rests on the rim
	color: { number }, -- placeholder primitive colour and puff, RGB 0..255
	accent: { number }, -- placeholder accent and puff colour
}

export type PadState = { id: string, from: string, at: number }
export type OverlayMesh = { meshId: string, size: { number }, drop: number } -- size: native W x H x D studs

local Habitats = {}

Habitats.BASE = "base"
Habitats.TRANSFORM_SECONDS = 1

local function h(id: string, name: string, drop: number, color: { number }, accent: { number }): Habitat
	return table.freeze({
		id = id,
		name = name,
		overlay = if id == "base" then nil else `habitat_{id}_overlay`,
		drop = drop,
		color = table.freeze(color),
		accent = table.freeze(accent),
	})
end

local LIST: { Habitat } = {
	h("base", "Pad", 0, { 200, 200, 200 }, { 255, 255, 255 }),
	h("hay_nest", "Hay Nest", 0, { 222, 190, 110 }, { 250, 230, 160 }),
	h("mushroom_ring", "Mushroom Ring", 0, { 200, 60, 55 }, { 250, 240, 220 }),
	h("flower_bed", "Flower Bed", 0, { 120, 85, 55 }, { 255, 140, 190 }),
	h("barn_crate", "Barn Crate", 0, { 170, 120, 70 }, { 150, 50, 40 }),
	h("rodeo_barrel", "Rodeo Barrel", 0, { 140, 90, 50 }, { 120, 220, 110 }),
	h("syrup_pool", "Syrup Pool", 1.049, { 230, 150, 40 }, { 255, 210, 120 }),
	h("show_stool", "Show Stool", 0, { 70, 110, 200 }, { 255, 215, 80 }),
	h("candy_patch", "Candy Patch", 0, { 255, 170, 210 }, { 120, 230, 200 }),
	h("crystal_grotto", "Crystal Grotto", 0, { 110, 100, 130 }, { 190, 150, 255 }),
}

-- Look family per Config.RARITIES tier (SlimeRoster comments), 7 = SlimeRoster.SECRET_TIER.
local FAMILY_BY_TIER: { [number]: string } = {
	[1] = "field",
	[2] = "sprout",
	[3] = "critter",
	[4] = "horned",
	[5] = "royal",
	[6] = "crystal",
	[SlimeRoster.SECRET_TIER] = "secret",
}

local FAMILY: { [string]: string } = {
	field = "hay_nest",
	sprout = "flower_bed",
	critter = "barn_crate",
	horned = "candy_patch",
	royal = "show_stool",
	crystal = "crystal_grotto",
	secret = "crystal_grotto",
}

-- Per-type overrides (SlimeRoster ids); everything else uses its family.
local TYPE: { [string]: string } = {
	flan = "syrup_pool",
	bubbles = "syrup_pool",
	froggo = "syrup_pool",
	chomp = "syrup_pool",
	octo = "syrup_pool",
	mushie = "mushroom_ring",
	sprout = "flower_bed",
	prickles = "flower_bed",
	moo = "rodeo_barrel",
	cheddar = "candy_patch",
	midas = "hay_nest",
	boo = "mushroom_ring",
}

local byId: { [string]: Habitat } = {}
for _, habitat in LIST do
	byId[habitat.id] = habitat
end

Habitats.LIST = table.freeze(LIST)
Habitats.FAMILY_BY_TIER = table.freeze(FAMILY_BY_TIER)
Habitats.FAMILY = table.freeze(FAMILY)
Habitats.TYPE = table.freeze(TYPE)

function Habitats.get(id: string): Habitat?
	return byId[id]
end

-- A known habitat id, else BASE: a pad never shows a look the table lacks
-- (TYPE / FAMILY drift, a stale or bad attribute).
function Habitats.resolve(id: any): string
	return if type(id) == "string" and byId[id] then id else Habitats.BASE
end

-- The overlay's uploaded mesh: its MeshAssets meshId, native size and drop
-- below the deck. nil for BASE, unknown ids, or an overlay with no meshId yet;
-- HabitatFx then draws the primitive placeholder.
function Habitats.overlayMesh(id: string): OverlayMesh?
	local habitat = byId[id]
	if not habitat or not habitat.overlay then
		return nil
	end
	local entry = MeshAssets.get(habitat.overlay)
	if not entry or not entry.meshId or not entry.size then
		return nil
	end
	return { meshId = entry.meshId, size = entry.size, drop = habitat.drop }
end

-- Habitat for a slime type, given its tier for the family fallback.
function Habitats.forType(species: string?, tier: number?): string
	local typed = species and TYPE[species]
	if typed then
		return Habitats.resolve(typed)
	end
	local entry = species and SlimeRoster.get(species)
	local family = FAMILY_BY_TIER[if entry then entry.tier else tier or 0]
	return Habitats.resolve(family and FAMILY[family])
end

function Habitats.forSlime(slime: { species: string?, tier: number }): string
	return Habitats.forType(slime.species, slime.tier)
end

-- Server pad state. Same target keeps the old stamp; a new target restamps.
function Habitats.transition(prev: PadState?, target: string, now: number): PadState
	if prev and prev.id == target then
		return prev
	end
	return { id = target, from = if prev then prev.id else Habitats.BASE, at = now }
end

-- Client weights: habitat id -> 0..1 (how much of that overlay shows). BASE
-- has no overlay.
export type Weights = { [string]: number }

-- First sight of a pad (join in progress, streamed in): the final state.
function Habitats.initialWeights(id: string): Weights
	if id == Habitats.BASE then
		return {}
	end
	return { [id] = 1 }
end

-- Moves every weight toward its target by dt / TRANSFORM_SECONDS: `id` -> 1,
-- the rest -> 0 (dropped at 0). Returns a new table.
function Habitats.stepWeights(weights: Weights, id: string, dt: number): Weights
	local rate = dt / Habitats.TRANSFORM_SECONDS
	local out: Weights = {}
	for key, w in weights do
		if key ~= id then
			local nextW = w - rate
			if nextW > 0 then
				out[key] = nextW
			end
		end
	end
	if id ~= Habitats.BASE then
		out[id] = math.min(1, (weights[id] or 0) + rate)
	end
	return out
end

-- True once only `id` shows, fully.
function Habitats.isSettled(weights: Weights, id: string): boolean
	for key, w in weights do
		if key ~= id or w < 1 then
			return false
		end
	end
	return id == Habitats.BASE or weights[id] == 1
end

return table.freeze(Habitats)
