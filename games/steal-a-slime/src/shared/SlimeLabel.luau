--!strict
--[[
	SlimeLabel (pure, contract/slime-labels.md)

	The text of the info card above a slime. The server writes the model
	attributes from a slime (`attributes`), the client turns the attributes
	back into card lines (`view`). No Roblox APIs.
]]

local Constants = if script then require(script.Parent.Constants) else require("./Constants")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Growth = if script then require(script.Parent.Growth) else require("./Growth")
local NumberFormat = if script then require(script.Parent.NumberFormat) else require("./NumberFormat")

export type View = {
	name: string, -- "Lop", "BOSS Lop"
	rarity: string, -- "Rare"
	rarityColor: { number }, -- { r, g, b } of Config.RARITIES
	mutation: string?, -- "Glow Syrup"; nil = none
	income: string, -- "+$1.25K/s", "+$0.8/s"
	extra: string?, -- "Buy $500" (priced wild) or "Growth 46%" (pad); nil = nothing
}

-- What the card reads; the attribute names are in `SlimeLabel.ATTRIBUTES`.
export type Attributes = {
	name: any,
	tier: any,
	mutations: any,
	income: any,
	price: any,
	growth: any,
	boss: any,
}

local SlimeLabel = {}

-- Attributes field -> model attribute name.
SlimeLabel.ATTRIBUTES = table.freeze({
	name = Constants.LABEL_NAME_ATTRIBUTE,
	tier = Constants.LABEL_TIER_ATTRIBUTE,
	mutations = Constants.LABEL_MUTATIONS_ATTRIBUTE,
	income = Constants.LABEL_INCOME_ATTRIBUTE,
	price = "Price",
	growth = Constants.GROWTH_ATTRIBUTE,
	boss = Constants.BOSS_ATTRIBUTE,
})

local function finite(n: any): number?
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

-- "+$1.25K/s", "+$0.8/s" (NumberFormat.rate, as the HUD); garbage and negatives show "+$0/s".
function SlimeLabel.incomeText(perSec: any): string
	return "+" .. NumberFormat.rate(math.max(finite(perSec) or 0, 0))
end

-- True when the shown income text would change (the server rewrites LabelIncome only then).
function SlimeLabel.incomeChanged(shown: any, perSec: number): boolean
	return finite(shown) == nil or SlimeLabel.incomeText(shown) ~= SlimeLabel.incomeText(perSec)
end

-- "Buy $500" for a priced wild slime, else "Growth 46%" while grown, else nil.
function SlimeLabel.extraText(price: any, growth: any): string?
	local p = finite(price)
	if p and p > 0 then
		return `Buy {NumberFormat.cash(p)}`
	end
	local g = finite(growth)
	return if g then Growth.labelText(g) else nil
end

-- Name / tier / mutations attribute values for a slime (LabelIncome is written separately).
function SlimeLabel.attributes(slime: Genome.Slime): (string, number, string?)
	local mutations = Genome.mutationsDisplay(Genome.mutationList(slime))
	return slime.name, Genome.rarity(slime.tier).tier, if mutations ~= "" then mutations else nil
end

-- Card lines from the attributes; nil when the model carries no LabelName yet.
function SlimeLabel.view(attrs: Attributes): View?
	if type(attrs.name) ~= "string" or attrs.name == "" then
		return nil
	end
	local rarity = Genome.rarity(finite(attrs.tier) or 1)
	local mutation = if type(attrs.mutations) == "string" and attrs.mutations ~= "" then attrs.mutations else nil
	return {
		name = if attrs.boss == true then `BOSS {attrs.name}` else attrs.name,
		rarity = rarity.name,
		rarityColor = rarity.color,
		mutation = mutation,
		income = SlimeLabel.incomeText(attrs.income),
		extra = SlimeLabel.extraText(attrs.price, attrs.growth),
	}
end

-- Number of text rows the card draws for a view: name, rarity line, income, extra.
function SlimeLabel.rows(view: View): number
	return if view.extra then 4 else 3
end

return table.freeze(SlimeLabel)
