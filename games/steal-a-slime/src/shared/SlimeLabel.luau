--!strict
--[[
	SlimeLabel (pure, contract/slime-labels.md)

	The text of a slime's label: the floating tag above a wild, carried or
	escaping slime, and the sign on the pad of a slime resting on it. The
	server writes the model attributes from a slime (`attributes`), the client
	turns the attributes back into label values (`view`). No Roblox APIs.
]]

local Constants = if script then require(script.Parent.Constants) else require("./Constants")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Growth = if script then require(script.Parent.Growth) else require("./Growth")
local NumberFormat = if script then require(script.Parent.NumberFormat) else require("./NumberFormat")

export type View = {
	name: string, -- "Lop", "BOSS Lop"
	rarity: string, -- "Rare"
	tier: number, -- Config.RARITIES index
	rarityColor: { number }, -- { r, g, b } of Config.RARITIES
	income: string, -- "+$1.25K/s", "+$0.8/s"
	price: string?, -- "$500" for a priced wild slime; nil = not for sale
	growth: number, -- whole percent 0..100 (the pad sign's bar)
	pad: number?, -- pad index while the slime rests on a pad: the label is the pad sign, not the tag
}

-- What the label reads; the attribute names are in `SlimeLabel.ATTRIBUTES`.
export type Attributes = {
	name: any,
	tier: any,
	income: any,
	price: any,
	growth: any,
	boss: any,
	pad: any,
}

local SlimeLabel = {}

-- Attributes field -> model attribute name.
SlimeLabel.ATTRIBUTES = table.freeze({
	name = Constants.LABEL_NAME_ATTRIBUTE,
	tier = Constants.LABEL_TIER_ATTRIBUTE,
	income = Constants.LABEL_INCOME_ATTRIBUTE,
	price = "Price",
	growth = Constants.GROWTH_ATTRIBUTE,
	boss = Constants.BOSS_ATTRIBUTE,
	pad = Constants.LABEL_PAD_ATTRIBUTE,
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

-- "$500" for a priced wild slime; nil when it is free or not for sale.
function SlimeLabel.priceText(price: any): string?
	local p = finite(price)
	return if p and p > 0 then NumberFormat.cash(p) else nil
end

-- Name / tier attribute values for a slime (LabelIncome is written separately).
function SlimeLabel.attributes(slime: Genome.Slime): (string, number)
	return slime.name, Genome.rarity(slime.tier).tier
end

-- Label values from the attributes; nil when the model carries no LabelName yet.
function SlimeLabel.view(attrs: Attributes): View?
	if type(attrs.name) ~= "string" or attrs.name == "" then
		return nil
	end
	local rarity = Genome.rarity(finite(attrs.tier) or 1)
	local pad = finite(attrs.pad)
	return {
		name = if attrs.boss == true then `BOSS {attrs.name}` else attrs.name,
		rarity = rarity.name,
		tier = rarity.tier,
		rarityColor = rarity.color,
		income = SlimeLabel.incomeText(attrs.income),
		price = SlimeLabel.priceText(attrs.price),
		growth = Growth.percentAt((finite(attrs.growth) or 0) / 100),
		pad = if pad and pad >= 1 then math.floor(pad) else nil,
	}
end

-- Number of text rows the floating tag draws for a view: name, rarity, income, then the price when for sale.
function SlimeLabel.rows(view: View): number
	return if view.price then 4 else 3
end

return table.freeze(SlimeLabel)
