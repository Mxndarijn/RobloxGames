--!strict
--[[
	Upgrades

	Permanent upgrades bought with Request("BuyUpgrade", id) (CONTRACT.md
	§8.1, §8.8): Config.UPGRADES, each gated by a rebirth count (or one per level), level n+1
	costs base x growth^n. Effects are in Perks. Kept on rebirth. `view` is
	State.upgrades. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Perks = if script then require(script.Parent.Perks) else require("./Perks")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Data = PlayerData.Data

export type View = {
	id: string,
	name: string,
	text: string,
	level: number,
	maxLevel: number,
	price: number?, -- nil = maxed or locked
	requires: number, -- rebirths needed for the next level
	unlocked: boolean,
}

local Upgrades = {}

-- Whether an upgrade exists for players right now: one tied to a feature flag only while it is on.
function Upgrades.available(def: Config.Upgrade): boolean
	return def.flag == nil or (Config.FEATURES :: any)[def.flag] == true
end

-- Price of the level after `level`, or nil when maxed / unknown.
function Upgrades.cost(id: string, level: number): number?
	local def = Perks.upgradeDef(id)
	if not def or level >= def.maxLevel then
		return nil
	end
	return math.floor(def.base * def.growth ^ level)
end

-- Rebirths needed to buy the level after `level` (Config.Upgrade.levelRequires, else `requires`).
function Upgrades.requiresFor(def: Config.Upgrade, level: number): number
	local perLevel = def.levelRequires
	if perLevel then
		return perLevel[math.clamp(level + 1, 1, #perLevel)] or def.requires
	end
	return def.requires
end

-- Whether the player may buy the next level of `id` (enough rebirths for it).
function Upgrades.unlocked(data: Data, id: string): boolean
	local def = Perks.upgradeDef(id)
	return def ~= nil and data.rebirths >= Upgrades.requiresFor(def, Perks.upgradeLevel(data, id))
end

-- Returns (ok, priceOrReason).
function Upgrades.buy(data: Data, id: string): (boolean, number | string)
	local def = Perks.upgradeDef(id)
	if not def or not Upgrades.available(def) then
		return false, "unknown upgrade"
	end
	local level = Perks.upgradeLevel(data, id)
	local needs = Upgrades.requiresFor(def, level)
	if data.rebirths < needs then
		return false, `locked: reach {needs} rebirths`
	end
	local cost = Upgrades.cost(id, level)
	if not cost then
		return false, "already maxed"
	end
	if not PlayerData.spend(data, cost) then
		return false, "not enough cash"
	end
	data.upgrades[id] = level + 1
	return true, cost
end

function Upgrades.view(data: Data): { View }
	local out = {}
	for _, def in Config.UPGRADES do
		if not Upgrades.available(def) then
			continue
		end
		local level = Perks.upgradeLevel(data, def.id)
		local needs = Upgrades.requiresFor(def, level)
		local unlocked = data.rebirths >= needs
		table.insert(out, {
			id = def.id,
			name = def.name,
			text = def.text,
			level = level,
			maxLevel = def.maxLevel,
			price = if unlocked then Upgrades.cost(def.id, level) else nil,
			requires = needs,
			unlocked = unlocked,
		})
	end
	return out
end

return table.freeze(Upgrades)
