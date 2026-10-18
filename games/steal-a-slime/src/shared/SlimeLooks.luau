--!strict
--[[
	SlimeLooks (owner: Phoenix; v28 slime audit, docs/slime-audit-v28.md)

	Per-type look and animation profile for every SlimeRoster id. Pure data, no
	Roblox APIs.

	  SlimeLooks.get(id) -> Look?            colour, Enum.Material name, kit mesh
	  SlimeLooks.anim(id, state) -> Anim?    state = "idle" | "wobble" | "move"

	Colour: Genome.generate gives wild spawns their type's colour (UI, the
	procedural fallback). Material: server SlimeMesh sets it on Body / Mesh of
	an unmutated slime (a mutation material always wins). Kit: the species'
	own fully coloured mesh (MeshAssets "slime_<id>", worn with Color white);
	SlimeMesh falls back to the shared slime package, then the procedural ball.

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
	"slime_gummy",
	"slime_mochi",
	"slime_bubbles",
	"slime_pebble",
	"slime_bumble",
	"slime_mushie",
	"slime_froggo",
	"slime_whiskers",
	"slime_lop",
	"slime_moo",
	"slime_blaze",
	"slime_octo",
	"slime_king",
	"slime_cosmo",
	"slime_midas",
	"slime_sprout",
	"slime_cheddar",
	"slime_prickles",
	"slime_flan",
	"slime_chomp",
	"slime_pengoo",
	"slime_frostbite",
	"slime_zap",
	"slime_ninja",
	"slime_imp",
	"slime_drako",
	"slime_robo",
	"slime_seraph",
	"slime_amethyst",
	"slime_prism",
	"slime_eclipse",
	"slime_boo",
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
		-- every pool species wears its own fully coloured mesh (MeshAssets "slime_<id>")
		l("gummy", { 126, 232, 79 }, "SmoothPlastic", "slime_gummy"),
		l("mochi", { 255, 226, 234 }, "SmoothPlastic", "slime_mochi"),
		l("bubbles", { 90, 180, 250 }, "SmoothPlastic", "slime_bubbles"),
		l("pebble", { 150, 140, 125 }, "SmoothPlastic", "slime_pebble"),
		l("bumble", { 255, 210, 58 }, "SmoothPlastic", "slime_bumble"),
		l("mushie", { 230, 60, 60 }, "SmoothPlastic", "slime_mushie"),
		l("froggo", { 90, 200, 80 }, "SmoothPlastic", "slime_froggo"),
		l("whiskers", { 245, 150, 60 }, "SmoothPlastic", "slime_whiskers"),
		l("lop", { 250, 200, 215 }, "SmoothPlastic", "slime_lop"),
		l("moo", { 245, 245, 240 }, "SmoothPlastic", "slime_moo"),
		l("blaze", { 255, 110, 40 }, "SmoothPlastic", "slime_blaze"),
		l("octo", { 190, 90, 220 }, "SmoothPlastic", "slime_octo"),
		l("king", { 130, 60, 190 }, "SmoothPlastic", "slime_king"),
		l("cosmo", { 60, 40, 130 }, "SmoothPlastic", "slime_cosmo"),
		l("midas", { 255, 200, 60 }, "SmoothPlastic", "slime_midas"),
		l("sprout", { 200, 230, 80 }, "SmoothPlastic", "slime_sprout"),
		l("cheddar", { 255, 200, 60 }, "SmoothPlastic", "slime_cheddar"),
		l("prickles", { 70, 170, 80 }, "SmoothPlastic", "slime_prickles"),
		l("flan", { 240, 180, 70 }, "SmoothPlastic", "slime_flan"),
		l("chomp", { 61, 143, 240 }, "SmoothPlastic", "slime_chomp"),
		l("pengoo", { 40, 50, 100 }, "SmoothPlastic", "slime_pengoo"),
		l("frostbite", { 150, 210, 255 }, "SmoothPlastic", "slime_frostbite"),
		l("zap", { 70, 60, 150 }, "SmoothPlastic", "slime_zap"),
		l("ninja", { 30, 30, 45 }, "SmoothPlastic", "slime_ninja"),
		l("imp", { 220, 40, 50 }, "SmoothPlastic", "slime_imp"),
		l("drako", { 60, 190, 170 }, "SmoothPlastic", "slime_drako"),
		l("robo", { 200, 205, 215 }, "SmoothPlastic", "slime_robo"),
		l("seraph", { 250, 248, 255 }, "SmoothPlastic", "slime_seraph"),
		l("amethyst", { 120, 70, 200 }, "SmoothPlastic", "slime_amethyst"),
		l("prism", { 255, 150, 220 }, "SmoothPlastic", "slime_prism"),
		l("eclipse", { 40, 20, 60 }, "SmoothPlastic", "slime_eclipse"),
		l("boo", { 170, 240, 220 }, "SmoothPlastic", "slime_boo"),
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
