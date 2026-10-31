--!strict
--[[
	PlotBasesView

	The Skins menu's Building tab (Panels/Skins, contract/base-shapes.md), pure (tests/ui/PlotBasesMenu.spec):
	State.plotBases becomes one row per base (the goo jar tower first), shaped like the Cloud tab's seat rows
	(PetSeatsView): its name and Equipped / Unlocked, or, for an Exclusive base not owned yet, a gold Exclusive tag
	and its Robux price. The pane for the selected base says how to get it and what its button does: Equip,
	Equipped, or Buy · R$<price>, which hands the base's Purchase (Base_<id>, Config.EXCLUSIVE_SHOP) to the
	PurchasePrompt adapter; while the product is not on sale the button opens the Exclusive shop on the base's
	card instead. The server decides unlocks and grants; this module only formats them.
]]

local ExclusiveShopView = if script then require(script.Parent.ExclusiveShopView) else require("./ExclusiveShopView")
local Format = if script then require(script.Parent.Format) else require("./Format")
local PetSeatsView = if script then require(script.Parent.PetSeatsView) else require("./PetSeatsView")
local PlotSkinsView = if script then require(script.Parent.PlotSkinsView) else require("./PlotSkinsView")

local PlotBasesView = {}

export type State = "equipped" | "unlocked" | "locked"

-- Same shape as a seat row, so the panel draws both with one row builder.
export type Row = PetSeatsView.Row
export type Detail = PetSeatsView.Detail

PlotBasesView.EQUIPPED = PlotSkinsView.EQUIPPED
PlotBasesView.EQUIP = PlotSkinsView.EQUIP
PlotBasesView.EXCLUSIVE = ExclusiveShopView.EXCLUSIVE
PlotBasesView.FREE_LINE = "Every player has this building."
PlotBasesView.OWNED_LINE = "You own this building."
PlotBasesView.EXCLUSIVE_LINE = PetSeatsView.EXCLUSIVE_LINE
PlotBasesView.EXCLUSIVE_ACTION = PetSeatsView.EXCLUSIVE_ACTION
PlotBasesView.EMPTY = "Buildings are not on this server."

local DEFAULT_COLOR: { number } = { 200, 200, 200 }

local function stateOf(base: any): State
	return if base.equipped == true then "equipped" elseif base.unlocked == true then "unlocked" else "locked"
end

local function offerOf(base: any, config: any?): ExclusiveShopView.Offer?
	local key = if type(base.productKey) == "string" then base.productKey else `Base_{base.id}`
	return if config ~= nil then ExclusiveShopView.offer(config, key) else nil
end

local function titleOf(base: any): string
	return Format.sentenceCase(if type(base.name) == "string" then base.name else base.id)
end

local function find(plotBases: any, id: string): any
	if type(plotBases) ~= "table" then
		return nil
	end
	for _, base in plotBases :: { any } do
		if type(base) == "table" and base.id == id then
			return base
		end
	end
	return nil
end

-- One row per State.plotBases entry (as the server sends them). Empty without the field (FEATURES.BaseShapes off).
-- `config` (shared Config) prices an Exclusive base.
function PlotBasesView.rows(plotBases: any, config: any?): { Row }
	local out: { Row } = {}
	if type(plotBases) ~= "table" then
		return out
	end
	for _, base in plotBases :: { any } do
		if type(base) == "table" and type(base.id) == "string" then
			local state: State = stateOf(base)
			local exclusive = base.exclusive == true and state == "locked"
			local offer = if exclusive then offerOf(base, config) else nil
			table.insert(out, {
				key = `base:{base.id}`,
				id = base.id,
				title = titleOf(base),
				state = state,
				exclusive = exclusive,
				line = "",
				count = "",
				fraction = if state == "locked" then 0 else 1,
				color = DEFAULT_COLOR,
				price = if offer then offer.price else "",
			})
		end
	end
	return out
end

-- The pane for base `id`, or nil when State has no such base.
function PlotBasesView.detail(plotBases: any, id: string, config: any?): Detail?
	local base = find(plotBases, id)
	if base == nil then
		return nil
	end
	local state: State = stateOf(base)
	local exclusive = base.exclusive == true and state == "locked"
	local offer = if exclusive then offerOf(base, config) else nil
	return {
		id = id,
		title = titleOf(base),
		state = state,
		exclusive = exclusive,
		heading = if exclusive then PetSeatsView.HOW_GET else "",
		line = if exclusive
			then PlotBasesView.EXCLUSIVE_LINE
			elseif base.exclusive == true then PlotBasesView.OWNED_LINE
			else PlotBasesView.FREE_LINE,
		count = nil,
		fraction = if state == "locked" then 0 else 1,
		action = if state == "equipped"
			then PlotBasesView.EQUIPPED
			elseif state == "unlocked" then PlotBasesView.EQUIP
			elseif offer and offer.purchase then offer.text
			else PlotBasesView.EXCLUSIVE_ACTION,
		purchase = if offer then offer.purchase else nil,
		shopKey = if exclusive then `plotBase:{id}` else nil,
	}
end

-- The base to show first: the equipped one, else the first.
PlotBasesView.firstSelected = PetSeatsView.firstSelected

-- "1/8 unlocked"
PlotBasesView.summary = PetSeatsView.summary

return table.freeze(PlotBasesView)
