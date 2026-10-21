--!strict
--[[
	CarryWriggle (pure, contract/slime-life.md "Alive motion")

	How a carried slime struggles: bursts of a wide, fast wriggle (it fights to get free) with rests between them
	(it sways slowly and looks round, catching its breath). Constant shaking reads as noise; bursts read as effort.
	Each cycle draws its own burst length from a hash of the cycle number and the slime's seed, so two carried
	slimes never struggle in step and nothing needs to be stored.

	  CarryWriggle.pose(t, seed) -> (pitch, yaw, roll, lift)   radians and studs, for the carry joint's C1
]]

local CarryWriggle = {}

CarryWriggle.PERIOD = 2.1 -- seconds: one burst plus one rest, on average
CarryWriggle.BURST = table.freeze({ 0.35, 0.6 }) -- share of the period spent struggling
CarryWriggle.HZ = 4.5 -- wriggle rate inside a burst
CarryWriggle.EASE = 0.12 -- seconds to ramp a burst in and out

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- 0..1 from two integers (a cheap integer hash; deterministic everywhere).
local function hash(a: number, b: number): number
	local h = (a * 374761393 + b * 668265263) % 2147483647
	h = (h * 1274126177 + 12345) % 2147483647
	return (h % 10007) / 10007
end

-- Struggle share 0..1 at time t (0 = resting, 1 = in a burst).
function CarryWriggle.effort(t: number, seed: number): number
	local P = CarryWriggle.PERIOD
	local phase = hash(seed, 7) * P
	local s = t + phase
	local cycle = math.floor(s / P)
	local u = s - cycle * P
	local B = CarryWriggle.BURST
	local burst = P * (B[1] + (B[2] - B[1]) * hash(seed, cycle))
	local e = CarryWriggle.EASE
	return smooth(u / e) * smooth((burst - u) / e)
end

function CarryWriggle.pose(t: number, seed: number): (number, number, number, number)
	local k = CarryWriggle.effort(t, seed)
	local w = 2 * math.pi * CarryWriggle.HZ * t
	-- burst: wide roll and twist, a kick up on each beat
	local bp = 0.16 * math.sin(w)
	local by = 0.32 * math.sin(w * 0.5 + 0.7)
	local br = 0.34 * math.sin(w + 1.3)
	local bl = 0.18 * math.abs(math.sin(w))
	-- rest: slow sway and a look round
	local rp = 0.05 * math.sin(t * 2.1 + seed)
	local ry = 0.55 * math.sin(t * 1.6 + seed * 0.37)
	local rr = 0.09 * math.sin(t * 5.0 + seed * 1.3)
	return rp + (bp - rp) * k, ry + (by - ry) * k, rr + (br - rr) * k, bl * k
end

return table.freeze(CarryWriggle)
