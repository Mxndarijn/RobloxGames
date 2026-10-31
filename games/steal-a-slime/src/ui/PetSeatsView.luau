--!strict
--[[
	PetSeatsView

	The Skins menu's Cloud tab content (Panels/Skins), pure (tests/ui/PetSeatsMenu.spec). State.petSeats
	(contract/pet-seats.md) becomes one row per seat: its name and either its state (Equipped / Unlocked), its
	unlock in one line with a bar and a count (a free unlock), or an Exclusive tag with its Robux price. The pane for
	the selected seat repeats how to unlock it and what its button does: Equip, Equipped, what is still missing, or
	Buy · R$<price> (Seat_<id>, Roblox's prompt; the Exclusive shop on that seat while it is not on sale). The
	server decides unlocks and grants; this module only formats them.
]]

local ExclusiveShopView = if script then require(script.Parent.ExclusiveShopView) else require("./ExclusiveShopView")
local Format = if script then require(script.Parent.Format) else require("./Format")
local PlotSkinsView = if script then require(script.Parent.PlotSkinsView) else require("./PlotSkinsView")

local PetSeatsView = {}

export type State = "equipped" | "unlocked" | "locked"

export type Row = {
	key: string, -- "seat:<id>"
	id: string,
	title: string,
	state: State,
	exclusive: boolean, -- an Exclusive not owned yet: the Exclusive tag and its price, never a bar
	line: string, -- how to unlock it ("Merge 200 slimes."); "" once unlocked and for an Exclusive
	count: string, -- "136/200" or "52%/80%" toward a free unlock; "" otherwise
	fraction: number, -- 0..1 toward a free unlock (1 once unlocked)
	color: { number }, -- icon tile colour
	price: string, -- an Exclusive's Robux price ("R$199"); "" otherwise
}

-- The pane for one item of the Cloud or Building tab (PlotBasesView.detail has the same shape).
export type Detail = {
	id: string,
	title: string,
	state: State,
	exclusive: boolean,
	heading: string, -- "How to unlock" / "How to get it"; "" for the free cloud
	line: string,
	count: string?,
	fraction: number,
	action: string, -- "Equip" / "Equipped" / "Merge 64 more slimes" / "Buy · R$199" / "Exclusive shop"
	purchase: ExclusiveShopView.Purchase?, -- an Exclusive on sale: what Buy prompts
	shopKey: string?, -- an Exclusive: its Exclusive shop card, opened while it is not on sale
}

PetSeatsView.EXCLUSIVE = "Exclusive"
PetSeatsView.EXCLUSIVE_LINE = "Buy it here or in the Exclusive shop."
PetSeatsView.EXCLUSIVE_ACTION = "Exclusive shop"
PetSeatsView.HOW_UNLOCK = "How to unlock"
PetSeatsView.HOW_GET = "How to get it"
PetSeatsView.FREE_LINE = "Every player has this cloud."
PetSeatsView.EMPTY = "Pet seats are not on this server."

local DEFAULT_COLOR = { 235, 240, 255 }

local function num(v: any): number
	return if type(v) == "number" and v == v then v else 0
end

local function stateOf(seat: any): State
	return if seat.equipped == true then "equipped" elseif seat.unlocked == true then "unlocked" else "locked"
end

-- How the seat unlocks, as one sentence.
local function lineOf(seat: any): string
	local need = num(seat.need)
	if seat.kind == "merges" then
		return `Merge {need} slimes.`
	elseif seat.kind == "dex" then
		return `Complete {need}% of the SlimeDex.`
	elseif seat.kind == "exclusive" then
		return PetSeatsView.EXCLUSIVE_LINE
	end
	return PetSeatsView.FREE_LINE
end

-- "136/200" or "52%/80%"; "" for seats without a bar.
local function countOf(seat: any): string
	local have, need = num(seat.have), num(seat.need)
	if seat.kind == "merges" then
		return `{math.min(have, need)}/{need}`
	elseif seat.kind == "dex" then
		return `{math.min(have, need)}%/{need}%`
	end
	return ""
end

local function fractionOf(seat: any, state: State): number
	local need = num(seat.need)
	if state ~= "locked" then
		return 1
	end
	return if need > 0 then math.clamp(num(seat.have) / need, 0, 1) else 0
end

local function titleOf(seat: any): string
	return Format.sentenceCase(if type(seat.name) == "string" then seat.name else seat.id)
end

local function offerOf(seat: any, config: any?): ExclusiveShopView.Offer?
	local key = if type(seat.productKey) == "string" then seat.productKey else `Seat_{seat.id}`
	return if config ~= nil then ExclusiveShopView.offer(config, key) else nil
end

-- One row per State.petSeats entry, in the server's order. Empty without the field.
function PetSeatsView.rows(petSeats: any, config: any): { Row }
	local out: { Row } = {}
	if type(petSeats) ~= "table" then
		return out
	end
	local colors: { [string]: { number } } = {}
	for _, def in config.PET_SEATS or {} do
		colors[def.id] = def.color
	end
	for _, seat in petSeats :: { any } do
		if type(seat) == "table" and type(seat.id) == "string" then
			local state: State = stateOf(seat)
			local locked = state == "locked"
			local exclusive = locked and seat.kind == "exclusive"
			local offer = if exclusive then offerOf(seat, config) else nil
			table.insert(out, {
				key = `seat:{seat.id}`,
				id = seat.id,
				title = titleOf(seat),
				state = state,
				exclusive = exclusive,
				line = if locked and not exclusive then lineOf(seat) else "",
				count = if locked then countOf(seat) else "",
				fraction = fractionOf(seat, state),
				color = colors[seat.id] or DEFAULT_COLOR,
				price = if offer then offer.price else "",
			})
		end
	end
	return out
end

-- The pane for seat `id`, or nil when State has no such seat. `config` (shared Config) prices an Exclusive.
function PetSeatsView.detail(petSeats: any, id: string, config: any?): Detail?
	if type(petSeats) ~= "table" then
		return nil
	end
	local seat: any = nil
	for _, s in petSeats :: { any } do
		if type(s) == "table" and s.id == id then
			seat = s
		end
	end
	if seat == nil then
		return nil
	end
	local state: State = stateOf(seat)
	local exclusive = seat.kind == "exclusive" and state == "locked"
	local count = countOf(seat)
	local left = math.max(num(seat.need) - num(seat.have), 0)
	local offer = if exclusive then offerOf(seat, config) else nil
	local action = if state == "equipped"
		then PlotSkinsView.EQUIPPED
		elseif state == "unlocked" then PlotSkinsView.EQUIP
		elseif offer and offer.purchase then offer.text
		elseif exclusive then PetSeatsView.EXCLUSIVE_ACTION
		elseif seat.kind == "merges" then `Merge {left} more slime{if left == 1 then "" else "s"}`
		elseif seat.kind == "dex" then `{left}% more of the SlimeDex`
		else PlotSkinsView.EQUIP
	return {
		id = id,
		title = titleOf(seat),
		state = state,
		exclusive = exclusive,
		heading = if seat.kind == "free" then "" elseif exclusive then PetSeatsView.HOW_GET else PetSeatsView.HOW_UNLOCK,
		line = lineOf(seat),
		count = if count ~= "" then count else nil,
		fraction = fractionOf(seat, state),
		action = action,
		purchase = if offer then offer.purchase else nil,
		shopKey = if exclusive then `seat:{id}` else nil,
	}
end

-- The seat to show first: the equipped one, else the first.
function PetSeatsView.firstSelected(rows: { Row }): string?
	for _, row in rows do
		if row.state == "equipped" then
			return row.id
		end
	end
	return if rows[1] then rows[1].id else nil
end

-- "3/19 unlocked"
function PetSeatsView.summary(rows: { Row }): string
	local n = 0
	for _, row in rows do
		if row.state ~= "locked" then
			n += 1
		end
	end
	return `{n}/{#rows} unlocked`
end

return table.freeze(PetSeatsView)
