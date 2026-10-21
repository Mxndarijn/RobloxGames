--!strict
--[[
	StepTrack: draws a value that arrives in steps (a replicated position, updated 20-30 times a second) smoothly at
	frame rate.

		local t = StepTrack.new(x, y, z, now)
		local sx, sy, sz = StepTrack.step(t, x, y, z, now)   -- every frame, with the latest stepwise value
		local yaw = StepTrack.angle(yaw, targetYaw, dt)      -- the same idea for a heading (radians)

	Each time the input changes, the speed is measured over the time since its last change and blended into the
	estimate (BLEND). The aim is the last input plus that speed times the time since, extrapolated at most LEAD
	input intervals, so a walk at a steady pace draws as a steady glide, and a stop holds instead of overshooting
	far. The drawn value follows the aim with a short first-order filter (FOLLOW per second). No input change for
	STILL seconds = standing (the speed drops to 0). A jump of SNAP or more is a teleport: drawn there at once.
	Pure: no Roblox APIs, no allocation after `new`.
]]

export type Track = {
	x: number, -- last input
	y: number,
	z: number,
	at: number, -- when the input last changed
	gap: number, -- seconds between the last two input changes
	vx: number, -- speed estimate
	vy: number,
	vz: number,
	ox: number, -- drawn value
	oy: number,
	oz: number,
	t: number, -- last step time
}

local StepTrack = {}

StepTrack.LEAD = 1.5 -- input intervals the aim may run ahead of the last input
StepTrack.BLEND = 0.6 -- share of a new speed measurement taken at once
StepTrack.FOLLOW = 20 -- 1 / s: the drawn value closes on the aim this fast
StepTrack.STILL = 0.35 -- seconds without an input change before it counts as standing
StepTrack.SNAP = 8 -- a jump this big (units) is a teleport
StepTrack.MAX_GAP = 0.25 -- seconds: a longer gap between inputs measures speed over this at most
StepTrack.TURN = 14 -- 1 / s: StepTrack.angle closes on its target this fast
StepTrack.TURN_SNAP = 2 -- radians: a heading jump this big is taken at once

function StepTrack.new(x: number, y: number, z: number, now: number): Track
	return { x = x, y = y, z = z, at = now, gap = 1 / 30, vx = 0, vy = 0, vz = 0, ox = x, oy = y, oz = z, t = now }
end

-- Jumps to (x, y, z) at rest.
function StepTrack.reset(t: Track, x: number, y: number, z: number, now: number)
	t.x, t.y, t.z, t.at, t.t = x, y, z, now, now
	t.vx, t.vy, t.vz = 0, 0, 0
	t.ox, t.oy, t.oz = x, y, z
end

-- Feeds this frame's input; returns the drawn value and the speed estimate.
function StepTrack.step(
	t: Track,
	x: number,
	y: number,
	z: number,
	now: number
): (number, number, number, number, number, number)
	local dx, dy, dz = x - t.x, y - t.y, z - t.z
	local moved = dx * dx + dy * dy + dz * dz
	if moved >= StepTrack.SNAP * StepTrack.SNAP then
		StepTrack.reset(t, x, y, z, now)
		return x, y, z, 0, 0, 0
	end
	if moved > 1e-10 then
		local gap = math.clamp(now - t.at, 1 / 240, StepTrack.MAX_GAP)
		local k = StepTrack.BLEND
		t.vx += (dx / gap - t.vx) * k
		t.vy += (dy / gap - t.vy) * k
		t.vz += (dz / gap - t.vz) * k
		t.x, t.y, t.z, t.at, t.gap = x, y, z, now, gap
	elseif now - t.at > StepTrack.STILL then
		t.vx, t.vy, t.vz = 0, 0, 0
	end
	local ahead = math.min(now - t.at, StepTrack.LEAD * t.gap)
	local ax, ay, az = t.x + t.vx * ahead, t.y + t.vy * ahead, t.z + t.vz * ahead
	local dt = math.max(now - t.t, 0)
	t.t = now
	local f = 1 - math.exp(-dt * StepTrack.FOLLOW)
	t.ox += (ax - t.ox) * f
	t.oy += (ay - t.oy) * f
	t.oz += (az - t.oz) * f
	return t.ox, t.oy, t.oz, t.vx, t.vy, t.vz
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- A heading `current` turned towards `target` the shortest way round over `dt` seconds (radians).
function StepTrack.angle(current: number, target: number, dt: number): number
	local d = wrap(target - current)
	if math.abs(d) >= StepTrack.TURN_SNAP then
		return wrap(target)
	end
	return wrap(current + d * (1 - math.exp(-math.max(dt, 0) * StepTrack.TURN)))
end

return table.freeze(StepTrack)
