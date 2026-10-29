--!strict
--[[
	CashPads (pure, FEATURES.CashPads, contract/cash-pads.md)

	With the flag on, a slime's income piles up on its pad instead of going straight to cash. `data.padCash`
	maps a pad index to its pile (fractional cash). A pile belongs to the pad, not the slime: it stays when the
	slime is stolen, sold, merged or moved, and only the plot owner collects it (whole cash; the fraction stays).
	A pad has no cap: it keeps filling while the player is online. Offline income goes onto the pads too, for at
	most the offline cap time (Economy.offlineIncome, Perks.offlineCap: Night Shift raises it). Rebirth leaves every
	pile where it is. `floorLook` and `face` describe the coin the view draws on each pad.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local Perks = if script then require(script.Parent.Perks) else require("./Perks")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Data = PlayerData.Data

local CashPads = {}

local MAX_PILE = 1e15 -- sanity clamp on a saved pile, matches the save's cash clamp scale

-- The flag, with an optional test override table (`{ CashPads = true }`).
function CashPads.enabled(features: { [string]: any }?): boolean
	if features and features.CashPads ~= nil then
		return features.CashPads == true
	end
	return Config.FEATURES.CashPads == true
end

local function piles(data: Data): { [number]: number }
	local map = data.padCash
	if map then
		return map
	end
	local fresh: { [number]: number } = {}
	data.padCash = fresh
	return fresh
end

-- The pile on `pad` (0 when empty).
function CashPads.pile(data: Data, pad: number): number
	return if data.padCash then data.padCash[pad] or 0 else 0
end

-- Sum of every pile.
function CashPads.total(data: Data): number
	local sum = 0
	local map = data.padCash
	if map then
		for _, amount in map do
			sum += amount
		end
	end
	return sum
end

-- Adds `amount` to `pad`'s pile. Returns what was added.
function CashPads.add(data: Data, pad: number, amount: number): number
	if amount <= 0 or amount ~= amount then
		return 0
	end
	local map = piles(data)
	map[pad] = math.min((map[pad] or 0) + amount, MAX_PILE)
	return amount
end

-- Fills every pad from its slime for `seconds` of online income. `skip` holds slime ids that earn nothing now
-- (carried away, brewing). Returns the total added.
function CashPads.accrue(data: Data, seconds: number, skip: { [string]: boolean }?): number
	if seconds <= 0 or seconds ~= seconds then
		return 0
	end
	local added = 0
	for _, slime in data.slimes do
		local pad = slime.pad
		if pad and not (skip and skip[slime.id]) then
			local perSec = PlayerData.slimeIncome(data, slime)
			if perSec > 0 then
				added += CashPads.add(data, pad, perSec * seconds)
			end
		end
	end
	return added
end

-- Offline income (Economy.offlineIncome per slime: `rate`, default OFFLINE_RATE, for at most the offline cap time)
-- onto the pads.
-- Returns the total added.
function CashPads.accrueOffline(
	data: Data,
	lastOnline: number,
	now: number,
	skip: { [string]: boolean }?,
	rate: number?
): number
	local capSeconds = Perks.offlineCap(data)
	local added = 0
	for _, slime in data.slimes do
		local pad = slime.pad
		if pad and not (skip and skip[slime.id]) then
			local perSec = PlayerData.slimeIncome(data, slime)
			local amount = Economy.offlineIncome(perSec, lastOnline, now, capSeconds, rate)
			if amount > 0 then
				added += CashPads.add(data, pad, amount)
			end
		end
	end
	return added
end

export type FloorLook = { diameter: number, front: number, lift: number }

-- The coin on pad `pad`: its diameter, studs from the pad's centre to the coin's centre (towards the jar), and how
-- far its bottom sits above the pad's bottom (where that floor's walk surface is). Config.CASH_PAD per floor; the last
-- entry covers any floor above.
function CashPads.floorLook(pad: number): FloorLook
	local c = Config.CASH_PAD
	local floor = math.max(1, math.ceil(pad / Config.PADS_PER_FLOOR))
	local function at(list: { number }): number
		return list[math.min(floor, #list)]
	end
	return { diameter = at(c.DIAMETER), front = at(c.FRONT), lift = at(c.LIFT) }
end

-- Is a player's root at (dx, dy, dz) from the centre of a coin `diameter` across standing on it (Config.CASH_PAD)?
function CashPads.touching(dx: number, dy: number, dz: number, diameter: number): boolean
	local c = Config.CASH_PAD
	local reach = diameter / 2 + c.TOUCH_SLACK
	return dx * dx + dz * dz <= reach * reach and dy >= 0 and dy <= c.TOUCH_HEIGHT
end

export type Face = { state: "empty" | "waiting" | "collected", amount: string, collect: boolean }

-- What the coin shows: "$0" (empty, dimmed, no COLLECT) while less than $1 waits, the amount plus COLLECT while cash
-- waits, and "+$X" for a moment after the owner collected `paid` (`flashing`).
function CashPads.face(pile: number, flashing: boolean, paid: number?): Face
	if flashing and paid and paid >= 1 then
		return { state = "collected", amount = `+${Economy.formatNumber(math.floor(paid))}`, collect = false }
	end
	if pile < 1 then
		return { state = "empty", amount = "$0", collect = false }
	end
	return { state = "waiting", amount = `${Economy.formatNumber(math.floor(pile))}`, collect = true }
end

-- Moves the whole cash of `pad`'s pile into the player's cash (PlayerData.earn); the fraction stays. Returns what was paid.
function CashPads.collect(data: Data, pad: number): number
	local pile = CashPads.pile(data, pad)
	local paid = math.floor(pile)
	if paid <= 0 then
		return 0
	end
	local rest = pile - paid
	local map = piles(data)
	if rest > 0 then
		map[pad] = rest
	else
		map[pad] = nil
	end
	PlayerData.earn(data, paid)
	return paid
end

-- Saved form: a dense list, entry i = pad i's pile (0 = empty); nil when nothing is piled up.
function CashPads.serialize(data: Data): { number }?
	local map = data.padCash
	if not map then
		return nil
	end
	local last = 0
	for pad, amount in map do
		if amount > 0 and pad > last then
			last = pad
		end
	end
	if last == 0 then
		return nil
	end
	local list = table.create(last, 0)
	for pad = 1, last do
		local amount = map[pad] or 0
		list[pad] = if amount == amount and amount > 0 then math.min(amount, MAX_PILE) else 0
	end
	return list
end

-- Loads a saved list. Junk, negative, NaN entries and pads past `padsUnlocked` are dropped; missing -> nil.
function CashPads.clean(raw: any, padsUnlocked: number): { [number]: number }?
	if type(raw) ~= "table" then
		return nil
	end
	local map: { [number]: number } = {}
	local any = false
	for pad = 1, math.min(#raw, padsUnlocked, Config.PADS_MAX) do
		local amount = raw[pad]
		if type(amount) == "number" and amount == amount and amount > 0 then
			map[pad] = math.min(amount, MAX_PILE)
			any = true
		end
	end
	return if any then map else nil
end

return CashPads
