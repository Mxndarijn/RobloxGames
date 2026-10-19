--!strict
--[[
	CycleModifier (pure, FEATURES.CycleModifier)

	A server modifier rolled at each dawn and dusk of the DayNight cycle
	(competitor-gaps.md #1). The roll is a pure function of (seed, phase), so it
	never draws from the world's spawn Rng. `luck` is a multiplier
	for the Fountain's rarity weights; "None" is 1.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local DayNight = if script then require(script.Parent.DayNight) else require("./DayNight")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

export type Modifier = { name: string, label: string, weight: number, luck: number }

local CycleModifier = {}

CycleModifier.NONE = Config.MODIFIERS[1]

-- Weighted pick: `roll` in [0, 1) over Config.MODIFIERS weights.
function CycleModifier.pick(roll: number, list: { Modifier }?): Modifier
	local mods = list or Config.MODIFIERS
	local total = 0
	for _, m in mods do
		total += m.weight
	end
	local at = roll * total
	for _, m in mods do
		at -= m.weight
		if at < 0 then
			return m
		end
	end
	return mods[#mods]
end

-- The modifier of phase `phase` (DayNight.phase) on a server with `seed`.
function CycleModifier.forPhase(seed: number, phase: number): Modifier
	local rng = Rng.new(seed * 7919 + phase * 104729 + 13)
	rng:float() -- the first draws of a Park-Miller LCG are correlated with nearby seeds
	rng:float()
	return CycleModifier.pick(rng:float())
end

-- Modifier at `elapsed` seconds since server start: (modifier, phase, seconds left in the phase).
function CycleModifier.at(seed: number, elapsed: number): (Modifier, number, number)
	local phase, left = DayNight.phase(elapsed)
	return CycleModifier.forPhase(seed, phase), phase, left
end

-- Luck multiplier for the active modifier; 1 when the feature is off.
function CycleModifier.multiplier(modifier: Modifier?): number
	if modifier == nil or not Config.FEATURES.CycleModifier then
		return 1
	end
	return modifier.luck
end

return table.freeze(CycleModifier)
