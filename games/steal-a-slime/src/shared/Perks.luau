--!strict
--[[
	Perks

	What a player's progression does (CONTRACT.md §8.8), as plain formulas
	over PlayerData fields and Config, so PlayerData / Economy users can apply
	them without a require cycle:
	  * rebirth ranks (Config.REBIRTH_TIERS): title, keep count and income
	    bonus; the best unlocked value wins, they don't stack;
	  * upgrade levels (Config.UPGRADES): income, carry slowdown, offline cap,
	    luck;
	  * SlimeDex milestone bonus (Config.DEX_MILESTONES: data.speciesRewards paid).
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local MergeGate = if script then require(script.Parent.MergeGate) else require("./MergeGate")

-- The fields Perks reads (a PlayerData.Data satisfies it).
export type Progress = {
	rebirths: number,
	upgrades: { [string]: number },
	speciesRewards: number,
	boostMult: number?, -- redeem-code income boost while active (Codes), nil / 1 = none
	friendBonus: number?, -- runtime friend bonus (FriendBonus, never saved), nil / 0 = none
	slimes: { any }?, -- owned slimes (follow-pet passive lookup)
	favoriteId: string?, -- the follow pet; nil = no passive
	weekendMult: number?, -- runtime x2 Weekend multiplier (Weekend, never saved), nil / 1 = none
	ritualBonus: number?, -- runtime "Blessed" bonus from the co-op ritual (Ritual, never saved), nil / 0 = none
	mvpBonus: number?, -- runtime Boss Champion bonus (BossCredit, never saved), nil / 0 = none
	passIncomeMult: number?, -- runtime Income2x Game Pass factor (Purchases.applyPasses, never saved), nil / 1 = none
	passBrewFactor: number?, -- runtime FastBrew Game Pass factor on brew times, nil / 1 = none
	passLuckBonus: number?, -- runtime LuckyCharmPlus Game Pass chance added to the Lucky Charm, nil / 0 = none
}

local Perks = {}

---------------------------------------------------------------------------
-- Rebirth ranks
---------------------------------------------------------------------------

-- Index into Config.REBIRTH_TIERS of the highest rank reached.
function Perks.tierIndex(rebirths: number): number
	local index = 1
	for i, tier in Config.REBIRTH_TIERS do
		if rebirths >= tier.rebirths then
			index = i
		end
	end
	return index
end

function Perks.tier(rebirths: number): Config.RebirthTier
	return Config.REBIRTH_TIERS[Perks.tierIndex(rebirths)]
end

function Perks.title(rebirths: number): string
	return Perks.tier(rebirths).title
end

-- The next rank, or nil at the top.
function Perks.nextTier(rebirths: number): Config.RebirthTier?
	return Config.REBIRTH_TIERS[Perks.tierIndex(rebirths) + 1]
end

local function upgradeDef(id: string): Config.Upgrade?
	for _, def in Config.UPGRADES do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- "unlocks Strong Arms, +25% income" (empty for the first rank).
function Perks.tierText(tier: Config.RebirthTier): string
	local parts = {}
	if tier.unlock then
		local def = upgradeDef(tier.unlock)
		table.insert(parts, `unlocks the {if def then def.name else tier.unlock} upgrade`)
	end
	if tier.income then
		table.insert(parts, `+{math.floor(tier.income * 100 + 0.5)}% income`)
	end
	local merges = MergeGate.opensAt(tier)
	if merges then
		table.insert(parts, `opens {merges} merges`)
	end
	return table.concat(parts, ", ")
end

-- Best value of `field` over every reached rank.
local function best(rebirths: number, field: string, default: number): number
	local value = default
	for _, tier in Config.REBIRTH_TIERS do
		local v = (tier :: any)[field]
		if rebirths >= tier.rebirths and type(v) == "number" and v > value then
			value = v
		end
	end
	return value
end

function Perks.rankIncomeBonus(rebirths: number): number
	return best(rebirths, "income", 0)
end

---------------------------------------------------------------------------
-- Upgrades and SlimeDex
---------------------------------------------------------------------------

function Perks.upgradeDef(id: string): Config.Upgrade?
	return upgradeDef(id)
end

function Perks.upgradeLevel(data: Progress, id: string): number
	local def = upgradeDef(id)
	local level = data.upgrades and data.upgrades[id]
	if not def or type(level) ~= "number" then
		return 0
	end
	return math.clamp(math.floor(level), 0, def.maxLevel)
end

local function upgradeEffect(data: Progress, id: string): number
	local def = upgradeDef(id)
	return if def then Perks.upgradeLevel(data, id) * def.step else 0
end

-- Sum of the bonuses of the first `paid` milestones of `list`.
local function paidBonus(list: { Config.DexMilestone }, paid: number?): number
	local total = 0
	for i = 1, math.clamp(math.floor(paid or 0), 0, #list) do
		total += list[i].bonus
	end
	return total
end

-- Income bonus from paid SlimeDex species milestones (0.05 = +5 %).
function Perks.dexBonus(data: Progress): number
	return paidBonus(Config.DEX_MILESTONES.species, data.speciesRewards)
end

---------------------------------------------------------------------------
-- Follow-pet passive: derived from the saved favourite, never stored
---------------------------------------------------------------------------

export type PetPassive = { kind: string, value: number, icon: string, text: string }

-- The favourite slime's perk, or nil with no favourite or an unknown tier.
function Perks.petPassive(data: Progress): PetPassive?
	local cfg = Config.PET_PASSIVES
	if not data.favoriteId or not data.slimes then
		return nil
	end
	for _, slime in data.slimes do
		if slime.id == data.favoriteId then
			local kind = cfg.KIND_BY_TIER[slime.tier]
			local def = if kind then cfg.KINDS[kind] else nil
			if not def then
				return nil
			end
			local value = math.min(slime.tier * def.perTier, def.cap)
			value = math.floor(value * 1000 + 0.5) / 1000
			return {
				kind = kind,
				value = value,
				icon = def.icon,
				text = `+{math.floor(value * 100 + 0.5)}% {def.word}`,
			}
		end
	end
	return nil
end

-- The passive's value when it is of `kind`, else 0.
local function petValue(data: Progress, kind: string): number
	local perk = Perks.petPassive(data)
	return if perk and perk.kind == kind then perk.value else 0
end

-- Everything except the rebirth multiplier: upgrade x rank x dex x code boost x friends x ritual x boss MVP x pet x
-- weekend x income Game Pass.
function Perks.bonusMultiplier(data: Progress): number
	return (1 + upgradeEffect(data, "Income"))
		* (1 + Perks.rankIncomeBonus(data.rebirths))
		* (1 + Perks.dexBonus(data))
		* math.max(data.boostMult or 1, 1)
		* (1 + math.max(data.friendBonus or 0, 0))
		* (1 + math.max(data.ritualBonus or 0, 0))
		* (1 + math.max(data.mvpBonus or 0, 0))
		* (1 + petValue(data, "income"))
		* math.max(data.weekendMult or 1, 1)
		* math.max(data.passIncomeMult or 1, 1)
end

-- State.incomeMultiplier: rebirth x upgrade x rank x dex.
function Perks.incomeMultiplier(data: Progress): number
	return Economy.rebirthMultiplier(data.rebirths) * Perks.bonusMultiplier(data)
end

-- Multiplier on the carry slowdown (1 = full slowdown).
function Perks.carrySlowFactor(data: Progress): number
	return math.max(0, 1 - upgradeEffect(data, "CarrySpeed"))
end

function Perks.offlineCap(data: Progress): number
	return Config.OFFLINE_CAP_SECONDS + upgradeEffect(data, "OfflineCap")
end

-- Multiplier on merge vat brew times (Quick Brew x the Fast Brew pass; 1 = full time).
function Perks.brewFactor(data: Progress): number
	local pass = math.clamp(data.passBrewFactor or 1, 0, 1)
	return math.max(0, 1 - upgradeEffect(data, "QuickBrew")) * pass
end

-- Chance that a wild slime this player deposits is one rarity higher, without the Lucky Charm+ pass.
function Perks.baseLuckChance(data: Progress): number
	return upgradeEffect(data, "Luck") + petValue(data, "luck")
end

-- Chance that a wild slime this player deposits is one rarity higher (the Lucky Charm+ pass included).
function Perks.luckChance(data: Progress): number
	return Perks.baseLuckChance(data) + math.max(data.passLuckBonus or 0, 0)
end

return table.freeze(Perks)
