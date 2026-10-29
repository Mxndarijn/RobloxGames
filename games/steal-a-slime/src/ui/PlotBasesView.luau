--!strict
--[[
	PlotBasesView

	The base strip of the Plot skins menu (Panels/Skins, contract/base-shapes.md), pure (tests/ui/PlotBasesMenu.spec):
	State.plotBases becomes one button per base (the goo jar tower first): its name and what pressing it does,
	Equip, Equipped, the rebirth it unlocks at, or, for an Exclusive base not owned yet, a gold "Exclusive" tag and
	"Buy · R$<price>". Buy hands the base's Purchase (Base_<id>, Config.EXCLUSIVE_SHOP) to the PurchasePrompt adapter;
	while the product is not on sale it opens the Exclusive shop on the base's card instead. The server decides
	unlocks and grants; this module only formats them.
]]

local ExclusiveShopView = if script then require(script.Parent.ExclusiveShopView) else require("./ExclusiveShopView")
local Format = if script then require(script.Parent.Format) else require("./Format")

local PlotBasesView = {}

export type State = "equipped" | "unlocked" | "locked"

export type Row = {
	key: string, -- "base:<id>"
	id: string,
	title: string,
	state: State,
	action: string, -- "Equip" / "Equipped" / "Rebirth 20" / "Buy · R$<price>"
	exclusive: boolean, -- an Exclusive base not owned yet: the gold tag and Buy
	purchase: ExclusiveShopView.Purchase?, -- exclusive and on sale: what Roblox's prompt sells
	shopKey: string?, -- exclusive: its Exclusive shop card ("plotBase:<id>")
}

PlotBasesView.EQUIPPED = "Equipped"
PlotBasesView.EQUIP = "Equip"
PlotBasesView.EXCLUSIVE = ExclusiveShopView.EXCLUSIVE

local function stateOf(base: any): State
	return if base.equipped == true then "equipped" elseif base.unlocked == true then "unlocked" else "locked"
end

local function onSale(p: ExclusiveShopView.Purchase?): boolean
	return p ~= nil and type(p.id) == "number" and p.id > 0
end

-- One row per State.plotBases entry (as the server sends them). Empty without the field (FEATURES.BaseShapes off).
-- `config` (shared Config) finds an Exclusive base's product id; without it Buy opens the shop.
function PlotBasesView.rows(plotBases: any, config: any?): { Row }
	local out: { Row } = {}
	if type(plotBases) ~= "table" then
		return out
	end
	for _, base in plotBases do
		if type(base) == "table" and type(base.id) == "string" then
			local state = stateOf(base)
			local rebirths = if type(base.rebirths) == "number" then base.rebirths else 0
			local exclusive = base.exclusive == true and state == "locked"
			local purchase = if exclusive
					and type(base.productKey) == "string"
					and config ~= nil
				then ExclusiveShopView.productPurchase(config, base.productKey)
				else nil
			local robux = if type(base.robux) == "number" then base.robux else 0
			local row: Row = {
				key = `base:{base.id}`,
				id = base.id,
				title = if type(base.name) == "string" then base.name else base.id,
				state = state,
				action = if state == "equipped"
					then PlotBasesView.EQUIPPED
					elseif state == "unlocked" then PlotBasesView.EQUIP
					elseif exclusive then `Buy · {Format.robux(robux)}`
					else `Rebirth {rebirths}`,
				exclusive = exclusive,
				purchase = if onSale(purchase) then purchase else nil,
				shopKey = if exclusive then `plotBase:{base.id}` else nil,
			}
			table.insert(out, row)
		end
	end
	return out
end

return table.freeze(PlotBasesView)
