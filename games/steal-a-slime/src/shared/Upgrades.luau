--!strict
--[[
	Upgrades

	Permanent upgrades bought with Request("BuyUpgrade", id) (CONTRACT.md
	§8.1, §8.8): Config.UPGRADES, each gated by a rebirth count, level n+1
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
	requires: number,
	unlocked: boolean,
}

local Upgrades = {}

-- Price of the level after `level`, or nil when maxed / unknown.
function Upgrades.cost(id: string, level: number): number?
	local def = Perks.upgradeDef(id)
	if not def or level >= def.maxLevel then
		return nil
	end
	return math.floor(def.base * def.growth ^ level)
end

function Upgrades.unlocked(data: Data, id: string): boolean
	local def = Perks.upgradeDef(id)
	return def ~= nil and data.rebirths >= def.requires
end

-- Returns (ok, priceOrReason).
function Upgrades.buy(data: Data, id: string): (boolean, number | string)
	local def = Perks.upgradeDef(id)
	if not def then
		return false, "unknown upgrade"
	end
	if data.rebirths < def.requires then
		return false, `locked: reach {def.requires} rebirths`
	end
	local level = Perks.upgradeLevel(data, id)
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
		local level = Perks.upgradeLevel(data, def.id)
		local unlocked = data.rebirths >= def.requires
		table.insert(out, {
			id = def.id,
			name = def.name,
			text = def.text,
			level = level,
			maxLevel = def.maxLevel,
			price = if unlocked then Upgrades.cost(def.id, level) else nil,
			requires = def.requires,
			unlocked = unlocked,
		})
	end
	return out
end

return table.freeze(Upgrades)
