--!strict
--[[
	SlimeLabel (pure, contract/slime-labels.md)

	The text of a slime's label: the floating tag above a wild, carried or
	escaping slime, and the sign on the pad of a slime resting on it. The
	server writes the model attributes from a slime (`attributes`), the client
	turns the attributes back into label values (`view`). No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Constants = if script then require(script.Parent.Constants) else require("./Constants")
local EggKind = if script then require(script.Parent.EggKind) else require("./EggKind")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Growth = if script then require(script.Parent.Growth) else require("./Growth")
local NumberFormat = if script then require(script.Parent.NumberFormat) else require("./NumberFormat")

export type View = {
	name: string, -- "Lop", "BOSS Lop"
	rarity: string, -- "Rare"
	tier: number, -- Config.RARITIES index
	rarityColor: { number }, -- { r, g, b } of Config.RARITIES
	income: string?, -- "+$1.25K/s", "+$0.8/s" (a wild slime's with the viewer's bonuses); nil for a boss
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
	status: any,
	owner: any, -- OwnerUserId: 0 / nil for a wild slime
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
	status = Constants.LABEL_STATUS_ATTRIBUTE,
	owner = "OwnerUserId",
})

local function finite(n: any): number?
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return n
end

-- The top rarity (Secret) is drawn in every colour instead of one: these stops, left to right or top to bottom.
SlimeLabel.RAINBOW = table.freeze({
	table.freeze({ 255, 92, 120 }),
	table.freeze({ 255, 214, 64 }),
	table.freeze({ 96, 240, 140 }),
	table.freeze({ 80, 200, 255 }),
	table.freeze({ 196, 110, 255 }),
})

-- True for the top rarity, which labels draw as a rainbow (Config.MAX_TIER, so a new rarity moves it along).
function SlimeLabel.isRainbow(view: View): boolean
	return view.tier >= Config.MAX_TIER
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

-- Name / tier attribute values for a slime (LabelIncome is written separately); an egg shows its egg name and tier.
function SlimeLabel.attributes(slime: Genome.Slime): (string, number)
	local kind = EggKind.of(slime)
	if kind then
		return EggKind.displayName(kind), kind.tier
	end
	local name = if slime.brewed == 1 then `Brewed {slime.name}` else slime.name
	if slime.shine then
		name = `{slime.shine} {name}`
	end
	return name, Genome.rarity(slime.tier).tier
end

-- "m:ss" for a non-negative number of seconds (rounded up).
function SlimeLabel.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- The status row of a Mystery Egg at `now` (LabelStatus), nil for a slime.
function SlimeLabel.eggStatus(slime: Genome.Slime, now: number): string?
	local kind = EggKind.of(slime)
	if not kind then
		return nil
	end
	local hatchAt = slime.egg and slime.egg.hatchAt
	if not hatchAt then
		return `Hatches in {SlimeLabel.clock(kind.hatchSeconds)} on a pad`
	elseif hatchAt <= now then
		return "Ready to hatch!"
	end
	return `Hatches in {SlimeLabel.clock(hatchAt - now)}`
end

-- Whether the label of a model hatched at server time `hatchedAt` (its HatchedAt attribute) waits for the hatch
-- show's reveal at `now` (contract/mystery-egg.md §40.6).
function SlimeLabel.hiddenByHatch(hatchedAt: any, now: number): boolean
	return type(hatchedAt) == "number"
		and now >= hatchedAt - 1
		and now < hatchedAt + Config.MYSTERY_EGG.HATCH_REVEAL_SECONDS
end

-- True for a slime nobody owns (OwnerUserId 0 or missing): its LabelIncome is the base rate, before anyone's bonuses.
function SlimeLabel.isWild(attrs: Attributes): boolean
	local owner = finite(attrs.owner)
	return owner == nil or owner <= 0
end

-- Income a wild slime's tag shows to a player: its base rate times that player's State.incomeMultiplier (rebirths
-- and every income bonus), what it would earn on their pad. An owned slime's LabelIncome already counts its owner's
-- bonuses and is shown as is. A missing or bad multiplier counts as 1.
function SlimeLabel.shownIncome(attrs: Attributes, multiplier: number?): number
	local income = finite(attrs.income) or 0
	local mult = finite(multiplier)
	if not SlimeLabel.isWild(attrs) or mult == nil or mult <= 0 then
		return income
	end
	return income * mult
end

-- Label values from the attributes; nil when the model carries no LabelName yet. `multiplier` is the viewing
-- player's State.incomeMultiplier (SlimeLabel.shownIncome).
function SlimeLabel.view(attrs: Attributes, multiplier: number?): View?
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
		income = if type(attrs.status) == "string" and attrs.status ~= ""
			then attrs.status
			elseif attrs.boss == true then nil
			else SlimeLabel.incomeText(SlimeLabel.shownIncome(attrs, multiplier)),
		price = SlimeLabel.priceText(attrs.price),
		growth = Growth.percentAt((finite(attrs.growth) or 0) / 100),
		pad = if pad and pad >= 1 then math.floor(pad) else nil,
	}
end

-- Number of text rows the floating tag draws for a view: rarity, name, income, then the price when for sale.
-- A boss has no income row (and is never for sale): rarity and name only.
function SlimeLabel.rows(view: View): number
	if not view.income then
		return 2
	end
	return if view.price then 4 else 3
end

return table.freeze(SlimeLabel)
