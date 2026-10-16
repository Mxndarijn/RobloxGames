--!strict
--[[
	Habitats (pure, FEATURES.Habitats, HABITATS.md)

	Data table: slime type / family -> habitat id, and each habitat's kit look.
	A pad whose slime sits on it shows that slime's habitat; an empty pad is
	BASE (the pad as built today). Habitat ids are never saved.

	  Habitats.forSlime(slime)     type (SlimeRoster id) > tier family > BASE
	  Habitats.resolve(id)         known id, else BASE (server and client)
	  Habitats.slotMesh(id)        a mesh slot's uploaded mesh (MeshAssets),
	                               nil = keep the primitive placeholder
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
	kit: string?, -- shared/modeling-kit name of the look; nil = the pad's own stand
	newMesh: boolean, -- true = no kit model fits yet: a mesh slot Archer fills (MESH_SLOTS)
	seat: number, -- slime seat height on the look at native size (studs)
	color: { number }, -- placeholder primitive colour, RGB 0..255
	accent: { number }, -- placeholder accent colour
}

export type PadState = { id: string, from: string, at: number }
export type SlotMesh = { meshId: string, size: { number } } -- size: native W x H x D studs

local Habitats = {}

Habitats.BASE = "base"
Habitats.TRANSFORM_SECONDS = 1

local function h(
	id: string,
	name: string,
	kit: string?,
	newMesh: boolean,
	seat: number,
	color: { number },
	accent: { number }
): Habitat
	return table.freeze({
		id = id,
		name = name,
		kit = kit,
		newMesh = newMesh,
		seat = seat,
		color = table.freeze(color),
		accent = table.freeze(accent),
	})
end

local LIST: { Habitat } = {
	h("base", "Pad", nil, false, 0, { 200, 200, 200 }, { 255, 255, 255 }),
	h("hay_nest", "Hay Nest", "phoenix_pad_hay", false, 1.0, { 222, 190, 110 }, { 250, 230, 160 }),
	h("mushroom_ring", "Mushroom Ring", "phoenix_pad_mushroom", false, 3.0, { 200, 60, 55 }, { 250, 240, 220 }),
	h("flower_bed", "Flower Bed", "phoenix_pad_flower_bed", false, 2.4, { 120, 85, 55 }, { 255, 140, 190 }),
	h("barn_crate", "Barn Crate", "phoenix_pad_crate", false, 2.4, { 170, 120, 70 }, { 150, 50, 40 }),
	h("rodeo_barrel", "Rodeo Barrel", "phoenix_pad_barrel_top", false, 2.4, { 140, 90, 50 }, { 120, 220, 110 }),
	h("syrup_pool", "Syrup Pool", "phoenix_pad_goo", false, 1.5, { 230, 150, 40 }, { 255, 210, 120 }),
	h("show_stool", "Show Stool", "phoenix_pad_stool", false, 3.0, { 70, 110, 200 }, { 255, 215, 80 }),
	h("candy_patch", "Candy Patch", "habitat_candy_patch", true, 2.4, { 255, 170, 210 }, { 120, 230, 200 }),
	h("crystal_grotto", "Crystal Grotto", "habitat_crystal_grotto", true, 2.4, { 110, 100, 130 }, { 190, 150, 255 }),
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
	pudding = "syrup_pool",
	puddle = "syrup_pool",
	honey_queen = "syrup_pool",
	clover = "mushroom_ring",
	moonmilk = "mushroom_ring",
	rodeo_ram = "rodeo_barrel",
	gumdrop_titan = "candy_patch",
	golden_goose_goo = "hay_nest",
}

local byId: { [string]: Habitat } = {}
local slots: { string } = {}
for _, habitat in LIST do
	byId[habitat.id] = habitat
	if habitat.newMesh then
		table.insert(slots, habitat.id)
	end
end

Habitats.LIST = table.freeze(LIST)
Habitats.FAMILY_BY_TIER = table.freeze(FAMILY_BY_TIER)
Habitats.FAMILY = table.freeze(FAMILY)
Habitats.TYPE = table.freeze(TYPE)
-- Habitats that still need a new mesh from Archer (HABITATS.md "Mesh slots").
Habitats.MESH_SLOTS = table.freeze(slots)

function Habitats.get(id: string): Habitat?
	return byId[id]
end

-- A known habitat id, else BASE: a pad never shows a look the table lacks
-- (TYPE / FAMILY drift, a stale or bad attribute).
function Habitats.resolve(id: any): string
	return if type(id) == "string" and byId[id] then id else Habitats.BASE
end

-- The uploaded mesh for a mesh slot (newMesh habitat): its MeshAssets meshId
-- and native size. nil for BASE, the kit-pad looks, unknown ids, or a slot
-- whose kit has no meshId yet; HabitatFx then draws the primitive placeholder.
function Habitats.slotMesh(id: string): SlotMesh?
	local habitat = byId[id]
	if not habitat or not habitat.newMesh or not habitat.kit then
		return nil
	end
	local entry = MeshAssets.get(habitat.kit)
	if not entry or not entry.meshId or not entry.size then
		return nil
	end
	return { meshId = entry.meshId, size = entry.size }
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

-- Client weights: habitat id -> 0..1 (how much of that look shows). BASE has
-- no look; the base stand shows 1 - (largest weight).
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

-- Base stand visibility for a set of weights (1 = fully the base pad).
function Habitats.baseVisibility(weights: Weights): number
	local top = 0
	for _, w in weights do
		top = math.max(top, w)
	end
	return 1 - top
end

return table.freeze(Habitats)
