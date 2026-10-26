--!strict
--[[
	Economy

	Pure cash maths: per-slime income, plot income, fractional income ticks,
	capped offline income, wild / sell / pad / rebirth prices, the rebirth
	multiplier and number formatting. No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local NumberFormat = if script then require(script.Parent.NumberFormat) else require("./NumberFormat")
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

-- Income multiplier rebirth `n` adds (the band of Config.REBIRTH_MULTIPLIER_STEPS it falls in).
function Economy.rebirthStep(n: number): number
	local step = 0
	for _, band in Config.REBIRTH_MULTIPLIER_STEPS do
		if n >= band.from then
			step = band.step
		end
	end
	return step
end

function Economy.rebirthMultiplier(rebirths: number): number
	local mult = 1
	for n = 1, math.min(count(rebirths), Config.MAX_REBIRTHS) do
		mult += Economy.rebirthStep(n)
	end
	return mult
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

-- What the fountain charges for `slime`: its base income for WILD_PRICE_SECONDS of its rarity. The rebirth
-- multiplier doesn't count, so the fountain gets cheaper as a player rebirths.
function Economy.wildPrice(slime: Slime): number
	local seconds = Config.WILD_PRICE_SECONDS[math.clamp(slime.tier, 1, Config.MAX_TIER)]
	return math.max(1, math.floor(Genome.baseIncome(slime) * seconds))
end

-- Cash for selling a slime (SELL_PRICE_SHARE of its fountain price), or nil for a Mystery Egg: an egg can't be sold.
function Economy.sellPrice(slime: Slime): number?
	if slime.egg then
		return nil
	end
	return math.max(1, math.floor(Economy.wildPrice(slime) * Config.SELL_PRICE_SHARE))
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

-- Rebirths that open pad `pad` (Config.BASE_FLOORS rows); 0 for a pad there from the start.
function Economy.rebirthsForPad(pad: number): number
	local floor = Economy.floorOf(pad)
	local row = Config.BASE_FLOORS[floor]
	return if row then row.padRebirths[pad - (floor - 1) * Config.PADS_PER_FLOOR] or 0 else 0
end

-- Rebirths the next pad needs, or nil when every pad is unlocked.
function Economy.padRebirths(padsUnlocked: number): number?
	local owned = count(padsUnlocked)
	if owned >= Config.PADS_MAX then
		return nil
	end
	return Economy.rebirthsForPad(owned + 1)
end

--[[
	Price of the next pad, or nil when every pad is unlocked. A pad open from the start costs PAD_START_COSTS;
	a pad that rebirth R opens costs PAD_PRICE_SHARE of rebirth R + 1, and each further pad R opens costs
	PAD_SAME_REBIRTH_GROWTH times the one before it.
]]
function Economy.padCost(padsUnlocked: number): number?
	local owned = count(padsUnlocked)
	if owned >= Config.PADS_MAX then
		return nil
	end
	local nextPad = owned + 1
	local need = Economy.rebirthsForPad(nextPad)
	if need == 0 then
		return Config.PAD_START_COSTS[nextPad - Config.PADS_START] or 0
	end
	local before = 0
	for pad = 1, owned do
		if Economy.rebirthsForPad(pad) == need then
			before += 1
		end
	end
	return math.floor(Config.PAD_PRICE_SHARE * Economy.rebirthCost(need) * Config.PAD_SAME_REBIRTH_GROWTH ^ before)
end

-- Cash the next rebirth costs at `rebirths` rebirths (Config.REBIRTH_COSTS; the last price at max).
function Economy.rebirthCost(rebirths: number): number
	local costs = Config.REBIRTH_COSTS
	return costs[math.clamp(count(rebirths) + 1, 1, #costs)]
end

function Economy.formatNumber(n: number): string
	return NumberFormat.short(n)
end

return Economy
