--!strict
--[[
	CashFlyLogic (pure): what the cash fly-in shows (ui/CashFly draws it).

	  CashFlyLogic.new() -> Model
	  CashFlyLogic.observe(model, input, now) -> Event?   a new State: the cash change it makes, if any
	  CashFlyLogic.land(model, flightId, now)              one coin of a flight reached the money plate
	  CashFlyLogic.tick(model, now) -> boolean             rows that ran out, the auto collect sum; true when rows changed
	  CashFlyLogic.shownCash(model) -> number              the number the money plate shows right now
	  CashFlyLogic.counting(model) -> boolean              coins are still to land
	  CashFlyLogic.coinCount(amount) -> number
	  CashFlyLogic.flightSeconds(coins) -> number
	  CashFlyLogic.rowText(row, formatCash) -> string      "+$1.2K" / "-$2.5K"

	Earned cash flies in as coins (a "flight"); the money plate counts up as each coin lands, and the "+" row shows
	when the first one lands. Spent cash shows a "-" row at once. The rows stack above the number: at most
	TUNING.ROWS, newest last, each gone TUNING.ROW_SECONDS after its last change. A change of the same sign within
	TUNING.JOIN_SECONDS of the newest row adds to it. At most TUNING.FLIGHTS fly at once; past that, or with reduced
	motion, earned cash shows its row at once with no coins. With Auto Collect, the steady income ticks are summed
	into one row every TUNING.AUTO_SECONDS. The first State and a rebirth (cash reset) show nothing.
]]

local CashFlyLogic = {}

CashFlyLogic.TUNING = table.freeze({
	ROWS = 3, -- amounts above the number at once
	ROW_SECONDS = 2, -- how long an amount stays after its last change
	JOIN_SECONDS = 1, -- a same-sign change this soon after the newest row adds to it
	FLIGHTS = 3, -- coin flights at once
	COINS_MIN = 5,
	COINS_MAX = 10,
	POP_SECONDS = 0.16, -- coins burst out of the source
	FLY_SECONDS = 0.72, -- then curve to the plate
	COIN_GAP_SECONDS = 0.045, -- between coins of one flight
	AUTO_SECONDS = 5, -- Auto Collect income shows as one summed row this often
	PASSIVE_SECONDS = 4, -- with Auto Collect, a rise up to this many seconds of income is the steady tick
	SPEND_COINS = 4, -- coins that spill out of the plate on a purchase
})
local T = CashFlyLogic.TUNING

export type Row = { id: number, sign: number, amount: number, at: number }
export type Flight = { id: number, amount: number, coins: number, landed: number, pending: number, startedAt: number }
export type Model = {
	cash: number?, -- the last State's cash; nil before the first State
	rebirths: number?,
	rows: { Row }, -- oldest first
	flights: { [number]: Flight },
	nextId: number,
	autoSum: number,
	autoAt: number?, -- when the auto collect sum started
}
export type Input = {
	cash: number,
	rebirths: number?,
	incomePerSec: number?,
	autoCollect: boolean?, -- the Auto Collect pass: income goes straight to cash
	reducedMotion: boolean?,
}
export type Event =
	{ kind: "flight", id: number, amount: number, coins: number }
	| { kind: "spend", amount: number, coins: number }

local function finite(value: any): number?
	return if type(value) == "number" and value == value and math.abs(value) ~= math.huge then value else nil
end

function CashFlyLogic.new(): Model
	return { cash = nil, rebirths = nil, rows = {}, flights = {}, nextId = 1, autoSum = 0, autoAt = nil }
end

local function newId(model: Model): number
	local id = model.nextId
	model.nextId += 1
	return id
end

-- Adds a signed amount to the stack: joins a fresh same-sign newest row, else a new row (dropping the oldest).
local function pushRow(model: Model, amount: number, now: number)
	if amount == 0 then
		return
	end
	local sign = if amount > 0 then 1 else -1
	local newest = model.rows[#model.rows]
	if newest and newest.sign == sign and now - newest.at < T.JOIN_SECONDS then
		newest.amount += math.abs(amount)
		newest.at = now
		return
	end
	table.insert(model.rows, { id = newId(model), sign = sign, amount = math.abs(amount), at = now })
	while #model.rows > T.ROWS do
		table.remove(model.rows, 1)
	end
end

local function flightCount(model: Model): number
	local n = 0
	for _ in model.flights do
		n += 1
	end
	return n
end

function CashFlyLogic.coinCount(amount: number): number
	local digits = math.log10(math.max(10, amount))
	return math.clamp(math.floor(3 + digits), T.COINS_MIN, T.COINS_MAX)
end

-- Seconds a flight of `coins` coins takes from start to the last landing.
function CashFlyLogic.flightSeconds(coins: number): number
	return T.POP_SECONDS + T.FLY_SECONDS + math.max(0, coins - 1) * T.COIN_GAP_SECONDS
end

function CashFlyLogic.observe(model: Model, input: Input, now: number): Event?
	local cash = finite(input.cash)
	if cash == nil then
		return nil
	end
	local rebirths = finite(input.rebirths) or 0
	local before, beforeRebirths = model.cash, model.rebirths
	model.cash = cash
	model.rebirths = rebirths
	if before == nil or (beforeRebirths ~= nil and rebirths > beforeRebirths) then
		-- First State or a rebirth: no amount; anything still flying lands on the new number.
		table.clear(model.flights)
		model.autoSum = 0
		model.autoAt = nil
		return nil
	end
	local delta = cash - before
	if delta == 0 then
		return nil
	end
	if delta < 0 then
		pushRow(model, delta, now)
		return { kind = "spend", amount = -delta, coins = T.SPEND_COINS }
	end
	local income = finite(input.incomePerSec) or 0
	if input.autoCollect == true and income > 0 and delta <= income * T.PASSIVE_SECONDS + 0.5 then
		model.autoSum += delta
		if model.autoAt == nil then
			model.autoAt = now
		end
		return nil
	end
	if input.reducedMotion == true or flightCount(model) >= T.FLIGHTS then
		pushRow(model, delta, now)
		return nil
	end
	local coins = CashFlyLogic.coinCount(delta)
	local id = newId(model)
	model.flights[id] = { id = id, amount = delta, coins = coins, landed = 0, pending = delta, startedAt = now }
	return { kind = "flight", id = id, amount = delta, coins = coins }
end

-- One coin landed: credits its share to the shown number; the first landing shows the "+" row.
function CashFlyLogic.land(model: Model, id: number, now: number)
	local flight = model.flights[id]
	if flight == nil then
		return
	end
	flight.landed += 1
	if flight.landed == 1 then
		pushRow(model, flight.amount, now)
	end
	local left = flight.coins - flight.landed
	if left <= 0 then
		model.flights[id] = nil
	else
		flight.pending -= math.floor(flight.pending / (left + 1))
	end
end

function CashFlyLogic.tick(model: Model, now: number): boolean
	local changed = false
	-- A flight whose coins never all landed (the view lost them) settles a moment after it should have.
	for id, flight in model.flights do
		if now - flight.startedAt > CashFlyLogic.flightSeconds(flight.coins) + 1 then
			if flight.landed == 0 then
				pushRow(model, flight.amount, now)
			end
			model.flights[id] = nil
			changed = true
		end
	end
	if model.autoAt ~= nil and now - model.autoAt >= T.AUTO_SECONDS then
		if model.autoSum > 0 then
			pushRow(model, model.autoSum, now)
			changed = true
		end
		model.autoSum = 0
		model.autoAt = nil
	end
	for i = #model.rows, 1, -1 do
		if now - model.rows[i].at >= T.ROW_SECONDS then
			table.remove(model.rows, i)
			changed = true
		end
	end
	return changed
end

function CashFlyLogic.shownCash(model: Model): number
	local shown = model.cash or 0
	for _, flight in model.flights do
		shown -= flight.pending
	end
	return math.max(0, shown) -- spending more than is still landing never shows a negative number
end

-- True while coins are still to land (the plate shows a number below the real cash).
function CashFlyLogic.counting(model: Model): boolean
	return next(model.flights) ~= nil
end

function CashFlyLogic.rowText(row: Row, formatCash: (number) -> string): string
	return (if row.sign > 0 then "+" else "-") .. formatCash(row.amount)
end

return CashFlyLogic
