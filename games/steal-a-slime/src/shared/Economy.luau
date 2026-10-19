--!strict
--[[
	Economy

	Pure cash maths: per-slime income, plot income, fractional income ticks,
	capped offline income, sell / pad / rebirth / lock prices and number
	formatting. No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local NumberFormat = if script then require(script.Parent.NumberFormat) else require("./NumberFormat")
local EggKind = if script then require(script.Parent.EggKind) else require("./EggKind")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")

type Slime = Genome.Slime

local Economy = {}

local function count(n: any): number
	local v = tonumber(n)
	if not v or v ~= v or v < 0 or v == math.huge then
		return 0
	end
	return math.floor(v)
end

function Economy.rebirthMultiplier(rebirths: number): number
	return 1 + count(rebirths) * Config.REBIRTH_MULTIPLIER_STEP
end

function Economy.slimeIncome(slime: Slime, rebirths: number): number
	return Genome.baseIncome(slime) * Economy.rebirthMultiplier(rebirths)
end

-- Cash/sec of every slime on the plot. `skip` holds ids that currently pay
-- nothing (e.g. a slime a thief is carrying away).
function Economy.plotIncome(slimes: { Slime }, rebirths: number, skip: { [string]: boolean }?): number
	local total = 0
	for _, slime in slimes do
		if not (skip and skip[slime.id]) then
			total += Economy.slimeIncome(slime, rebirths)
		end
	end
	return total
end

--[[
	Adds `incomePerSec * dt` to whole-number cash, keeping the fractional part
	in `remainder` so slow slimes still pay out over time.
	Returns (newCash, newRemainder, paid).
]]
function Economy.tickIncome(cash: number, remainder: number, incomePerSec: number, dt: number): (number, number, number)
	if incomePerSec <= 0 or dt <= 0 or dt ~= dt or incomePerSec ~= incomePerSec then
		return cash, remainder, 0
	end
	local total = remainder + incomePerSec * dt
	local whole = math.floor(total)
	return cash + whole, total - whole, whole
end

--[[
	Cash earned while offline: OFFLINE_RATE of income for at most
	OFFLINE_CAP_SECONDS. Clock skew (now < lastOnline) pays nothing.
	Returns (cash, creditedSeconds).
]]
function Economy.offlineIncome(
	incomePerSec: number,
	lastOnline: number,
	now: number,
	cap: number?,
	rate: number?
): (number, number)
	if type(lastOnline) ~= "number" or lastOnline <= 0 or lastOnline ~= lastOnline then
		return 0, 0
	end
	local elapsed = now - lastOnline
	if elapsed <= 0 or elapsed ~= elapsed or incomePerSec <= 0 then
		return 0, 0
	end
	local seconds = math.min(elapsed, cap or Config.OFFLINE_CAP_SECONDS)
	return math.floor(incomePerSec * seconds * (rate or Config.OFFLINE_RATE)), seconds
end

-- Cash for selling a slime; an egg sells for its kind's flat `sell` x the rebirth multiplier.
function Economy.sellPrice(slime: Slime, rebirths: number): number
	local kind = EggKind.of(slime)
	if kind then
		return math.max(1, math.floor(kind.sell * Economy.rebirthMultiplier(rebirths)))
	end
	return math.max(1, math.floor(Economy.slimeIncome(slime, rebirths) * Config.SELL_SECONDS))
end

-- The floor pad `pad` stands on: 1 for pads 1..PADS_PER_FLOOR, 2 for the next PADS_PER_FLOOR, and so on.
function Economy.floorOf(pad: number): number
	return math.max(1, math.ceil(pad / Config.PADS_PER_FLOOR))
end

-- How many floors a plot shows: every floor with an unlocked pad, plus the next one once the top one is full
-- (its pads locked, so the next pad can be bought there). Never more than #BASE_FLOORS.
function Economy.floorsShown(padsUnlocked: number): number
	return math.min(#Config.BASE_FLOORS, count(padsUnlocked) // Config.PADS_PER_FLOOR + 1)
end

-- Price of the next pad, or nil when every pad is unlocked (Config.BASE_FLOORS).
function Economy.padCost(padsUnlocked: number): number?
	local owned = count(padsUnlocked)
	if owned >= Config.PADS_MAX then
		return nil
	end
	local nextPad = owned + 1
	local floor = Economy.floorOf(nextPad)
	local row = Config.BASE_FLOORS[floor]
	local first = if floor == 1 then Config.PADS_START + 1 else (floor - 1) * Config.PADS_PER_FLOOR + 1
	return math.floor(row.firstPadCost * row.growth ^ math.max(0, nextPad - first))
end

-- x REBIRTH_COST_GROWTH per rebirth up to REBIRTH_LATE_FROM, then x REBIRTH_COST_GROWTH_LATE.
function Economy.rebirthCost(rebirths: number): number
	local r = count(rebirths)
	local early = math.min(r, Config.REBIRTH_LATE_FROM)
	local late = math.max(0, r - Config.REBIRTH_LATE_FROM)
	return math.floor(
		Config.REBIRTH_BASE_COST * Config.REBIRTH_COST_GROWTH ^ early * Config.REBIRTH_COST_GROWTH_LATE ^ late
	)
end

function Economy.lockCost(incomePerSec: number): number
	local income = if incomePerSec == incomePerSec and incomePerSec > 0 then incomePerSec else 0
	return math.max(Config.LOCK_BASE_COST, math.floor(income * Config.LOCK_INCOME_SECONDS))
end

function Economy.formatNumber(n: number): string
	return NumberFormat.short(n)
end

return Economy
