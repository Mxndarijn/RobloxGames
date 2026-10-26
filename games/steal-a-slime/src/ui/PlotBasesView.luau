--!strict
--[[
	PlotBasesView

	The base strip of the Plot skins menu (Panels/Skins, contract/base-shapes.md), pure (tests/ui/PlotBasesMenu.spec):
	State.plotBases becomes one button per base (the goo jar tower first): its name and what pressing it does,
	Equip, Equipped, or the rebirth it unlocks at. The server decides unlocks; this module only formats them.
]]

local PlotBasesView = {}

export type State = "equipped" | "unlocked" | "locked"

export type Row = {
	key: string, -- "base:<id>"
	id: string,
	title: string,
	state: State,
	action: string, -- "Equip" / "Equipped" / "Rebirth 20"
}

PlotBasesView.EQUIPPED = "Equipped"
PlotBasesView.EQUIP = "Equip"

local function stateOf(base: any): State
	return if base.equipped == true then "equipped" elseif base.unlocked == true then "unlocked" else "locked"
end

-- One row per State.plotBases entry (as the server sends them). Empty without the field (FEATURES.BaseShapes off).
function PlotBasesView.rows(plotBases: any): { Row }
	local out: { Row } = {}
	if type(plotBases) ~= "table" then
		return out
	end
	for _, base in plotBases do
		if type(base) == "table" and type(base.id) == "string" then
			local state = stateOf(base)
			local rebirths = if type(base.rebirths) == "number" then base.rebirths else 0
			local row: Row = {
				key = `base:{base.id}`,
				id = base.id,
				title = if type(base.name) == "string" then base.name else base.id,
				state = state,
				action = if state == "equipped"
					then PlotBasesView.EQUIPPED
					elseif state == "unlocked" then PlotBasesView.EQUIP
					else `Rebirth {rebirths}`,
			}
			table.insert(out, row)
		end
	end
	return out
end

return table.freeze(PlotBasesView)
