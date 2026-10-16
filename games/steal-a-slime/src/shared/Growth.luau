--!strict
--[[
	Growth (pure, FEATURES.GrowingSlimes)

	A slime's optional `growth` (0..1) rises while it sits on a pad: dt /
	GROWTH_SECONDS online, and (now - lastOnline) / GROWTH_SECONDS offline,
	with the offline gap capped at GROWTH_OFFLINE_CAP_SECONDS. Growth raises
	income (Genome.baseIncome, so sell price too) by up to
	GROWTH_MAX_INCOME_BONUS and the drawn scale by up to GROWTH_MAX_SCALE_BONUS.
	Missing `growth` = 0, so old saves load unchanged (no SAVE_VERSION bump).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")

type Slime = Genome.Slime

local Growth = {}

function Growth.enabled(): boolean
	return Config.FEATURES.GrowingSlimes == true
end

-- Income multiplier at this growth (what Genome.baseIncome applies).
function Growth.incomeMultiplier(slime: Slime): number
	return 1 + Config.GROWTH_MAX_INCOME_BONUS * Genome.growthFraction(slime)
end

-- Model scale factor (1 = unchanged).
function Growth.scale(slime: Slime): number
	return 1 + Config.GROWTH_MAX_SCALE_BONUS * Genome.growthFraction(slime)
end

-- Whole percent 0..100 for the "Growth %" label.
function Growth.percent(slime: Slime): number
	return math.floor(Genome.growthFraction(slime) * 100 + 0.5)
end

-- Label text, or nil when there is nothing to show (feature off / not grown yet).
function Growth.label(slime: Slime): string?
	local percent = Growth.percent(slime)
	if percent <= 0 then
		return nil
	end
	return `Growth {percent}%`
end

-- Grows one slime by `seconds` of pad time. Returns true if it changed.
function Growth.advance(slime: Slime, seconds: number): boolean
	if not Growth.enabled() or seconds ~= seconds or seconds <= 0 then
		return false
	end
	local before = Genome.growthFraction(slime)
	if before >= 1 then
		return false
	end
	slime.growth = math.min(1, before + seconds / Config.GROWTH_SECONDS)
	return true
end

-- `skip` holds ids that don't grow (e.g. a slime a thief is carrying away).
function Growth.advanceAll(slimes: { Slime }, seconds: number, skip: { [string]: boolean }?)
	for _, slime in slimes do
		if not (skip and skip[slime.id]) then
			Growth.advance(slime, seconds)
		end
	end
end

--[[
	Growth earned while offline, once on load. Clock skew (now < lastOnline)
	and a missing lastOnline give nothing. Returns the seconds credited.
]]
function Growth.applyOffline(slimes: { Slime }, lastOnline: number, now: number, cap: number?): number
	if type(lastOnline) ~= "number" or lastOnline <= 0 or lastOnline ~= lastOnline then
		return 0
	end
	local elapsed = now - lastOnline
	if elapsed ~= elapsed or elapsed <= 0 then
		return 0
	end
	local seconds = math.min(elapsed, cap or Config.GROWTH_OFFLINE_CAP_SECONDS)
	Growth.advanceAll(slimes, seconds)
	return seconds
end

return Growth
