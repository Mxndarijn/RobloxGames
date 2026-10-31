--!strict
--[[
	SlimeLooks (owner: Phoenix; v28 slime audit, docs/slime-audit-v28.md)

	Per-type look and animation profile for every SlimeRoster id. Pure data, no
	Roblox APIs.

	  SlimeLooks.get(id) -> Look?            colour, Enum.Material name, kit mesh
	  SlimeLooks.anim(id, state) -> Anim?    state = "idle" | "wobble" | "move"

	Colour: Genome.generate gives wild spawns their type's colour (UI, the
	procedural fallback). Material: server SlimeMesh sets it on Body / Mesh of
	a slime. Kit: the species'
	own fully coloured mesh (MeshAssets "slime_<id>", worn with Color white);
	SlimeMesh falls back to the shared slime package, then the procedural ball.

	Animations: slimes are not rigs and no AnimationIds exist. Every state is
	the procedural fallback played by the visuals client (VisualsClient step):
	idle = bob, wobble = tilt (wriggle while Carried), move = the walking sway
	(ui/SlimeLife SWAY; slimes glide, they don't hop: contract/slime-walk.md).
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
	"slime_sir_goo",
	"slime_phoenix",
	"slime_sunny",
	"slime_elder_oak",
	"slime_gaia",
	"slime_captain_goo",
	"slime_yeti",
	"slime_abyss",
	"slime_lunara",
	"slime_solaris",
	"slime_nebulon",
	"slime_aurora",
	"slime_goo_oracle",
	"slime_kirin",
	"slime_jackpot",
	"slime_star_emperor",
	"slime_goo_god",
	"slime_soda",
	"slime_rocky_road",
	"slime_bloom",
	"slime_honey_toad",
	"slime_truffle",
	"slime_sushi",
	"slime_snow_bunny",
	"slime_moo_shroom",
	"slime_catfish",
	"slime_steam",
	"slime_kraken",
	"slime_thunderbee",
	"slime_cyber_ninja",
	"slime_dragon_king",
	"slime_nightwing",
	"slime_goozilla",
	"slime_queen_jelly",
	"slime_klawdius",
	"slime_pumpking",
	"slime_mecha_goo",
	"slime_goomancer",
	"slime_glitch",
	"slime_doodle",
	"slime_origami",
	"slime_disco",
	"slime_isle",
	"slime_chrono",
	"slime_kitsune",
	"slime_jester",
	"slime_cowboy",
	"slime_venus",
	"slime_bonsai",
	"slime_diver",
	"slime_narwhal",
	"slime_astronaut",
	"slime_griffin",
	"slime_cerberus",
	"slime_willow_wisp",
	"slime_mammoth",
	"slime_siren",
	"slime_djinn",
	"slime_sphinx",
	"slime_monarch",
	"slime_reef",
	"slime_supernova",
	"slime_valkyrie",
	"slime_hydra",
	"slime_constellation",
	"slime_ryujin",
})

-- Materials a slime body may use; all are Enum.Material names.
local MATERIALS = table.freeze({ "SmoothPlastic", "Ice", "Foil", "Neon", "Plastic" })

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
		l("sir_goo", { 120, 210, 90 }, "SmoothPlastic", "slime_sir_goo"),
		l("phoenix", { 255, 120, 40 }, "SmoothPlastic", "slime_phoenix"),
		l("sunny", { 255, 215, 60 }, "SmoothPlastic", "slime_sunny"),
		l("elder_oak", { 130, 90, 55 }, "SmoothPlastic", "slime_elder_oak"),
		l("gaia", { 90, 200, 100 }, "SmoothPlastic", "slime_gaia"),
		l("captain_goo", { 60, 200, 170 }, "SmoothPlastic", "slime_captain_goo"),
		l("yeti", { 230, 240, 255 }, "SmoothPlastic", "slime_yeti"),
		l("abyss", { 25, 35, 80 }, "SmoothPlastic", "slime_abyss"),
		l("lunara", { 220, 210, 255 }, "SmoothPlastic", "slime_lunara"),
		l("solaris", { 255, 190, 60 }, "SmoothPlastic", "slime_solaris"),
		l("nebulon", { 80, 60, 180 }, "SmoothPlastic", "slime_nebulon"),
		l("aurora", { 200, 170, 255 }, "SmoothPlastic", "slime_aurora"),
		l("goo_oracle", { 110, 60, 170 }, "SmoothPlastic", "slime_goo_oracle"),
		l("kirin", { 245, 245, 235 }, "SmoothPlastic", "slime_kirin"),
		l("jackpot", { 220, 40, 50 }, "SmoothPlastic", "slime_jackpot"),
		l("star_emperor", { 30, 40, 110 }, "SmoothPlastic", "slime_star_emperor"),
		l("goo_god", { 255, 240, 200 }, "SmoothPlastic", "slime_goo_god"),
		l("soda", { 150, 80, 40 }, "SmoothPlastic", "slime_soda"),
		l("rocky_road", { 110, 70, 50 }, "SmoothPlastic", "slime_rocky_road"),
		l("bloom", { 110, 210, 90 }, "SmoothPlastic", "slime_bloom"),
		l("honey_toad", { 255, 200, 70 }, "SmoothPlastic", "slime_honey_toad"),
		l("truffle", { 110, 70, 45 }, "SmoothPlastic", "slime_truffle"),
		l("sushi", { 250, 245, 240 }, "SmoothPlastic", "slime_sushi"),
		l("snow_bunny", { 200, 230, 255 }, "SmoothPlastic", "slime_snow_bunny"),
		l("moo_shroom", { 220, 50, 50 }, "SmoothPlastic", "slime_moo_shroom"),
		l("catfish", { 245, 150, 60 }, "SmoothPlastic", "slime_catfish"),
		l("steam", { 240, 120, 140 }, "SmoothPlastic", "slime_steam"),
		l("kraken", { 30, 110, 120 }, "SmoothPlastic", "slime_kraken"),
		l("thunderbee", { 255, 220, 50 }, "SmoothPlastic", "slime_thunderbee"),
		l("cyber_ninja", { 40, 45, 60 }, "SmoothPlastic", "slime_cyber_ninja"),
		l("dragon_king", { 210, 40, 50 }, "SmoothPlastic", "slime_dragon_king"),
		l("nightwing", { 230, 225, 240 }, "SmoothPlastic", "slime_nightwing"),
		l("goozilla", { 50, 140, 70 }, "SmoothPlastic", "slime_goozilla"),
		l("queen_jelly", { 230, 110, 220 }, "SmoothPlastic", "slime_queen_jelly"),
		l("klawdius", { 235, 85, 70 }, "SmoothPlastic", "slime_klawdius"),
		l("pumpking", { 245, 130, 30 }, "SmoothPlastic", "slime_pumpking"),
		l("mecha_goo", { 200, 205, 215 }, "SmoothPlastic", "slime_mecha_goo"),
		l("goomancer", { 120, 130, 235 }, "SmoothPlastic", "slime_goomancer"),
		l("glitch", { 190, 240, 90 }, "SmoothPlastic", "slime_glitch"),
		l("doodle", { 250, 250, 250 }, "SmoothPlastic", "slime_doodle"),
		l("origami", { 255, 170, 200 }, "SmoothPlastic", "slime_origami"),
		l("disco", { 210, 215, 225 }, "SmoothPlastic", "slime_disco"),
		l("isle", { 120, 200, 90 }, "SmoothPlastic", "slime_isle"),
		l("chrono", { 60, 90, 200 }, "SmoothPlastic", "slime_chrono"),
		l("kitsune", { 250, 250, 255 }, "SmoothPlastic", "slime_kitsune"),
		l("jester", { 235, 70, 150 }, "SmoothPlastic", "slime_jester"),
		l("cowboy", { 70, 130, 220 }, "SmoothPlastic", "slime_cowboy"),
		l("venus", { 120, 210, 60 }, "SmoothPlastic", "slime_venus"),
		l("bonsai", { 110, 220, 190 }, "SmoothPlastic", "slime_bonsai"),
		l("diver", { 255, 200, 80 }, "SmoothPlastic", "slime_diver"),
		l("narwhal", { 150, 210, 245 }, "SmoothPlastic", "slime_narwhal"),
		l("astronaut", { 240, 240, 250 }, "SmoothPlastic", "slime_astronaut"),
		l("griffin", { 240, 190, 80 }, "SmoothPlastic", "slime_griffin"),
		l("cerberus", { 170, 150, 240 }, "SmoothPlastic", "slime_cerberus"),
		l("willow_wisp", { 110, 230, 200 }, "SmoothPlastic", "slime_willow_wisp"),
		l("mammoth", { 210, 150, 100 }, "SmoothPlastic", "slime_mammoth"),
		l("siren", { 80, 215, 210 }, "SmoothPlastic", "slime_siren"),
		l("djinn", { 80, 150, 240 }, "SmoothPlastic", "slime_djinn"),
		l("sphinx", { 240, 205, 130 }, "SmoothPlastic", "slime_sphinx"),
		l("monarch", { 250, 140, 40 }, "SmoothPlastic", "slime_monarch"),
		l("reef", { 70, 210, 210 }, "SmoothPlastic", "slime_reef"),
		l("supernova", { 255, 230, 150 }, "SmoothPlastic", "slime_supernova"),
		l("valkyrie", { 110, 170, 240 }, "SmoothPlastic", "slime_valkyrie"),
		l("hydra", { 90, 190, 120 }, "SmoothPlastic", "slime_hydra"),
		l("constellation", { 120, 110, 230 }, "SmoothPlastic", "slime_constellation"),
		l("ryujin", { 100, 210, 160 }, "SmoothPlastic", "slime_ryujin"),
	}
do
	LOOKS[look.id] = look
end

-- Procedural profiles, same numbers as VisualsClient (bob, tilt) and SlimeLife (walking sway).
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
		slimeState = "Wild",
		frequency = 4.4,
		amplitude = 0.05,
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
