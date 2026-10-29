--!strict
--[[
	EggGlow (pure)

	The brightness of a Mystery Egg's glow on its pad (EggFx), from its incubation progress 0..1 and a clock `t`
	in seconds. While it incubates the glow breathes gently round a base that grows with the progress, a little
	quicker near the hatch, and never goes dark: the light falls on the nest and floor, and a full on/off swing
	there reads as a flicker. Ready: a brighter, slower breathe.
	No Roblox APIs; numbers only.
]]

local EggGlow = {}

EggGlow.MIN_RATE = 0.3 -- breaths per second at the start of incubation
EggGlow.MAX_RATE = 1.2 -- breaths per second right before the hatch
EggGlow.DEPTH = 0.3 -- share of the base the breathe takes away at its lowest
EggGlow.READY_BASE = 2.5
EggGlow.READY_SWING = 1.2
EggGlow.READY_SPEED = 6 -- radians per second

-- Breaths per second at a progress 0..1: slow at the start, quicker near the hatch.
function EggGlow.pulseRate(progress: number): number
	return EggGlow.MIN_RATE + (EggGlow.MAX_RATE - EggGlow.MIN_RATE) * math.clamp(progress, 0, 1) ^ 2
end

-- Glow at its brightest for a progress 0..1 while incubating.
function EggGlow.base(progress: number): number
	return 0.3 + 1.4 * math.clamp(progress, 0, 1)
end

-- Brightness at time `t` for an incubating egg at `progress` 0..1.
function EggGlow.incubating(progress: number, t: number): number
	local wave = 0.5 + 0.5 * math.sin(t * math.pi * 2 * EggGlow.pulseRate(progress))
	return EggGlow.base(progress) * (1 - EggGlow.DEPTH * (1 - wave))
end

-- Brightness at time `t` for a ready egg.
function EggGlow.ready(t: number): number
	return EggGlow.READY_BASE + EggGlow.READY_SWING * math.sin(t * EggGlow.READY_SPEED)
end

return table.freeze(EggGlow)
