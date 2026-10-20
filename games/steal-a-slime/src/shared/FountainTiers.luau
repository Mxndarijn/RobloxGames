--!strict
--[[
	FountainTiers (FEATURES.FountainTiers, CONTRACT.md §19)

	The central fountain upgrades with rank. Rank thresholds are the Config.REBIRTH_TIERS entries that carry a
	`family`: Slime Wrangler (3 rebirths) opens Garden, Goo Tycoon (6) Frost & Sea, Slime Sovereign (10) Starlight.
	  * Fountain tier (1..4): the best rank seen on this server since it started (World.fountainTier, never
	    goes back down while the server lives). It drives the look (goo glow; client FountainTierFx
	    reads the workspace attribute Constants.FOUNTAIN_TIER_ATTRIBUTE) and the drop pool.
	  * Drop pool: Classic (Meadow) always, plus every family the tier has opened. A drop rolls its rarity first,
	    then a species uniformly over that tier's species in the pool (Genome.speciesPool, contract/slime-odds.md).
	  * Catching a family slime needs your own rank to have opened it (a stolen one is already owned).
	No income multiplier and no price: a family slime sells / earns like a Classic one of the same tier,
	and size (the economy is untouched). Species are SlimeRoster entries with `family` set, so a
	save only stores a species id it already knew how to store (Genome.sanitize).
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Family = {
	id: string, -- permanent: SlimeRoster Entry.family and Config.REBIRTH_TIERS[i].family
	name: string,
	tier: number, -- fountain tier that opens it (2..4)
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

-- Rebirths a family's rank needs (its Config.REBIRTH_TIERS entry), nil for an unknown family.
function FountainTiers.rebirthsFor(id: string): number?
	for _, rank in Config.REBIRTH_TIERS do
		if rank.family == id then
			return rank.rebirths
		end
	end
	return nil
end

function FountainTiers.look(tier: number): Look
	return FountainTiers.LOOKS[math.clamp(math.floor(tier), 1, FountainTiers.MAX_TIER)]
end

-- Family ids open at fountain `tier`, in FAMILIES order.
function FountainTiers.pool(tier: number): { string }
	local out = {}
	for _, family in FAMILIES do
		if tier >= family.tier then
			table.insert(out, family.id)
		end
	end
	return out
end

-- Failure text when a player of `rebirths` can't catch a slime of family `id` (nil family = Classic), else nil.
function FountainTiers.catchBlock(rebirths: number, id: string?): string?
	local needed = if id then FountainTiers.rebirthsFor(id) else nil
	local family = FountainTiers.family(id)
	if not family or not needed or rebirths >= needed then
		return nil
	end
	local title = ""
	for _, rank in Config.REBIRTH_TIERS do
		if rank.rebirths == needed then
			title = rank.title
		end
	end
	return `Reach {title} ({needed} rebirths) to catch {family.name} slimes`
end

-- "Garden slimes now drop" for a toast when the fountain reaches `tier` (nil at tier 1).
function FountainTiers.upgradeText(tier: number): string?
	if tier <= 1 then
		return nil
	end
	local l = FountainTiers.look(tier)
	for _, family in FAMILIES do
		if family.tier == tier then
			return `The fountain grew into the {l.name}! {family.name} slimes now drop.`
		end
	end
	return `The fountain grew into the {l.name}!`
end

-- The best rank on a server: the highest rebirth count among `rebirthsList`.
function FountainTiers.best(rebirthsList: { number }): number
	local best = 0
	for _, r in rebirthsList do
		best = math.max(best, r)
	end
	return best
end

-- Rank text for Perks.tierText ("opens the Garden slimes").
function FountainTiers.rankText(familyId: string): string
	local family = FountainTiers.family(familyId)
	return if family then `opens the {family.name} slimes` else ""
end

return table.freeze(FountainTiers)
