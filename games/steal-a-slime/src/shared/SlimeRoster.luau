--!strict
--[[
	SlimeRoster (wired v28: Genome.generate picks species)

	Named Slime Ranch slime types per rarity tier, plus a Secret tier. Pure data, no Roblox APIs.

	Save safety: ids are new, lower-case and permanent. Nothing here renames a
	Config.RARITIES tier.
	Tiers 1..7 match Config.RARITIES (SECRET_TIER = 7, the Secret
	rarity).
]]

export type Entry = {
	id: string, -- permanent save id, never rename
	name: string, -- display name
	tier: number, -- Config.RARITIES tier, or SECRET_TIER
	look: string, -- colour / kit mesh / accessory note for modelling
	family: string?, -- FountainTiers family id (v19); nil = Classic, the original roster
	kind: Kind, -- "spawn" rolls from the fountain and random merges; the others only from their own system
	income: number, -- species income bonus within its rarity (INCOME; 1 = the rarity's base income)
	jackpot: boolean?, -- a jackpot: x JACKPOT_INCOME, Config.JACKPOT_SHARE of its rarity's drops, never merged or asked for
	dexBonus: boolean?, -- a SlimeDex bonus entry: shown and counted in bonusFound, never in the Dex total or milestones
}

-- spawn: the fountain and random merges. hybrid: merge recipes only. boss: the boss event only.
-- event: a limited Secret, only while its event runs.
export type Kind = "spawn" | "hybrid" | "boss" | "event"

local SECRET_TIER = 7

-- Income bonus of each species within its rarity (Genome.baseIncome). Later families earn more, and a species
-- that earns more spawns less often within its rarity (Genome.speciesWeight). Ids not listed earn x1.
local INCOME: { [string]: number } = {
	-- Common
	gummy = 1,
	mochi = 0.9,
	bubbles = 1.05,
	pebble = 0.95,
	sprout = 1.1,
	cheddar = 1.15,
	-- Uncommon
	bumble = 1,
	mushie = 0.95,
	froggo = 1.05,
	prickles = 1.1,
	flan = 1.15,
	-- Rare
	whiskers = 1,
	lop = 0.95,
	moo = 1.05,
	chomp = 1.15,
	pengoo = 1.2,
	-- Epic
	blaze = 1,
	octo = 0.95,
	frostbite = 1.15,
	zap = 1.2,
	imp = 1.3,
	drako = 1.35,
	-- Legendary
	king = 1,
	sir_goo = 1.05,
	sunny = 1.1,
	ninja = 1.15,
	captain_goo = 1.2,
	robo = 1.3,
	-- Mythic
	cosmo = 1,
	phoenix = 1.05,
	elder_oak = 1.1,
	yeti = 1.2,
	amethyst = 1.25,
	seraph = 1.3,
	prism = 1.35,
	-- Celestial
	lunara = 1,
	solaris = 1.1,
	nebulon = 1.2,
	-- Divine
	aurora = 1,
	goo_oracle = 1.1,
	kirin = 1.2,
	-- New wild slimes (Legendary and up)
	jester = 1,
	cowboy = 1,
	venus = 1.05,
	bonsai = 1.05,
	diver = 1.1,
	narwhal = 1.1,
	astronaut = 1.1,
	griffin = 1,
	cerberus = 1,
	willow_wisp = 1.05,
	mammoth = 1.05,
	siren = 1.05,
	djinn = 1.15,
	sphinx = 1.15,
	monarch = 1.05,
	reef = 1.1,
	supernova = 1.1,
	valkyrie = 1.1,
	-- Secret
	midas = 1,
	gaia = 1.15,
	abyss = 1.2,
	boo = 1.25,
	eclipse = 1.3,
}
local HYBRID_INCOME = 1.2 -- every merge hybrid (on top of Config.RECIPE_INCOME_MULT)
local EVENT_INCOME = 1.4 -- every limited event Secret
local JACKPOT_INCOME = 5 -- every jackpot
local JACKPOTS: { [string]: boolean } = { jackpot = true, star_emperor = true, goo_god = true }
-- Legendary-and-up species that are SlimeDex bonus entries, so the Dex total, milestones and unlocks stay put.
local DEX_BONUS: { [string]: boolean } = {
	jester = true,
	cowboy = true,
	venus = true,
	bonsai = true,
	diver = true,
	narwhal = true,
	astronaut = true,
	griffin = true,
	cerberus = true,
	willow_wisp = true,
	mammoth = true,
	siren = true,
	djinn = true,
	sphinx = true,
	monarch = true,
	reef = true,
	supernova = true,
	valkyrie = true,
	hydra = true,
	constellation = true,
	ryujin = true,
}

local function e(id: string, name: string, tier: number, look: string, family: string?, kind: Kind?): Entry
	return table.freeze({
		id = id,
		name = name,
		tier = tier,
		look = look,
		family = family,
		kind = (kind or "spawn") :: Kind,
		income = if JACKPOTS[id]
			then JACKPOT_INCOME
			else INCOME[id] or if kind == "hybrid"
				then HYBRID_INCOME
				elseif kind == "event" then EVENT_INCOME
				else 1,
		jackpot = if JACKPOTS[id] then true else nil,
		dexBonus = if DEX_BONUS[id] then true else nil,
	})
end

local function k(kind: Kind, id: string, name: string, tier: number, look: string): Entry
	return e(id, name, tier, look, nil, kind)
end

local ROSTER: { Entry } = {
	-- The slime pool (shared/modeling-kit/models/pool, docs/SLIME-ECONOMY.md §1.3): one mesh per
	-- species, `look` is the pitch. Classic (Meadow) is open from the start.
	e("gummy", "Gummy", 1, "lime gumdrop, toothy grin"),
	e("mochi", "Mochi", 1, "wide pink rice cake, sleepy"),
	e("bubbles", "Bubbles", 1, "sky-blue ball with soap bubbles"),
	e("pebble", "Pebble", 1, "mossy rock, grumpy unibrow"),
	e("bumble", "Bumble", 2, "bee with shades"),
	e("mushie", "Mushie", 2, "shy red mushroom cap"),
	e("froggo", "Froggo", 2, "frog, tongue out"),
	e("whiskers", "Whiskers", 3, "orange tabby cat, wink"),
	e("lop", "Lop", 3, "pink bunny with floppy ears"),
	e("moo", "Moo", 3, "cow with bell collar"),
	e("blaze", "Blaze", 4, "fire slime with a flame top"),
	e("octo", "Octo", 4, "purple octopus"),
	e("king", "King Goo", 5, "crown, cape, mustache"),
	e("cosmo", "Cosmo", 6, "galaxy with a planet ring"),
	e("midas", "Midas", SECRET_TIER, "dripping gold, shades, chain"),
	e("sir_goo", "Sir Goo", 5, "knight with a plumed helmet, shield and sword"),
	e("phoenix", "Phoenix", 6, "fire bird with flame wings, crest and tail"),
	-- Garden (orchard id): Slime Wrangler
	e("sprout", "Sprout", 1, "pear slime with a two-leaf sprout", "orchard"),
	e("cheddar", "Cheddar", 1, "cheese cube", "orchard"),
	e("prickles", "Prickles", 2, "cactus with a flower", "orchard"),
	e("flan", "Flan", 2, "caramel pudding with a cherry", "orchard"),
	e("sunny", "Sunny", 5, "sunflower with a petal mane and shades", "orchard"),
	e("elder_oak", "Elder Oak", 6, "ancient tree with a leafy canopy and an owl", "orchard"),
	e("gaia", "Gaia", SECRET_TIER, "earth spirit with a floating flower crown", "orchard"),
	-- Frost & Sea (frost id): Goo Tycoon
	e("chomp", "Chomp", 3, "shark with a scar", "frost"),
	e("pengoo", "Pengoo", 3, "penguin in a top hat", "frost"),
	e("frostbite", "Frostbite", 4, "ice slime with icicles and shades", "frost"),
	e("zap", "Zap", 4, "storm cloud and lightning", "frost"),
	e("ninja", "Ninja", 5, "masked ninja with katana", "frost"),
	e("captain_goo", "Captain Goo", 5, "pirate with a tricorn, eye patch and parrot", "frost"),
	e("yeti", "Yeti", 6, "shaggy frost yeti with ice horns", "frost"),
	e("abyss", "Abyss", SECRET_TIER, "deep-sea angler with a glowing lure", "frost"),
	-- Starlight: Slime Sovereign
	e("imp", "Imp", 4, "little devil with bat wings", "starlight"),
	e("drako", "Drako", 4, "baby dragon", "starlight"),
	e("robo", "Robo", 5, "chrome robot with visor", "starlight"),
	e("seraph", "Seraph", 6, "angel with halo and wings", "starlight"),
	e("amethyst", "Amethyst", 6, "crystal golem", "starlight"),
	e("prism", "Prism", 6, "rainbow unicorn on a cloud", "starlight"),
	e("eclipse", "Eclipse", SECRET_TIER, "void slime with a burning ring", "starlight"),
	e("boo", "Boo", SECRET_TIER, "floating ghost", "starlight"),
	-- Celestial and Divine (the slime ladder): every player sees them, grabbing waits for CATCH_REBIRTHS.
	e("lunara", "Lunara", 8, "moon spirit with crescent horns and an orbiting moon"),
	e("solaris", "Solaris", 8, "sun core with a rayed corona ring"),
	e("nebulon", "Nebulon", 8, "nebula swirls with drifting stars and a tiny planet"),
	e("aurora", "Aurora", 9, "rainbow-shifting slime with aurora ribbons"),
	e("goo_oracle", "Goo Oracle", 9, "mystic with a third-eye gem and a rune circle"),
	e("kirin", "Kirin", 9, "divine qilin with a golden horn and a cloud mane"),
	-- Jackpots: one per top rarity, flashy and rare (Config.JACKPOT_SHARE of its drops), x5 income.
	e("jackpot", "Jackpot", SECRET_TIER, "slot machine with 777 reels and spilling coins"),
	e("star_emperor", "Star Emperor", 8, "starry cape and a crown of tiny planets"),
	e("goo_god", "Goo God", 9, "huge white-gold slime with a sunburst and orbiting mini-slimes"),
	e("jester", "Jester", 5, "jester hat with bells, juggling three tiny slimes"),
	e("cowboy", "Cowboy", 5, "ranch sheriff with a wide hat, star badge and lasso"),
	e("venus", "Venus", 5, "venus flytrap with snapping leaf jaws", "orchard"),
	e("bonsai", "Bonsai", 5, "tiny bonsai tree in a clay pot", "orchard"),
	e("diver", "Diver", 5, "brass diving helmet with a round window", "frost"),
	e("narwhal", "Narwhal", 5, "pale blue whale with a spiral horn", "frost"),
	e("astronaut", "Astronaut", 5, "white space suit with a round visor", "starlight"),
	e("griffin", "Griffin", 6, "eagle head and wings on a lion-gold body"),
	e("cerberus", "Cerberus", 6, "three-headed puppy with spiked collars"),
	e("willow_wisp", "Willow Wisp", 6, "glowing forest spirit with a lantern", "orchard"),
	e("mammoth", "Mammoth", 6, "woolly mammoth with curled tusks", "frost"),
	e("siren", "Siren", 6, "mermaid with a shell crown and trident", "frost"),
	e("djinn", "Djinn", 6, "blue genie rising from a golden lamp", "starlight"),
	e("sphinx", "Sphinx", 6, "sandstone sphinx with a pharaoh headdress", "starlight"),
	e("monarch", "Monarch", SECRET_TIER, "huge shimmering butterfly wings", "orchard"),
	e("reef", "Reef", SECRET_TIER, "living coral reef with tiny fish", "frost"),
	e("supernova", "Supernova", 8, "bursting white-hot star with a shock ring"),
	e("valkyrie", "Valkyrie", 9, "winged silver helmet and a spear of light"),
	-- Merge-only hybrids (docs/SLIME-ECONOMY.md §2): never spawn, only from their recipe.
	k("hybrid", "soda", "Soda Pop", 2, "cola drop with a bottle cap and straw"),
	k("hybrid", "rocky_road", "Rocky Road", 2, "chocolate scoop in a waffle cone"),
	k("hybrid", "bloom", "Bloom", 3, "jelly in a blossom with a little bee"),
	k("hybrid", "honey_toad", "Honey Toad", 3, "bee-striped frog dripping honey"),
	k("hybrid", "truffle", "Truffle", 3, "chocolate mushroom with a monocle"),
	k("hybrid", "sushi", "Sushi", 4, "nigiri with chopsticks"),
	k("hybrid", "snow_bunny", "Snow Bunny", 4, "icy bunny with earmuffs"),
	k("hybrid", "moo_shroom", "Moo-shroom", 4, "toadstool cow"),
	k("hybrid", "catfish", "Catfish", 4, "cat-shark with barbels"),
	k("hybrid", "steam", "Steampuff", 5, "half fire, half ice, steam cloud"),
	k("hybrid", "kraken", "Kraken", 5, "deep-sea octopus-shark"),
	k("hybrid", "thunderbee", "Thunderbee", 5, "electric bee"),
	k("hybrid", "cyber_ninja", "Cyber Ninja", 6, "chrome ninja with a neon katana"),
	k("hybrid", "dragon_king", "Dragon King", 6, "crowned dragon with a cape"),
	k("hybrid", "nightwing", "Nightwing", SECRET_TIER, "half angel, half void"),
	k("hybrid", "hydra", "Hydra", SECRET_TIER, "three-headed sea serpent"),
	k("hybrid", "constellation", "Constellation", 8, "stars joined by glowing lines"),
	k("hybrid", "ryujin", "Ryujin", 9, "jade cloud dragon holding a pearl"),
	-- Boss slimes (the boss event, docs/SLIME-ECONOMY.md §3).
	k("boss", "goozilla", "Goozilla", 6, "roaring kaiju slime"),
	k("boss", "queen_jelly", "Queen Jelly", 6, "jellyfish queen with a tiara"),
	k("boss", "klawdius", "Klawdius", 6, "hermit crab in a spiral shell with a giant claw"),
	k("boss", "pumpking", "Pumpking", 6, "jack-o'-lantern with a glowing grin and a crown"),
	k("boss", "mecha_goo", "Mecha Goo", SECRET_TIER, "mech with a tiny slime pilot"),
	k("boss", "goomancer", "Goomancer", SECRET_TIER, "wizard with a tall star hat, beard and orb staff"),
	-- Event Secrets: one is featured at a time.
	k("event", "glitch", "Gl1tch", SECRET_TIER, "corrupted video-frame slime"),
	k("event", "doodle", "Doodle", SECRET_TIER, "hand-drawn ink slime"),
	k("event", "origami", "Origami", SECRET_TIER, "folded paper crane"),
	k("event", "disco", "Disco", SECRET_TIER, "mirror ball with headphones"),
	k("event", "isle", "Skyisle", SECRET_TIER, "floating island world"),
	k("event", "chrono", "Chrono", SECRET_TIER, "hourglass with clock eyes"),
	k("event", "kitsune", "Kitsune", SECRET_TIER, "nine-tailed spirit fox"),
}

local byId: { [string]: Entry } = {}
for _, entry in ROSTER do
	byId[entry.id] = entry
end

local SlimeRoster = {
	SECRET_TIER = SECRET_TIER,
	ROSTER = table.freeze(ROSTER),
}

function SlimeRoster.get(id: string): Entry?
	return byId[id]
end

-- Income bonus of species `id` within its rarity; 1 for an unknown or missing id.
function SlimeRoster.incomeBonus(id: string?): number
	local entry = if id then byId[id] else nil
	return if entry then entry.income else 1
end

-- Spawning types of `tier` in one family: `family` nil = the Classic (Meadow) species.
function SlimeRoster.forTier(tier: number, family: string?): { Entry }
	local out = {}
	for _, entry in ROSTER do
		if entry.kind == "spawn" and entry.tier == tier and entry.family == family then
			table.insert(out, entry)
		end
	end
	return out
end

-- Every entry of one kind ("spawn" | "hybrid" | "boss" | "event"), in roster order.
function SlimeRoster.ofKind(kind: Kind): { Entry }
	local out = {}
	for _, entry in ROSTER do
		if entry.kind == kind then
			table.insert(out, entry)
		end
	end
	return out
end

return table.freeze(SlimeRoster)
