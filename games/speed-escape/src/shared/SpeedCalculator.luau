--!strict
--[[
	SpeedCalculator

	Pure functions for the speed / rebirth economy. No Roblox services are used,
	so this module runs unchanged in Studio and under Lune for unit tests.

	Every function takes an optional `config` table; omitted fields fall back to
	`SpeedCalculator.DEFAULT_CONFIG`.
]]

export type Config = {
	baseSpeed: number, -- WalkSpeed with 0 steps
	speedPerStep: number, -- speed gained per step before multipliers
	maxSpeed: number, -- hard cap on WalkSpeed
	rebirthBaseCost: number, -- steps required for the first rebirth
	rebirthCostGrowth: number, -- cost multiplier per rebirth already done
	rebirthMultiplierStep: number, -- extra step multiplier per rebirth
}

export type PartialConfig = {
	baseSpeed: number?,
	speedPerStep: number?,
	maxSpeed: number?,
	rebirthBaseCost: number?,
	rebirthCostGrowth: number?,
	rebirthMultiplierStep: number?,
}

local SpeedCalculator = {}

SpeedCalculator.DEFAULT_CONFIG = table.freeze({
	baseSpeed = 16,
	speedPerStep = 0.05,
	maxSpeed = 500,
	rebirthBaseCost = 1000,
	rebirthCostGrowth = 2.5,
	rebirthMultiplierStep = 0.5,
}) :: Config

local function resolve(config: PartialConfig?): Config
	local defaults = SpeedCalculator.DEFAULT_CONFIG
	if config == nil then
		return defaults
	end
	return {
		baseSpeed = config.baseSpeed or defaults.baseSpeed,
		speedPerStep = config.speedPerStep or defaults.speedPerStep,
		maxSpeed = config.maxSpeed or defaults.maxSpeed,
		rebirthBaseCost = config.rebirthBaseCost or defaults.rebirthBaseCost,
		rebirthCostGrowth = config.rebirthCostGrowth or defaults.rebirthCostGrowth,
		rebirthMultiplierStep = config.rebirthMultiplierStep or defaults.rebirthMultiplierStep,
	}
end

-- Coerces NaN, negatives and fractions into a non-negative whole number.
local function sanitizeCount(value: number): number
	if value ~= value or value < 0 then
		return 0
	end
	if value == math.huge then
		return value
	end
	return math.floor(value)
end

local function multiplierFor(rebirths: number, cfg: Config): number
	return 1 + sanitizeCount(rebirths) * cfg.rebirthMultiplierStep
end

--[[
	Step multiplier granted by rebirths: 1 + rebirths * rebirthMultiplierStep.
]]
function SpeedCalculator.getMultiplier(rebirths: number, config: PartialConfig?): number
	return multiplierFor(rebirths, resolve(config))
end

--[[
	WalkSpeed for a given step count and rebirth count, capped at maxSpeed.
]]
function SpeedCalculator.getSpeed(steps: number, rebirths: number?, config: PartialConfig?): number
	local cfg = resolve(config)
	local multiplier = multiplierFor(rebirths or 0, cfg)
	local speed = cfg.baseSpeed + sanitizeCount(steps) * cfg.speedPerStep * multiplier
	return math.min(speed, cfg.maxSpeed)
end

--[[
	Minimum whole number of steps needed to reach `targetSpeed`.
	Returns nil if the target is above maxSpeed (unreachable).
]]
function SpeedCalculator.getStepsForSpeed(targetSpeed: number, rebirths: number?, config: PartialConfig?): number?
	local cfg = resolve(config)
	if targetSpeed > cfg.maxSpeed then
		return nil
	end
	if targetSpeed <= cfg.baseSpeed then
		return 0
	end
	local perStep = cfg.speedPerStep * multiplierFor(rebirths or 0, cfg)
	if perStep <= 0 then
		return nil
	end
	return math.ceil((targetSpeed - cfg.baseSpeed) / perStep - 1e-9)
end

--[[
	Steps required to perform the next rebirth, given rebirths already done.
	cost = floor(rebirthBaseCost * rebirthCostGrowth ^ rebirths)
]]
function SpeedCalculator.getRebirthCost(rebirths: number, config: PartialConfig?): number
	local cfg = resolve(config)
	return math.floor(cfg.rebirthBaseCost * cfg.rebirthCostGrowth ^ sanitizeCount(rebirths))
end

function SpeedCalculator.canRebirth(steps: number, rebirths: number, config: PartialConfig?): boolean
	return sanitizeCount(steps) >= SpeedCalculator.getRebirthCost(rebirths, config)
end

--[[
	Rebirth progress in [0, 1], handy for progress bars.
]]
function SpeedCalculator.getRebirthProgress(steps: number, rebirths: number, config: PartialConfig?): number
	local cost = SpeedCalculator.getRebirthCost(rebirths, config)
	if cost <= 0 then
		return 1
	end
	return math.clamp(sanitizeCount(steps) / cost, 0, 1)
end

--[[
	Performs a rebirth: steps reset to 0 and rebirths increase by 1.
	Returns (success, newSteps, newRebirths); on failure the inputs are returned
	unchanged.
]]
function SpeedCalculator.applyRebirth(
	steps: number,
	rebirths: number,
	config: PartialConfig?
): (boolean, number, number)
	if not SpeedCalculator.canRebirth(steps, rebirths, config) then
		return false, steps, rebirths
	end
	return true, 0, sanitizeCount(rebirths) + 1
end

--[[
	Converts distance travelled (studs) into steps, using `studsPerStep`.
]]
function SpeedCalculator.stepsFromDistance(distance: number, studsPerStep: number): number
	if studsPerStep <= 0 then
		return 0
	end
	return sanitizeCount(distance / studsPerStep)
end

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

--[[
	Short human-readable number: 999 -> "999", 1500 -> "1.5K", 2_000_000 -> "2M".
]]
function SpeedCalculator.formatNumber(value: number): string
	if value ~= value then
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	local index = 1
	while n >= 1000 and index < #SUFFIXES do
		n /= 1000
		index += 1
	end
	if index == 1 then
		return sign .. tostring(math.floor(n))
	end
	local rounded = math.floor(n * 10) / 10
	local text = if rounded == math.floor(rounded) then string.format("%d", rounded) else string.format("%.1f", rounded)
	return sign .. text .. SUFFIXES[index]
end

return SpeedCalculator
