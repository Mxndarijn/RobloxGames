--!strict
--[[
	PetSeats

	What the follow pet rides on (Config.PET_SEATS, contract/pet-seats.md). A seat unlocks by its `unlock` rule:
	"free" always, "merges" once stats.merges reaches `count`, "dex" once `percent` of the SlimeDex is found
	(SpeciesDex.count over SpeciesDex.TOTAL), "exclusive" once bought in the Exclusive Shop (`data.ownedSeats`,
	contract/exclusive-shop.md); an unowned Exclusive's view row names its product key (`Seat_<id>`). The equipped
	seat is data.petSeat; `equip` refuses a locked seat and `current` never returns one.
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local SpeciesDex = if script then require(script.Parent.SpeciesDex) else require("./SpeciesDex")

type Data = PlayerData.Data
type Seat = Config.PetSeat

export type Kind = "free" | "merges" | "dex" | "exclusive"

export type View = {
	id: string,
	name: string,
	kind: Kind,
	have: number, -- progress toward `need`: merges, or SlimeDex percent (whole numbers)
	need: number, -- 0 for free and exclusive seats
	unlocked: boolean,
	equipped: boolean,
	productKey: string?, -- an unowned Exclusive seat: its Config.EXCLUSIVE_SHOP.products key ("Seat_<id>"); nil otherwise
}

local PetSeats = {}

PetSeats.DEFAULT = Config.PET_SEAT_DEFAULT

function PetSeats.get(id: any): Seat?
	if type(id) ~= "string" then
		return nil
	end
	for _, seat in Config.PET_SEATS do
		if seat.id == id then
			return seat
		end
	end
	return nil
end

-- Whole SlimeDex percent found (rounded down), 0..100.
function PetSeats.dexPercent(data: Data): number
	return math.floor(SpeciesDex.count(data) * 100 / SpeciesDex.TOTAL)
end

-- Progress toward the seat's unlock: (have, need). Free and exclusive seats need nothing to show: (0, 0).
function PetSeats.progress(data: Data, seat: Seat): (number, number)
	local rule = seat.unlock
	if rule.kind == "merges" then
		return data.stats.merges, rule.count or 0
	elseif rule.kind == "dex" then
		return PetSeats.dexPercent(data), rule.percent or 0
	end
	return 0, 0
end

function PetSeats.unlocked(data: Data, seat: Seat): boolean
	local kind = seat.unlock.kind
	if kind == "free" then
		return true
	elseif kind == "merges" then
		return data.stats.merges >= (seat.unlock.count or 0)
	elseif kind == "dex" then
		-- Exact: 40 of 50 found is 80 %, without rounding.
		return SpeciesDex.count(data) * 100 >= (seat.unlock.percent or 0) * SpeciesDex.TOTAL
	elseif kind == "exclusive" then
		local owned = (data :: any).ownedSeats
		return type(owned) == "table" and table.find(owned, seat.id) ~= nil
	end
	return false
end

-- The seat the pet rides: the equipped one if it exists and is unlocked, else the default cloud.
function PetSeats.current(data: Data): string
	local seat = PetSeats.get(data.petSeat)
	if seat and PetSeats.unlocked(data, seat) then
		return seat.id
	end
	return PetSeats.DEFAULT
end

function PetSeats.equip(data: Data, id: any): (boolean, string?)
	local seat = PetSeats.get(id)
	if not seat then
		return false, "unknown pet seat"
	end
	if not PetSeats.unlocked(data, seat) then
		return false, "pet seat is locked"
	end
	data.petSeat = seat.id
	return true, nil
end

-- State.petSeats: every seat in Config order.
function PetSeats.view(data: Data): { View }
	local equipped = PetSeats.current(data)
	local out: { View } = {}
	for _, seat in Config.PET_SEATS do
		local have, need = PetSeats.progress(data, seat)
		local unlocked = PetSeats.unlocked(data, seat)
		table.insert(out, {
			id = seat.id,
			name = seat.name,
			kind = seat.unlock.kind,
			have = have,
			need = need,
			unlocked = unlocked,
			equipped = seat.id == equipped,
			productKey = if seat.unlock.kind == "exclusive" and not unlocked then `Seat_{seat.id}` else nil,
		})
	end
	return out
end

return table.freeze(PetSeats)
