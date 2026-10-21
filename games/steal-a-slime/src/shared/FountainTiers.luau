--!strict
--[[
	FountainTiers (FEATURES.FountainTiers, CONTRACT.md §19)

	The central fountain's look upgrades with rank. Rank thresholds are the Config.REBIRTH_TIERS entries that carry a
	`family`: Slime Wrangler (3 rebirths) grows the Garden Fountain, Goo Tycoon (6) Frost & Sea, Slime Sovereign (10)
	Starlight.
	  * Fountain tier (1..4): the best rank seen on this server since it started (World.fountainTier, never
	    goes back down while the server lives). It drives the look (goo glow; client FountainTierFx
	    reads the workspace attribute Constants.FOUNTAIN_TIER_ATTRIBUTE).
	  * Drop pool: Classic (Meadow) plus every family (allFamilies), on every server at every rank. A drop rolls
	    its rarity first, then a species uniformly over that tier's species in the pool (Genome.speciesPool,
	    contract/slime-odds.md). No slime needs rebirths to catch, buy, steal or merge into.
	No income multiplier and no price: a family slime sells / earns like a Classic one of the same tier,
	and size (the economy is untouched). Species are SlimeRoster entries with `family` set, so a
	save only stores a species id it already knew how to store (Genome.sanitize).
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Family = {
	id: string, -- permanent: SlimeRoster Entry.family and Config.REBIRTH_TIERS[i].family
	name: string,
	tier: number, -- fountain tier named after it (2..4)
}

export type Look = {
	name: string, -- the fountain's name at this tier
	glow: { number }, -- colour of the goo crown light (Map.Volcano.Crater.CraterGlow)
	glowBrightness: number,
}

local FountainTiers = {}

FountainTiers.MAX_TIER = 4

local FAMILIES: { Family } = {
	table.freeze({ id = "orchard", name = "Garden", tier = 2 }),
	table.freeze({ id = "frost", name = "Frost & Sea", tier = 3 }),
	table.freeze({ id = "starlight", name = "Starlight", tier = 4 }),
}
FountainTiers.FAMILIES = table.freeze(FAMILIES)
-- Display name of the Classic species (family nil).
FountainTiers.CLASSIC_NAME = "Meadow"

local function look(name: string, glow: { number }, brightness: number): Look
	return table.freeze({
		name = name,
		glow = table.freeze(glow),
		glowBrightness = brightness,
	})
end

-- Index = tier. Tier 1 is the fountain as shipped: the glow is left as built.
FountainTiers.LOOKS = table.freeze({
	look("Meadow Fountain", { 150, 255, 200 }, 1),
	look("Garden Fountain", { 255, 170, 90 }, 2),
	look("Frost & Sea Fountain", { 150, 220, 255 }, 3),
	look("Starlight Fountain", { 255, 225, 120 }, 4),
})

local byId: { [string]: Family } = {}
for _, family in FAMILIES do
	byId[family.id] = family
end

function FountainTiers.family(id: string?): Family?
	return if id then byId[id] else nil
end

-- Tier (1..MAX_TIER) a player of `rebirths` rebirths would build: one step per Config.REBIRTH_TIERS rank
-- that carries a family and has been reached.
function FountainTiers.tierFor(rebirths: number): number
	local tier = 1
	for _, rank in Config.REBIRTH_TIERS do
		if rank.family and rebirths >= rank.rebirths then
			tier += 1
		end
	end
	return math.min(tier, FountainTiers.MAX_TIER)
end

function FountainTiers.look(tier: number): Look
	return FountainTiers.LOOKS[math.clamp(math.floor(tier), 1, FountainTiers.MAX_TIER)]
end

-- Every family id, in FAMILIES order: the fountain drops them all on every server.
function FountainTiers.allFamilies(): { string }
	local out = {}
	for _, family in FAMILIES do
		table.insert(out, family.id)
	end
	return out
end

-- "The fountain grew into the Garden Fountain!" for a toast when the fountain reaches `tier` (nil at tier 1).
function FountainTiers.upgradeText(tier: number): string?
	if tier <= 1 then
		return nil
	end
	return `The fountain grew into the {FountainTiers.look(tier).name}!`
end

-- The best rank on a server: the highest rebirth count among `rebirthsList`.
function FountainTiers.best(rebirthsList: { number }): number
	local best = 0
	for _, r in rebirthsList do
		best = math.max(best, r)
	end
	return best
end

return table.freeze(FountainTiers)
