--!strict
--[[
	Perks

	What a player's progression does (CONTRACT.md §8.8), as plain formulas
	over PlayerData fields and Config, so PlayerData / Economy users can apply
	them without a require cycle:
	  * rebirth ranks (Config.REBIRTH_TIERS): title, keep count, income and
	    lock bonuses; the best unlocked value wins, they don't stack;
	  * upgrade levels (Config.UPGRADES): income, carry slowdown, offline cap,
	    luck;
	  * SlimeDex milestone bonus (Config.DEX_MILESTONES, data.dexRewards paid).
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")

-- The fields Perks reads (a PlayerData.Data satisfies it).
export type Progress = {
	rebirths: number,
	upgrades: { [string]: number },
	dexRewards: number,
	boostMult: number?, -- redeem-code income boost while active (Codes), nil / 1 = none
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

-- "unlocks Strong Arms, keep 2 slimes, +25% income, +30s locks" (empty for the first rank).
function Perks.tierText(tier: Config.RebirthTier): string
	local parts = {}
	if tier.unlock then
		local def = upgradeDef(tier.unlock)
		table.insert(parts, `unlocks the {if def then def.name else tier.unlock} upgrade`)
	end
	if tier.keep then
		table.insert(parts, `keep {tier.keep} slimes on rebirth`)
	end
	if tier.income then
		table.insert(parts, `+{math.floor(tier.income * 100 + 0.5)}% income`)
	end
	if tier.lock then
		table.insert(parts, `+{tier.lock}s locks`)
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

-- Slimes kept on rebirth (favourite first, then the best).
function Perks.keepCount(rebirths: number): number
	return best(rebirths, "keep", 1)
end

function Perks.rankIncomeBonus(rebirths: number): number
	return best(rebirths, "income", 0)
end

-- Extra seconds on every bought lock (Steal.lockDuration).
function Perks.lockBonus(rebirths: number): number
	return best(rebirths, "lock", 0)
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

-- Income bonus from paid SlimeDex milestones (0.05 = +5 %).
function Perks.dexBonus(data: Progress): number
	local total = 0
	for i = 1, math.clamp(data.dexRewards or 0, 0, #Config.DEX_MILESTONES) do
		total += Config.DEX_MILESTONES[i].bonus
	end
	return total
end

-- Everything except the rebirth multiplier: upgrade x rank x dex x code boost.
function Perks.bonusMultiplier(data: Progress): number
	return (1 + upgradeEffect(data, "Income"))
		* (1 + Perks.rankIncomeBonus(data.rebirths))
		* (1 + Perks.dexBonus(data))
		* math.max(data.boostMult or 1, 1)
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

-- Chance that a wild slime this player deposits is one rarity higher.
function Perks.luckChance(data: Progress): number
	return upgradeEffect(data, "Luck")
end

return table.freeze(Perks)
