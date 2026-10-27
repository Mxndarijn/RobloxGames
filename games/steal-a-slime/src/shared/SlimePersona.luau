--!strict
--[[
	SlimePersona (pure, contract/slime-life.md)

	How each species moves and behaves: its gait (Hop / Ooze / Waddle / Float /
	Scoot), its temperament (which lane beats it picks, how it reacts to a
	player) and, for hoppers, its hop style. Read by the server (ParadeChoreo
	picks beats by temperament) and the client (ui/SlimeGait, ui/SlimeReact).

	  SlimePersona.of(speciesId) -> Persona   DEFAULT for an unknown or nil id
]]

export type Gait = "Hop" | "Ooze" | "Waddle" | "Float" | "Scoot"
export type Temper = "Bouncy" | "Lazy" | "Curious" | "Shy" | "Showoff" | "Feisty"

-- Hop gait only. height: studs at size 1; air: seconds in the air; wait: studs the anchor gets ahead before the
-- next jump (longer leaps); settle: seconds of landing wobble before the next squat.
export type Hop = { height: number, air: number, wait: number, settle: number }

export type Persona = { gait: Gait, temper: Temper, hop: Hop }

local SlimePersona = {}

SlimePersona.GAITS = table.freeze({ "Hop", "Ooze", "Waddle", "Float", "Scoot" } :: { Gait })
SlimePersona.TEMPERS = table.freeze({ "Bouncy", "Lazy", "Curious", "Shy", "Showoff", "Feisty" } :: { Temper })

local HOP: Hop = table.freeze({ height = 1.5, air = 0.44, wait = 0.8, settle = 0.22 })
-- Hop styles that differ from HOP.
local HOPS: { [string]: Hop } = {
	gummy = table.freeze({ height = 1.6, air = 0.42, wait = 0.7, settle = 0.2 }), -- springy jelly, short and quick
	froggo = table.freeze({ height = 1.2, air = 0.5, wait = 1.7, settle = 0.32 }), -- long flat leaps, a pause between
	lop = table.freeze({ height = 2.1, air = 0.6, wait = 1.2, settle = 0.24 }), -- high floaty bunny hops
	snow_bunny = table.freeze({ height = 2.1, air = 0.6, wait = 1.2, settle = 0.24 }),
	honey_toad = table.freeze({ height = 1.1, air = 0.5, wait = 1.8, settle = 0.4 }),
	ninja = table.freeze({ height = 0.8, air = 0.3, wait = 0.6, settle = 0.12 }), -- low quick dashes
	cyber_ninja = table.freeze({ height = 0.8, air = 0.3, wait = 0.6, settle = 0.12 }),
	whiskers = table.freeze({ height = 1.3, air = 0.4, wait = 1.0, settle = 0.3 }), -- pounces
	pumpking = table.freeze({ height = 1.3, air = 0.55, wait = 1.5, settle = 0.45 }), -- heavy stomps, a long wobble
}

local function p(gait: Gait, temper: Temper, id: string): Persona
	return table.freeze({ gait = gait, temper = temper, hop = HOPS[id] or HOP })
end

-- Every SlimeRoster id (tests/SlimePersona.spec checks the two lists match).
local BY_SPECIES: { [string]: Persona } = {
	-- spawning species
	gummy = p("Hop", "Bouncy", "gummy"),
	mochi = p("Ooze", "Lazy", "mochi"),
	bubbles = p("Hop", "Curious", "bubbles"),
	pebble = p("Scoot", "Feisty", "pebble"),
	bumble = p("Float", "Showoff", "bumble"),
	mushie = p("Scoot", "Shy", "mushie"),
	froggo = p("Hop", "Bouncy", "froggo"),
	whiskers = p("Hop", "Curious", "whiskers"),
	lop = p("Hop", "Shy", "lop"),
	moo = p("Waddle", "Lazy", "moo"),
	blaze = p("Scoot", "Feisty", "blaze"),
	octo = p("Scoot", "Curious", "octo"),
	king = p("Waddle", "Showoff", "king"),
	cosmo = p("Float", "Curious", "cosmo"),
	midas = p("Waddle", "Showoff", "midas"),
	sprout = p("Hop", "Bouncy", "sprout"),
	cheddar = p("Scoot", "Showoff", "cheddar"),
	prickles = p("Scoot", "Feisty", "prickles"),
	flan = p("Ooze", "Lazy", "flan"),
	chomp = p("Scoot", "Feisty", "chomp"),
	pengoo = p("Waddle", "Curious", "pengoo"),
	frostbite = p("Ooze", "Showoff", "frostbite"),
	zap = p("Float", "Bouncy", "zap"),
	ninja = p("Hop", "Shy", "ninja"),
	imp = p("Float", "Feisty", "imp"),
	drako = p("Hop", "Feisty", "drako"),
	robo = p("Waddle", "Curious", "robo"),
	seraph = p("Float", "Lazy", "seraph"),
	amethyst = p("Waddle", "Lazy", "amethyst"),
	prism = p("Float", "Bouncy", "prism"),
	eclipse = p("Float", "Showoff", "eclipse"),
	boo = p("Float", "Curious", "boo"),
	sir_goo = p("Waddle", "Showoff", "sir_goo"),
	phoenix = p("Float", "Feisty", "phoenix"),
	sunny = p("Hop", "Bouncy", "sunny"),
	elder_oak = p("Ooze", "Lazy", "elder_oak"),
	gaia = p("Float", "Lazy", "gaia"),
	captain_goo = p("Waddle", "Feisty", "captain_goo"),
	yeti = p("Waddle", "Bouncy", "yeti"),
	abyss = p("Float", "Feisty", "abyss"),
	lunara = p("Float", "Lazy", "lunara"),
	solaris = p("Float", "Showoff", "solaris"),
	nebulon = p("Float", "Curious", "nebulon"),
	aurora = p("Float", "Bouncy", "aurora"),
	goo_oracle = p("Float", "Lazy", "goo_oracle"),
	kirin = p("Hop", "Showoff", "kirin"),
	jackpot = p("Hop", "Showoff", "jackpot"),
	star_emperor = p("Waddle", "Showoff", "star_emperor"),
	goo_god = p("Float", "Showoff", "goo_god"),
	-- merge hybrids
	soda = p("Hop", "Bouncy", "soda"),
	rocky_road = p("Scoot", "Feisty", "rocky_road"),
	bloom = p("Ooze", "Shy", "bloom"),
	honey_toad = p("Hop", "Lazy", "honey_toad"),
	truffle = p("Scoot", "Shy", "truffle"),
	sushi = p("Ooze", "Curious", "sushi"),
	snow_bunny = p("Hop", "Shy", "snow_bunny"),
	moo_shroom = p("Waddle", "Lazy", "moo_shroom"),
	catfish = p("Scoot", "Curious", "catfish"),
	steam = p("Float", "Feisty", "steam"),
	kraken = p("Scoot", "Feisty", "kraken"),
	thunderbee = p("Float", "Showoff", "thunderbee"),
	cyber_ninja = p("Hop", "Feisty", "cyber_ninja"),
	dragon_king = p("Waddle", "Showoff", "dragon_king"),
	nightwing = p("Float", "Feisty", "nightwing"),
	-- boss slimes
	goozilla = p("Waddle", "Feisty", "goozilla"),
	queen_jelly = p("Float", "Showoff", "queen_jelly"),
	klawdius = p("Scoot", "Feisty", "klawdius"),
	pumpking = p("Hop", "Bouncy", "pumpking"),
	mecha_goo = p("Waddle", "Feisty", "mecha_goo"),
	goomancer = p("Float", "Curious", "goomancer"),
	-- event Secrets
	glitch = p("Scoot", "Bouncy", "glitch"),
	doodle = p("Hop", "Curious", "doodle"),
	origami = p("Hop", "Shy", "origami"),
	disco = p("Hop", "Showoff", "disco"),
	isle = p("Ooze", "Lazy", "isle"),
	chrono = p("Float", "Curious", "chrono"),
	kitsune = p("Hop", "Showoff", "kitsune"),
}
SlimePersona.BY_SPECIES = table.freeze(BY_SPECIES)
SlimePersona.DEFAULT = p("Ooze", "Curious", "")

function SlimePersona.of(speciesId: string?): Persona
	return if speciesId then BY_SPECIES[speciesId] or SlimePersona.DEFAULT else SlimePersona.DEFAULT
end

return table.freeze(SlimePersona)
