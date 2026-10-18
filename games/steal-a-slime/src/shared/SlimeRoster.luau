--!strict
--[[
	SlimeRoster (wired v28: Genome.generate picks species; Config.MUTATIONS holds the new mutations)

	Named Slime Ranch slime types per rarity tier, plus a Secret tier and the
	proposed Rainbow / Crystal / Eclipse mutations. Pure data, no Roblox APIs.

	Save safety: ids are new, lower-case and permanent. Nothing here renames a
	Config.RARITIES tier or a Config.MUTATIONS name (Glow/Lava/Galaxy/Gold);
	Lava keeps its save id and only displays as "Syrup" (docs/archive/RANCH_RENAME.md).
	Tiers 1..7 match Config.RARITIES (SECRET_TIER = 7, the Secret
	rarity).
]]

export type Entry = {
	id: string, -- permanent save id, never rename
	name: string, -- display name
	tier: number, -- Config.RARITIES tier, or SECRET_TIER
	look: string, -- colour / kit mesh / accessory note for modelling
	family: string?, -- FountainTiers family id (v19); nil = Classic, the original roster
}

export type MutationDraft = {
	name: string, -- permanent save id
	display: string,
	multiplier: number,
	weight: number, -- relative to Glow 50 / Lava 30 / Galaxy 15 / Gold 5
}

local SECRET_TIER = 7

local function e(id: string, name: string, tier: number, look: string, family: string?): Entry
	return table.freeze({ id = id, name = name, tier = tier, look = look, family = family })
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
	-- Garden (orchard id): Slime Wrangler
	e("sprout", "Sprout", 1, "pear slime with a two-leaf sprout", "orchard"),
	e("cheddar", "Cheddar", 1, "cheese cube", "orchard"),
	e("prickles", "Prickles", 2, "cactus with a flower", "orchard"),
	e("flan", "Flan", 2, "caramel pudding with a cherry", "orchard"),
	-- Frost & Sea (frost id): Goo Tycoon
	e("chomp", "Chomp", 3, "shark with a scar", "frost"),
	e("pengoo", "Pengoo", 3, "penguin in a top hat", "frost"),
	e("frostbite", "Frostbite", 4, "ice slime with icicles and shades", "frost"),
	e("zap", "Zap", 4, "storm cloud and lightning", "frost"),
	e("ninja", "Ninja", 5, "masked ninja with katana", "frost"),
	-- Starlight: Slime Sovereign
	e("imp", "Imp", 4, "little devil with bat wings", "starlight"),
	e("drako", "Drako", 4, "baby dragon", "starlight"),
	e("robo", "Robo", 5, "chrome robot with visor", "starlight"),
	e("seraph", "Seraph", 6, "angel with halo and wings", "starlight"),
	e("amethyst", "Amethyst", 6, "crystal golem", "starlight"),
	e("prism", "Prism", 6, "rainbow unicorn on a cloud", "starlight"),
	e("eclipse", "Eclipse", SECRET_TIER, "void slime with a burning ring", "starlight"),
	e("boo", "Boo", SECRET_TIER, "floating ghost", "starlight"),
}

-- Proposed new mutations, ordered by multiplier with the existing ones:
-- Glow 1.5 / Lava 2 / Galaxy 3 / Rainbow 4 / Gold 5 / Crystal 7 / Eclipse 10.
local NEW_MUTATIONS: { MutationDraft } = {
	table.freeze({ name = "Rainbow", display = "Rainbow", multiplier = 4, weight = 8 }),
	table.freeze({ name = "Crystal", display = "Crystal", multiplier = 7, weight = 2 }),
	table.freeze({ name = "Eclipse", display = "Eclipse", multiplier = 10, weight = 0.5 }),
}

-- Display names for existing mutation save ids (docs/archive/RANCH_RENAME.md).
local MUTATION_DISPLAY = table.freeze({
	Glow = "Glow",
	Lava = "Syrup",
	Wet = "Wet",
	Frozen = "Frozen",
	Galaxy = "Galaxy",
	Gold = "Gold",
	Rainbow = "Rainbow",
	Crystal = "Crystal",
	Eclipse = "Eclipse",
})

local byId: { [string]: Entry } = {}
for _, entry in ROSTER do
	byId[entry.id] = entry
end

local SlimeRoster = {
	SECRET_TIER = SECRET_TIER,
	ROSTER = table.freeze(ROSTER),
	NEW_MUTATIONS = table.freeze(NEW_MUTATIONS),
	MUTATION_DISPLAY = MUTATION_DISPLAY,
}

function SlimeRoster.get(id: string): Entry?
	return byId[id]
end

-- Types of `tier` in one family: `family` nil = the Classic (Meadow) species.
function SlimeRoster.forTier(tier: number, family: string?): { Entry }
	local out = {}
	for _, entry in ROSTER do
		if entry.tier == tier and entry.family == family then
			table.insert(out, entry)
		end
	end
	return out
end

return table.freeze(SlimeRoster)
