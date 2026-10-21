--!strict
--[[
	Spring: second-order dynamics for procedural motion (follow-through, overshoot, anticipation).

		local s = Spring.new(2.5, 0.35, 1.5, 0)   -- f (Hz), zeta (damping), r (response), start value
		local y = Spring.step(s, dt, target)      -- once per frame; returns the smoothed value
		Spring.kick(s, 4)                         -- add velocity (a landing, a nudge)

	The value y follows the target x through  y + k1 y' + k2 y'' = x + k3 x'  with
	k1 = zeta / (pi f), k2 = 1 / (2 pi f)^2, k3 = r zeta / (2 pi f):
	  f      how fast it responds (its natural frequency, Hz)
	  zeta   0 rings forever, 0..1 overshoots and wobbles out, >= 1 settles without overshoot
	  r      0 starts slowly, 1 responds at once, > 1 overshoots the start, < 0 moves the wrong way first
	The target's speed x' is measured from successive targets unless the caller passes it. Each step is
	stable for any dt (k2 is raised for long frames), and dt is capped at MAX_DT so a hitch can't fling it.
	Pure: no Roblox APIs, no allocation after `new`.
]]

export type Spring = {
	k1: number,
	k2: number,
	k3: number,
	y: number, -- current value
	v: number, -- current speed
	xp: number, -- last target (for its speed)
}

local Spring = {}

Spring.MAX_DT = 0.1 -- seconds: a longer frame steps as this long

local function constants(f: number, zeta: number, r: number): (number, number, number)
	local w = 2 * math.pi * math.max(f, 1e-3)
	return zeta / (math.pi * math.max(f, 1e-3)), 1 / (w * w), r * zeta / w
end

function Spring.new(f: number, zeta: number, r: number, x0: number?): Spring
	local k1, k2, k3 = constants(f, zeta, r)
	local x = x0 or 0
	return { k1 = k1, k2 = k2, k3 = k3, y = x, v = 0, xp = x }
end

-- New f / zeta / r; keeps the current value and speed.
function Spring.retune(s: Spring, f: number, zeta: number, r: number)
	s.k1, s.k2, s.k3 = constants(f, zeta, r)
end

-- Jumps to `x` at rest.
function Spring.reset(s: Spring, x: number)
	s.y, s.v, s.xp = x, 0, x
end

-- Adds `dv` to the speed (units per second).
function Spring.kick(s: Spring, dv: number)
	s.v += dv
end

-- Advances by `dt` seconds towards target `x` (speed `xd`, measured when nil). Returns the new value.
function Spring.step(s: Spring, dt: number, x: number, xd: number?): number
	if not (dt > 0) then
		return s.y
	end
	dt = math.min(dt, Spring.MAX_DT)
	local speed = if xd ~= nil then xd else (x - s.xp) / dt
	s.xp = x
	local k2 = math.max(s.k2, dt * dt / 2 + dt * s.k1 / 2, dt * s.k1)
	s.y += dt * s.v
	s.v += dt * (x + s.k3 * speed - s.y - s.k1 * s.v) / k2
	return s.y
end

return table.freeze(Spring)
