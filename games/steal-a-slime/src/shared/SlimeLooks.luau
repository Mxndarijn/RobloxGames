--!strict
--[[
	SlimeLooks (owner: Phoenix; v28 slime audit, docs/slime-audit-v28.md)

	Per-type look and animation profile for every SlimeRoster id. Pure data, no
	Roblox APIs.

	  SlimeLooks.get(id) -> Look?            colour, Enum.Material name, kit mesh
	  SlimeLooks.anim(id, state) -> Anim?    state = "idle" | "wobble" | "move"

	Colour: Genome.generate gives wild spawns their type's colour. Material:
	server SlimeMesh sets it on Body / Mesh of an unmutated slime (a mutation
	material always wins). Kit: the modeling-kit mesh the type is meant to use
	(MeshAssets name, uploaded); server SlimeMesh wears it, falling back to the
	shared slime package (Config.SLIME_MESH_ASSET_ID), then the procedural ball.

	Animations: slimes are not rigs and no AnimationIds exist. Every state is
	the procedural fallback played by the visuals client (VisualsClient step):
	idle = bob, wobble = tilt (wriggle while Carried), move = Escaping hops.
	The numbers mirror that controller. `animationId` stays nil until an
	uploaded animation replaces the fallback.
]]

export type Look = {
	id: string,
	color: { number }, -- RGB 0-255
	material: string, -- Enum.Material name
	kit: string, -- MeshAssets / modeling-kit name
}

export type AnimState = "idle" | "wobble" | "move"

export type Anim = {
	state: AnimState,
	source: "Procedural" | "Animation",
	animationId: string?, -- rbxassetid, nil = procedural fallback
	slimeState: string, -- model State attribute the controller plays it in
	frequency: number, -- radians per second (sin(t * frequency))
	amplitude: number, -- studs (idle, move) or radians (wobble), per unit Size
}

local KITS = table.freeze({
	"slime_base",
	"slime_acc_leaf",
	"slime_ears",
	"slime_horns",
	"slime_acc_crown",
	"slime_acc_crystal",
	"slime_wobble",
})

-- Materials a slime body may use; all are Enum.Material names.
local MATERIALS = table.freeze({ "SmoothPlastic", "Glass", "Foil", "Neon", "Plastic" })

local ANIM_STATES: { AnimState } = { "idle", "wobble", "move" }

local function l(id: string, color: { number }, material: string, kit: string): Look
	return table.freeze({ id = id, color = table.freeze(color), material = material, kit = kit })
end

local LOOKS: { [string]: Look } = {}
for _, look in
	{
		-- 1 Common: slime_base
		l("pudding", { 240, 196, 92 }, "SmoothPlastic", "slime_base"),
		l("clover", { 108, 196, 92 }, "SmoothPlastic", "slime_base"),
		l("oatmeal", { 222, 200, 160 }, "SmoothPlastic", "slime_base"),
		l("radish", { 236, 110, 150 }, "SmoothPlastic", "slime_base"),
		l("puddle", { 96, 168, 236 }, "SmoothPlastic", "slime_base"),
		l("haystack", { 230, 196, 80 }, "SmoothPlastic", "slime_base"),
		-- 2 Uncommon: slime_base + leaf
		l("sprout", { 120, 220, 96 }, "SmoothPlastic", "slime_acc_leaf"),
		l("carrot", { 244, 140, 48 }, "SmoothPlastic", "slime_acc_leaf"),
		l("berry", { 214, 48, 84 }, "SmoothPlastic", "slime_acc_leaf"),
		l("minty", { 150, 236, 200 }, "SmoothPlastic", "slime_acc_leaf"),
		l("pumpkin", { 236, 128, 36 }, "SmoothPlastic", "slime_acc_leaf"),
		l("tulip", { 246, 140, 180 }, "SmoothPlastic", "slime_acc_leaf"),
		-- 3 Rare: slime_ears
		l("bunny_puff", { 250, 214, 220 }, "SmoothPlastic", "slime_ears"),
		l("caramel_kitty", { 206, 140, 70 }, "SmoothPlastic", "slime_ears"),
		l("moo_goo", { 245, 245, 240 }, "SmoothPlastic", "slime_ears"),
		l("piglet", { 248, 170, 186 }, "SmoothPlastic", "slime_ears"),
		l("cocoa_pup", { 132, 86, 58 }, "SmoothPlastic", "slime_ears"),
		-- 4 Epic: slime_horns
		l("billy_gum", { 250, 130, 196 }, "SmoothPlastic", "slime_horns"),
		l("rodeo_ram", { 240, 228, 204 }, "SmoothPlastic", "slime_horns"),
		l("licorice_bull", { 40, 34, 40 }, "SmoothPlastic", "slime_horns"),
		l("toffee_buck", { 170, 108, 52 }, "SmoothPlastic", "slime_horns"),
		l("sour_apple", { 160, 230, 60 }, "SmoothPlastic", "slime_horns"),
		-- 5 Legendary: crown
		l("honey_queen", { 246, 176, 40 }, "SmoothPlastic", "slime_acc_crown"),
		l("harvest_king", { 228, 196, 104 }, "SmoothPlastic", "slime_acc_crown"),
		l("blue_ribbon", { 52, 100, 220 }, "SmoothPlastic", "slime_acc_crown"),
		l("marshmallow_duke", { 252, 248, 244 }, "SmoothPlastic", "slime_acc_crown"),
		-- 6 Mythic: crystal cluster
		l("rock_candy", { 200, 168, 240 }, "Glass", "slime_acc_crystal"),
		l("dewdrop_spirit", { 120, 230, 236 }, "Glass", "slime_acc_crystal"),
		l("gumdrop_titan", { 220, 30, 60 }, "SmoothPlastic", "slime_acc_crystal"),
		-- Secret
		l("golden_goose_goo", { 255, 200, 60 }, "Foil", "slime_wobble"),
		l("moonmilk", { 36, 44, 110 }, "SmoothPlastic", "slime_ears"),
		-- v19 families (FountainTiers): the same kit per tier as Classic
		l("apple_pop", { 226, 52, 56 }, "SmoothPlastic", "slime_base"),
		l("pear_drop", { 176, 214, 64 }, "SmoothPlastic", "slime_acc_leaf"),
		l("peach_fuzz", { 255, 176, 128 }, "SmoothPlastic", "slime_ears"),
		l("plum_stag", { 132, 62, 168 }, "SmoothPlastic", "slime_horns"),
		l("cherry_baron", { 150, 22, 52 }, "SmoothPlastic", "slime_acc_crown"),
		l("citrine_quince", { 250, 214, 52 }, "Glass", "slime_acc_crystal"),
		l("vanilla_scoop", { 255, 244, 212 }, "SmoothPlastic", "slime_base"),
		l("mint_chip", { 128, 232, 188 }, "SmoothPlastic", "slime_acc_leaf"),
		l("sherbet_bunny", { 255, 150, 112 }, "SmoothPlastic", "slime_ears"),
		l("icicle_ibex", { 150, 214, 255 }, "SmoothPlastic", "slime_horns"),
		l("snowcone_duke", { 206, 232, 255 }, "SmoothPlastic", "slime_acc_crown"),
		l("glacier_gem", { 70, 214, 232 }, "Glass", "slime_acc_crystal"),
		l("stardust_blob", { 150, 110, 240 }, "SmoothPlastic", "slime_base"),
		l("nebula_sprout", { 224, 80, 200 }, "SmoothPlastic", "slime_acc_leaf"),
		l("comet_kitty", { 80, 84, 200 }, "SmoothPlastic", "slime_ears"),
		l("meteor_ram", { 255, 120, 56 }, "SmoothPlastic", "slime_horns"),
		l("aurora_queen", { 60, 226, 190 }, "SmoothPlastic", "slime_acc_crown"),
		l("supernova_titan", { 255, 236, 170 }, "Foil", "slime_acc_crystal"),
	}
do
	LOOKS[look.id] = look
end

-- Procedural profiles, same numbers as VisualsClient (bob, tilt, escape hop).
local PROCEDURAL: { [AnimState]: Anim } = {
	idle = table.freeze({
		state = "idle" :: AnimState,
		source = "Procedural" :: "Procedural",
		animationId = nil,
		slimeState = "Pad",
		frequency = 3,
		amplitude = 0.08,
	}),
	wobble = table.freeze({
		state = "wobble" :: AnimState,
		source = "Procedural" :: "Procedural",
		animationId = nil,
		slimeState = "Pad",
		frequency = 2.2,
		amplitude = 0.04,
	}),
	move = table.freeze({
		state = "move" :: AnimState,
		source = "Procedural" :: "Procedural",
		animationId = nil,
		slimeState = "Escaping",
		frequency = 7,
		amplitude = 1.6,
	}),
}

local SlimeLooks = {
	KITS = KITS,
	MATERIALS = MATERIALS,
	ANIM_STATES = table.freeze(ANIM_STATES),
}

function SlimeLooks.get(id: string?): Look?
	return if id then LOOKS[id] else nil
end

-- The animation a type plays in `state`. Every roster type resolves to the
-- procedural fallback today; unknown ids and states return nil.
function SlimeLooks.anim(id: string?, state: string): Anim?
	if not (id and LOOKS[id]) then
		return nil
	end
	return PROCEDURAL[state :: AnimState]
end

function SlimeLooks.isMaterial(name: string): boolean
	return table.find(MATERIALS, name) ~= nil
end

return table.freeze(SlimeLooks)
