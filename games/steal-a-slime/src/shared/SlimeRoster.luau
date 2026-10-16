--!strict
--[[
	SlimeRoster (wired v28: Genome.generate picks species; Config.MUTATIONS holds the new mutations)

	Named Slime Ranch slime types per rarity tier, plus a Secret tier and the
	proposed Rainbow / Crystal / Eclipse mutations. Pure data, no Roblox APIs.

	Save safety: ids are new, lower-case and permanent. Nothing here renames a
	Config.RARITIES tier or a Config.MUTATIONS name (Glow/Lava/Galaxy/Gold);
	Lava keeps its save id and only displays as "Syrup" (RANCH_RENAME.md).
	Tiers 1..7 match Config.RARITIES (SECRET_TIER = 7, the Secret
	rarity).
]]

export type Entry = {
	id: string, -- permanent save id, never rename
	name: string, -- display name
	tier: number, -- Config.RARITIES tier, or SECRET_TIER
	look: string, -- colour / kit mesh / accessory note for modelling
}

export type MutationDraft = {
	name: string, -- permanent save id
	display: string,
	multiplier: number,
	weight: number, -- relative to Glow 50 / Lava 30 / Galaxy 15 / Gold 5
}

local SECRET_TIER = 7

local function e(id: string, name: string, tier: number, look: string): Entry
	return table.freeze({ id = id, name = name, tier = tier, look = look })
end

local ROSTER: { Entry } = {
	-- 1 Common (6): slime_base, soft field colours
	e("pudding", "Pudding Slime", 1, "butterscotch yellow, slime_base"),
	e("clover", "Clover Slime", 1, "meadow green, slime_base, Spots pattern"),
	e("oatmeal", "Oatmeal Slime", 1, "warm oat beige, slime_base, Belly pattern"),
	e("radish", "Radish Slime", 1, "radish pink, slime_base"),
	e("puddle", "Puddle Slime", 1, "pond blue, slime_base"),
	e("haystack", "Haystack Slime", 1, "straw gold, slime_base, Stripes pattern"),
	-- 2 Uncommon (6): slime_base + slime_acc_leaf
	e("sprout", "Sprout Slime", 2, "fresh green, leaf"),
	e("carrot", "Carrot Slime", 2, "carrot orange, leaf as carrot top"),
	e("berry", "Berry Slime", 2, "raspberry red, leaf, Spots seeds"),
	e("minty", "Minty Slime", 2, "mint, leaf"),
	e("pumpkin", "Pumpkin Slime", 2, "pumpkin orange, leaf, Stripes ribs"),
	e("tulip", "Tulip Slime", 2, "tulip pink, leaf"),
	-- 3 Rare (5): slime_ears
	e("bunny_puff", "Bunny Puff", 3, "cream-pink, slime_ears"),
	e("caramel_kitty", "Caramel Kitty", 3, "caramel, slime_ears"),
	e("moo_goo", "Moo Goo", 3, "white + black Spots, slime_ears"),
	e("piglet", "Piglet Slime", 3, "piggy pink, slime_ears"),
	e("cocoa_pup", "Cocoa Pup", 3, "cocoa brown, slime_ears"),
	-- 4 Epic (5): slime_horns
	e("billy_gum", "Billy Gum", 4, "bubblegum pink, slime_horns (goat)"),
	e("rodeo_ram", "Rodeo Ram", 4, "wool cream body, barn-red horns, slime_horns"),
	e("licorice_bull", "Licorice Bull", 4, "licorice black, slime_horns"),
	e("toffee_buck", "Toffee Buck", 4, "toffee brown, slime_horns"),
	e("sour_apple", "Sour Apple Imp", 4, "sour-apple green, slime_horns, Fang mouth"),
	-- 5 Legendary (4): slime_base + slime_acc_crown
	e("honey_queen", "Honey Queen", 5, "honey amber, crown"),
	e("harvest_king", "Harvest King", 5, "wheat gold, crown"),
	e("blue_ribbon", "Blue Ribbon", 5, "prize blue, crown"),
	e("marshmallow_duke", "Marshmallow Duke", 5, "marshmallow white, crown"),
	-- 6 Mythic (3): slime_base + slime_acc_crystal
	e("rock_candy", "Rock Candy", 6, "sugar lilac, crystal cluster"),
	e("dewdrop_spirit", "Dewdrop Spirit", 6, "dew aqua, crystal cluster, Glow-like sheen"),
	e("gumdrop_titan", "Gumdrop Titan", 6, "cherry red, crystal cluster, MAX size look"),
	-- Secret (2): roster-only tier 7
	e("golden_goose_goo", "Golden Goose Goo", SECRET_TIER, "gold body, crown + crystal, slime_wobble drips"),
	e("moonmilk", "Moonmilk", SECRET_TIER, "midnight blue + pale white, slime_ears + crystal"),
}

-- Proposed new mutations, ordered by multiplier with the existing ones:
-- Glow 1.5 / Lava 2 / Galaxy 3 / Rainbow 4 / Gold 5 / Crystal 7 / Eclipse 10.
local NEW_MUTATIONS: { MutationDraft } = {
	table.freeze({ name = "Rainbow", display = "Rainbow", multiplier = 4, weight = 8 }),
	table.freeze({ name = "Crystal", display = "Crystal", multiplier = 7, weight = 2 }),
	table.freeze({ name = "Eclipse", display = "Eclipse", multiplier = 10, weight = 0.5 }),
}

-- Display names for existing mutation save ids (RANCH_RENAME.md).
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

function SlimeRoster.forTier(tier: number): { Entry }
	local out = {}
	for _, entry in ROSTER do
		if entry.tier == tier then
			table.insert(out, entry)
		end
	end
	return out
end

return table.freeze(SlimeRoster)
