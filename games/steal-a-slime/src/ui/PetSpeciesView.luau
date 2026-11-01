--!strict
--[[
	PetSpeciesView

	The Skins menu's Pet tab content (Panels/Skins), pure (tests/ui/PetSpeciesMenu.spec). The slime that rides the
	follow pet's cloud: "Auto" (State.petSpecies nil or "": the favourite, else the best slime, as before) or any
	species found in the SlimeDex (State.dex, as SlimeDex.cards). One row per Dex card that has a species kit, in Dex
	order, after Auto; a species not found yet is locked and shows grey. The pane for the selected row ends in
	Equip (SetPetSpecies), Equipped, or a well saying to find it first. The server decides what may ride; this
	module only formats it.
]]

local PlotSkinsView = if script then require(script.Parent.PlotSkinsView) else require("./PlotSkinsView")

local PetSpeciesView = {}

export type State = "equipped" | "unlocked" | "locked"

export type Row = {
	key: string, -- "pet:auto" / "pet:<species>"
	id: string, -- "" for Auto
	auto: boolean,
	title: string,
	state: State,
	found: boolean,
	tier: number,
	speciesColor: { number },
}

export type Detail = {
	id: string,
	auto: boolean,
	title: string,
	state: State,
	found: boolean,
	tier: number,
	speciesColor: { number },
	line: string,
	action: string, -- "Equip" / "Equipped" / "Find it in the SlimeDex first"
	exclusive: boolean, -- always false (Skins' shared button code reads it)
}

PetSpeciesView.AUTO = "Auto"
PetSpeciesView.AUTO_KEY = "pet:auto"
PetSpeciesView.AUTO_STATE = "Your favourite"
PetSpeciesView.AUTO_LINE = "Your favourite slime rides the cloud."
PetSpeciesView.FOUND = "Found"
PetSpeciesView.NOT_FOUND = "Not found yet"
PetSpeciesView.FOUND_LINE = "Rides your cloud. Looks only."
PetSpeciesView.LOCKED_LINE = "Find this slime to use it as your pet."
PetSpeciesView.LOCKED_ACTION = "Find it in the SlimeDex first"

local AUTO_COLOR = { 255, 210, 63 }

-- The species State.petSpecies names, nil for Auto.
local function picked(petSpecies: any): string?
	return if type(petSpecies) == "string" and petSpecies ~= "" then petSpecies else nil
end

-- Auto, then one row per card (SlimeDex.cards) whose species has a kit (`hasKit`, nil = every species): the found
-- ones first, then the rest, each part in Dex order.
function PetSpeciesView.rows(cards: { any }, petSpecies: any, hasKit: ((id: string) -> boolean)?): { Row }
	local current = picked(petSpecies)
	local out: { Row } = {
		{
			key = PetSpeciesView.AUTO_KEY,
			id = "",
			auto = true,
			title = PetSpeciesView.AUTO,
			state = if current == nil then "equipped" else "unlocked",
			found = true,
			tier = 1,
			speciesColor = AUTO_COLOR,
		},
	}
	local later: { Row } = {}
	for _, card in cards do
		if type(card) == "table" and type(card.key) == "string" and (hasKit == nil or hasKit(card.key)) then
			local found = card.found == true
			table.insert(if found then out else later, {
				key = `pet:{card.key}`,
				id = card.key,
				auto = false,
				title = card.title,
				state = if not found then "locked" elseif card.key == current then "equipped" else "unlocked",
				found = found,
				tier = card.tier,
				speciesColor = card.speciesColor,
			})
		end
	end
	table.move(later, 1, #later, #out + 1, out)
	return out
end

-- The pane for row `id` ("" = Auto), or nil when there is no such row.
function PetSpeciesView.detail(rows: { Row }, id: string): Detail?
	for _, row in rows do
		if row.id == id then
			return {
				id = row.id,
				auto = row.auto,
				title = row.title,
				state = row.state,
				found = row.found,
				tier = row.tier,
				speciesColor = row.speciesColor,
				line = if row.auto
					then PetSpeciesView.AUTO_LINE
					elseif row.found then PetSpeciesView.FOUND_LINE
					else PetSpeciesView.LOCKED_LINE,
				action = if row.state == "equipped"
					then PlotSkinsView.EQUIPPED
					elseif row.state == "unlocked" then PlotSkinsView.EQUIP
					else PetSpeciesView.LOCKED_ACTION,
				exclusive = false,
			}
		end
	end
	return nil
end

-- The row's small state line: Equipped / Your favourite / Found / Not found yet.
function PetSpeciesView.stateText(row: Row): string
	if row.state == "equipped" then
		return PlotSkinsView.EQUIPPED
	elseif row.auto then
		return PetSpeciesView.AUTO_STATE
	end
	return if row.found then PetSpeciesView.FOUND else PetSpeciesView.NOT_FOUND
end

-- The row to show first: the equipped one, else Auto.
function PetSpeciesView.firstSelected(rows: { Row }): string?
	for _, row in rows do
		if row.state == "equipped" then
			return row.id
		end
	end
	return if rows[1] then rows[1].id else nil
end

-- "12/61 found" (species rows only).
function PetSpeciesView.summary(rows: { Row }): string
	local found, total = 0, 0
	for _, row in rows do
		if not row.auto then
			total += 1
			if row.found then
				found += 1
			end
		end
	end
	return `{found}/{total} found`
end

return table.freeze(PetSpeciesView)
