--!strict
--[[
	Habitats (pure, FEATURES.Habitats, HABITATS.md)

	A pad whose slime sits on it shows that slime's habitat: layers
	that rise out of the cork stand's dish round the slime.

	  bed     a disc over the stand's goo bed in the theme's colour and
	          material (sand for the reef, snow for the ice...)
	  frame   the ring round the slime, one per rarity tier (wood for Common
	          up to white-gold for Divine); Secret, Celestial and Divine add a
	          glowing lip (the shared glow mesh, tinted, Neon)
	  theme   props on the back and sides of the rim that set the place
	          (Ember Rocks, Ocean Reef...), shared by the slimes of that theme
	  prop    one signature prop on the front of the rim, only this species

	A habitat id names all three: "<theme>.<tier>" or "<theme>.<tier>.<species>"
	("reef.5.captain_goo"). The server writes it on the pad as before; the
	client crossfades whole ids, so a swap changes every layer at once. An
	empty pad is BASE (no overlay). Ids are never saved.

	  Habitats.forSlime(slime)     the slime's habitat id
	  Habitats.forType(species, tier)
	  Habitats.resolve(id)         a valid id, else BASE (server and client)
	  Habitats.look(id)            parsed id: theme, frame, prop
	  Habitats.layers(id)          what to draw, frame first, prop last
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

type RGB = { number }

export type Theme = {
	id: string,
	name: string,
	mesh: string, -- habitat_theme_<id> (shared/modeling-kit)
	drop: number, -- studs the theme mesh hangs below the deck (drips over the dish rim); usually 0
	color: RGB, -- placeholder props and puff, RGB 0..255
	accent: RGB,
	bed: RGB, -- the disc over the stand's goo bed, inside the frame
	bedMaterial: string, -- its Enum.Material name
}

export type Frame = {
	tier: number,
	name: string,
	mesh: string, -- habitat_frame_<tier>
	color: RGB, -- placeholder ring
	glow: RGB?, -- the glowing lip's colour; nil = no lip
	shimmer: boolean, -- the lip cycles through the rainbow (Secret)
}

export type Look = { id: string, theme: Theme, frame: Frame, prop: string? }

export type LayerKind = "bed" | "frame" | "glow" | "theme" | "prop"
-- size: native W x H x D studs; offset: the bbox centre from the dish centre (mesh axes, Roblox X, Z)
export type OverlayMesh = { meshId: string, size: { number }, drop: number, offset: { number } }
export type Layer = {
	kind: LayerKind,
	mesh: string, -- "" for the bed (a primitive disc, nothing to upload)
	overlay: OverlayMesh?, -- nil until uploaded: the client draws a placeholder (frame, theme) or nothing
	color: RGB,
	accent: RGB,
	glow: RGB?, -- glow layer: its Neon colour
	material: string?, -- bed layer: its Enum.Material name
	shimmer: boolean,
}

export type PadState = { id: string, from: string, at: number }

local Habitats = {}

Habitats.BASE = "base"
Habitats.TRANSFORM_SECONDS = 1
Habitats.GLOW_MESH = "habitat_frame_glow"
-- The signature prop stands this far from the dish centre on the front of the rim (pad-local, toward the walkway).
Habitats.PROP_RADIUS = 3.15
-- Yaw (degrees) that turns a kit mesh's front (kit -Y, pad-local +Z) to the walkway side of the pad.
Habitats.FRONT_YAW = 180

local function theme(
	id: string,
	name: string,
	drop: number,
	color: RGB,
	accent: RGB,
	bed: RGB,
	bedMaterial: string
): Theme
	return table.freeze({
		id = id,
		name = name,
		mesh = `habitat_theme_{id}`,
		drop = drop,
		color = table.freeze(color),
		accent = table.freeze(accent),
		bed = table.freeze(bed),
		bedMaterial = bedMaterial,
	})
end

local THEMES: { Theme } = {
	theme("barnyard", "Barnyard", 0, { 205, 60, 50 }, { 245, 215, 120 }, { 226, 196, 120 }, "Sand"),
	theme("sweets", "Sweet Treats", 0, { 255, 170, 210 }, { 120, 230, 200 }, { 255, 190, 215 }, "SmoothPlastic"),
	theme("garden", "Flower Garden", 0, { 110, 180, 90 }, { 255, 140, 190 }, { 120, 190, 90 }, "Grass"),
	theme("forest", "Mushroom Forest", 0, { 120, 90, 60 }, { 215, 60, 55 }, { 100, 150, 80 }, "LeafyGrass"),
	theme("pond", "Lily Pond", 0, { 70, 170, 120 }, { 120, 200, 240 }, { 95, 180, 210 }, "Glass"),
	theme("royal", "Royal Court", 0, { 170, 40, 60 }, { 255, 215, 80 }, { 175, 45, 65 }, "Fabric"),
	theme("arcane", "Arcane Grotto", 0, { 110, 100, 130 }, { 190, 150, 255 }, { 135, 110, 185 }, "Marble"),
	theme("ember", "Ember Rocks", 0, { 70, 50, 50 }, { 255, 120, 30 }, { 140, 110, 100 }, "Basalt"),
	theme("ice", "Ice Floe", 0, { 180, 225, 245 }, { 255, 255, 255 }, { 232, 243, 255 }, "Snow"),
	theme("reef", "Ocean Reef", 0, { 240, 215, 155 }, { 255, 125, 140 }, { 240, 214, 160 }, "Sand"),
	theme("sky", "Sky Isle", 0, { 245, 248, 255 }, { 150, 205, 255 }, { 225, 238, 255 }, "SmoothPlastic"),
	theme("space", "Starry Space", 0, { 60, 60, 110 }, { 255, 225, 120 }, { 70, 72, 140 }, "Slate"),
	theme("tech", "Tech Lab", 0, { 150, 160, 175 }, { 80, 230, 255 }, { 155, 165, 182 }, "DiamondPlate"),
	theme("dojo", "Dojo", 0, { 120, 170, 90 }, { 225, 60, 50 }, { 205, 192, 132 }, "Fabric"),
	theme("spooky", "Spooky", 0, { 90, 80, 100 }, { 180, 110, 255 }, { 115, 95, 135 }, "Slate"),
	theme("vault", "Treasure Vault", 0, { 140, 110, 60 }, { 255, 210, 70 }, { 232, 188, 72 }, "Foil"),
	theme("party", "Party Stage", 0, { 60, 40, 90 }, { 255, 90, 200 }, { 120, 75, 165 }, "SmoothPlastic"),
}

local function frame(tier: number, name: string, color: RGB, glow: RGB?, shimmer: boolean?): Frame
	return table.freeze({
		tier = tier,
		name = name,
		mesh = `habitat_frame_{tier}`,
		color = table.freeze(color),
		glow = if glow then table.freeze(glow) else nil,
		shimmer = shimmer == true,
	})
end

-- One per Config.RARITIES tier (SlimeRoster.SECRET_TIER = 7).
local FRAMES: { Frame } = {
	frame(1, "Wood", { 168, 116, 63 }),
	frame(2, "Painted Wood", { 95, 174, 106 }),
	frame(3, "Stone", { 142, 151, 163 }),
	frame(4, "Copper", { 196, 122, 60 }),
	frame(5, "Gold", { 242, 194, 48 }),
	frame(6, "Silver and Gems", { 214, 224, 236 }),
	frame(7, "Shadow", { 45, 40, 60 }, { 255, 255, 255 }, true),
	frame(8, "Starry Glass", { 40, 44, 100 }, { 150, 130, 255 }),
	frame(9, "White Gold", { 255, 244, 214 }, { 255, 215, 110 }),
}

-- Every species in SlimeRoster -> its theme (tests/Habitats.spec checks none is missing).
local SPECIES_THEME: { [string]: string } = {
	-- Barnyard
	moo = "barnyard",
	lop = "barnyard",
	whiskers = "barnyard",
	moo_shroom = "barnyard",
	-- Sweet Treats
	gummy = "sweets",
	mochi = "sweets",
	cheddar = "sweets",
	flan = "sweets",
	soda = "sweets",
	rocky_road = "sweets",
	sushi = "sweets",
	-- Flower Garden
	sprout = "garden",
	bumble = "garden",
	prickles = "garden",
	bloom = "garden",
	sunny = "garden",
	gaia = "garden",
	-- Mushroom Forest
	pebble = "forest",
	mushie = "forest",
	truffle = "forest",
	elder_oak = "forest",
	-- Lily Pond
	bubbles = "pond",
	froggo = "pond",
	honey_toad = "pond",
	-- Royal Court
	king = "royal",
	sir_goo = "royal",
	dragon_king = "royal",
	-- Arcane Grotto
	amethyst = "arcane",
	goo_oracle = "arcane",
	goomancer = "arcane",
	chrono = "arcane",
	-- Ember Rocks
	blaze = "ember",
	imp = "ember",
	drako = "ember",
	phoenix = "ember",
	goozilla = "ember",
	-- Ice Floe
	pengoo = "ice",
	frostbite = "ice",
	snow_bunny = "ice",
	steam = "ice",
	yeti = "ice",
	-- Ocean Reef
	chomp = "reef",
	octo = "reef",
	catfish = "reef",
	captain_goo = "reef",
	kraken = "reef",
	queen_jelly = "reef",
	klawdius = "reef",
	abyss = "reef",
	-- Sky Isle
	zap = "sky",
	thunderbee = "sky",
	seraph = "sky",
	prism = "sky",
	aurora = "sky",
	kirin = "sky",
	isle = "sky",
	-- Starry Space
	cosmo = "space",
	eclipse = "space",
	lunara = "space",
	solaris = "space",
	nebulon = "space",
	star_emperor = "space",
	-- Tech Lab
	robo = "tech",
	cyber_ninja = "tech",
	mecha_goo = "tech",
	-- Dojo
	ninja = "dojo",
	origami = "dojo",
	kitsune = "dojo",
	-- Spooky
	boo = "spooky",
	pumpking = "spooky",
	nightwing = "spooky",
	-- Treasure Vault
	midas = "vault",
	jackpot = "vault",
	goo_god = "vault",
	-- Party Stage
	disco = "party",
	doodle = "party",
	glitch = "party",
}

-- Slimes without a species (merged before species existed): a theme by tier.
local TIER_THEME: { [number]: string } = {
	[1] = "garden",
	[2] = "garden",
	[3] = "barnyard",
	[4] = "sweets",
	[5] = "royal",
	[6] = "arcane",
	[7] = "arcane",
	[8] = "space",
	[9] = "sky",
}

local themeById: { [string]: Theme } = {}
for _, t in THEMES do
	themeById[t.id] = t
end
local frameByTier: { [number]: Frame } = {}
for _, f in FRAMES do
	frameByTier[f.tier] = f
end

Habitats.THEMES = table.freeze(THEMES)
Habitats.FRAMES = table.freeze(FRAMES)
Habitats.SPECIES_THEME = table.freeze(SPECIES_THEME)
Habitats.TIER_THEME = table.freeze(TIER_THEME)

function Habitats.propMesh(species: string): string
	return `habitat_prop_{species}`
end

-- Every kit mesh a habitat can draw (MeshSwap publishes a template for each uploaded one).
local MESHES: { string } = { Habitats.GLOW_MESH }
for _, f in FRAMES do
	table.insert(MESHES, f.mesh)
end
for _, t in THEMES do
	table.insert(MESHES, t.mesh)
end
local speciesIds: { string } = {}
for species in SPECIES_THEME do
	table.insert(speciesIds, species)
end
table.sort(speciesIds)
for _, species in speciesIds do
	table.insert(MESHES, Habitats.propMesh(species))
end
Habitats.MESHES = table.freeze(MESHES)

function Habitats.theme(id: string): Theme?
	return themeById[id]
end

function Habitats.frame(tier: number): Frame?
	return frameByTier[tier]
end

-- The parsed id, or nil for BASE and anything that isn't a valid habitat.
function Habitats.look(id: any): Look?
	if type(id) ~= "string" then
		return nil
	end
	local parts = string.split(id, ".")
	if #parts < 2 or #parts > 3 then
		return nil
	end
	local t = themeById[parts[1]]
	local f = frameByTier[tonumber(parts[2]) or -1]
	if not t or not f or `{f.tier}` ~= parts[2] then
		return nil
	end
	local prop = parts[3]
	if prop and SPECIES_THEME[prop] == nil then
		return nil
	end
	return { id = id, theme = t, frame = f, prop = prop }
end

-- A valid habitat id, else BASE: a pad never shows a look the tables lack (drift, a stale or bad attribute).
function Habitats.resolve(id: any): string
	return if Habitats.look(id) then id else Habitats.BASE
end

-- The uploaded mesh for kit name `mesh`: its meshId, native size, drop below the deck and bbox-centre offset (a
-- theme keeps its front clear, so its bbox is not centred on the dish; MeshAssets `offset` = {x, y, z}, y unused).
-- nil while not uploaded.
function Habitats.overlayMesh(mesh: string, drop: number?): OverlayMesh?
	local entry = MeshAssets.get(mesh)
	if not entry or not entry.meshId or not entry.size then
		return nil
	end
	local o = entry.offset
	return {
		meshId = entry.meshId,
		size = entry.size,
		drop = drop or 0,
		offset = if o then { o[1], o[3] } else { 0, 0 },
	}
end

-- What to draw for habitat `id`, in rise order: bed, frame, glow lip, theme props, signature prop. {} for BASE.
function Habitats.layers(id: string): { Layer }
	local look = Habitats.look(id)
	if not look then
		return {}
	end
	local t, f = look.theme, look.frame
	local out: { Layer } = {
		{
			kind = "bed",
			mesh = "",
			color = t.bed,
			accent = t.accent,
			material = t.bedMaterial,
			shimmer = false,
		},
		{
			kind = "frame",
			mesh = f.mesh,
			overlay = Habitats.overlayMesh(f.mesh),
			color = f.color,
			accent = f.color,
			shimmer = false,
		},
	}
	if f.glow then
		table.insert(out, {
			kind = "glow",
			mesh = Habitats.GLOW_MESH,
			overlay = Habitats.overlayMesh(Habitats.GLOW_MESH),
			color = f.glow,
			accent = f.glow,
			glow = f.glow,
			shimmer = f.shimmer,
		})
	end
	table.insert(out, {
		kind = "theme",
		mesh = t.mesh,
		overlay = Habitats.overlayMesh(t.mesh, t.drop),
		color = t.color,
		accent = t.accent,
		shimmer = false,
	})
	if look.prop then
		local mesh = Habitats.propMesh(look.prop)
		table.insert(out, {
			kind = "prop",
			mesh = mesh,
			overlay = Habitats.overlayMesh(mesh),
			color = t.color,
			accent = t.accent,
			shimmer = false,
		})
	end
	return out
end

-- Habitat for a slime type at rarity `tier` (the frame). The species' roster tier stands in for a missing or
-- out-of-range tier; a slime without a species gets its tier's theme and no signature prop.
function Habitats.forType(species: string?, tier: number?): string
	local entry = species and SlimeRoster.get(species)
	local frameTier = if tier and frameByTier[tier] then tier elseif entry then entry.tier else nil
	if not frameTier or not frameByTier[frameTier] then
		return Habitats.BASE
	end
	local themeId = species and SPECIES_THEME[species]
	if themeId then
		return `{themeId}.{frameTier}.{species}`
	end
	local fallback = TIER_THEME[frameTier]
	return if fallback then `{fallback}.{frameTier}` else Habitats.BASE
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

-- Client weights: habitat id -> 0..1 (how much of that look shows). BASE has no look.
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
