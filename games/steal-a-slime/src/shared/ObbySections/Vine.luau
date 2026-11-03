--!strict
--[[
	Vine (pure, contract/obby-sections.md §7 "vine")

	The rope swing's physics, shared by the client controller (visuals/client/ObbyMoves) and the checks
	(tests/ObbyCheck, tests/obby/VineSwing.spec), so the game and the checks agree on every grab and release.

	A rope hangs from a fixed pivot `arm` studs above its knob's centre and swings in one plane: along the course
	(motion `swing`, axis "x") or across it (axis "z"). Angles are radians, positive towards the plane's `s`
	direction (+x for an along rope, -z for an across one, as Kit.offsetAt's swing). Positions are in the plane:
	`s` along it from the pivot, `y` up from the pivot.

	  idle     a rope nobody holds swings on server time (Kit's swing: `amp` degrees, `period` = Vine.period(arm))
	  grab     the knob within `reach` of your body (feet to head) grabs you, jumping or walking in: the rope swings
	           to your angle and you keep CARRY of your speed along the swing (plus ROPE of the rope's own)
	  swing    a real pendulum (gravity G, your root `length` studs under the pivot). Holding the stick along the
	           swing pumps it (PUMP studs/s², the way it swings) up to AMP_MAX; let go and it fades slowly (DRAG)
	  release  a fresh jump press after GRACE: you fly off with the swing's speed along its arc plus UP
]]

local Vine = {}

Vine.G = 110 -- studs/s² the rope swings under: lighter than the world's 196.2 so a swing reads (about 2 s)
Vine.GRIP = 3.3 -- studs from the knob's centre (your hands) down to your root, standing straight
Vine.TILT = 0.4 -- share of the rope's angle your body leans with it
Vine.FEET = 3 -- studs from the root down to the feet
Vine.HEAD = 2 -- studs from the root up to the top of the head
Vine.PUMP = 26 -- studs/s² the way you swing while you hold the stick along the swing
Vine.DRAG = 0.1 -- share of the swing speed lost a second (the swing fades when you stop pumping)
Vine.AMP_MAX = 62 -- degrees: the highest a pumped swing goes
Vine.CARRY = 0.85 -- share of your speed along the swing a grab keeps (a chain flows rope to rope)
Vine.ROPE = 0.5 -- share of the rope's own swing speed a grab adds
Vine.UP = 12 -- studs/s up added on a let go
Vine.GRACE = 0.25 -- seconds after a grab before a jump press lets go
Vine.STEER = 16 -- studs/s² of air steering after a let go (ObbyMoves.STEER_ACCEL)
Vine.REACH = table.freeze({ easy = 5, medium = 4.5, hard = 4 }) -- knob centre to your body, studs
Vine.HINT = table.freeze({ easy = 0.9, medium = 0.5, hard = 0.3 }) -- seconds of the release arc the dots show
Vine.STEP = 1 / 120 -- the longest physics step

-- Local attributes ObbyMoves writes on a rope part the local player holds and ObbyFx reads: the rope's angle
-- (radians) and how much of it to show over the server-time swing (0..1, faded back after a let go).
Vine.HELD_ANGLE = "ObbyHeldAngle"
Vine.HELD_FADE = "ObbyHeldFade"
-- The same for a rope another player holds (visuals/client/ObbyVineSync, from their replicated root); the local
-- player's own hold (HELD_*) wins when both are set.
Vine.OTHER_ANGLE = "ObbyOtherAngle"
Vine.OTHER_FADE = "ObbyOtherFade"
Vine.HOLD_SLACK = 6 -- studs past the rope's length a holder's root may be from its pivot and still be drawn on it

local AMP = math.rad(Vine.AMP_MAX)

-- The idle swing's period for a knob `arm` under its pivot (the small-angle pendulum).
function Vine.period(arm: number): number
	return 2 * math.pi * math.sqrt(arm / Vine.G)
end

-- The pendulum's length: pivot to your root.
function Vine.length(arm: number): number
	return arm + Vine.GRIP
end

-- Your root at rope angle `th`, from the pivot (s, y): the knob's centre in your hands, your body leaning TILT.
function Vine.rootAt(arm: number, th: number): (number, number)
	local lean = Vine.TILT * th
	return arm * math.sin(th) + Vine.GRIP * math.sin(lean), -arm * math.cos(th) - Vine.GRIP * math.cos(lean)
end

-- Your root's velocity (s, y) swinging at angle `th`, `w` radians/s (no let-go kick).
function Vine.velocityAt(arm: number, th: number, w: number): (number, number)
	local lean = Vine.TILT * th
	local T, G = Vine.TILT, Vine.GRIP
	return w * (arm * math.cos(th) + G * T * math.cos(lean)), w * (arm * math.sin(th) + G * T * math.sin(lean))
end

-- The let go: your velocity (s, y) off the rope at angle `th`, `w` radians/s, with the UP kick.
function Vine.release(arm: number, th: number, w: number): (number, number)
	local vs, vy = Vine.velocityAt(arm, th, w)
	return vs, vy + Vine.UP
end

-- The angular speed (radians/s, >= 0) at angle `th` of a swing that turns at `amp` radians.
function Vine.speedAt(arm: number, th: number, amp: number): number
	local k = Vine.G / Vine.length(arm)
	return math.sqrt(math.max(2 * k * (math.cos(th) - math.cos(amp)), 0))
end

-- The highest swing a held rope reaches (radians).
function Vine.ampMax(): number
	return AMP
end

-- One physics step of a held rope: gravity, the pump (`push` -1..1, the stick along the swing's s direction),
-- the fade and the AMP_MAX cap. Returns the new angle and angular speed.
function Vine.step(arm: number, th: number, w: number, push: number, dt: number): (number, number)
	local L = Vine.length(arm)
	local k = Vine.G / L
	local left = dt
	local cap = k * (1 - math.cos(AMP))
	while left > 1e-9 do
		local h = math.min(left, Vine.STEP)
		left -= h
		local a = -k * math.sin(th)
		-- holding the stick along the swing (either way) pumps it the way it swings; from a near standstill it
		-- starts it the way you push. It never brakes: let go of the stick and the swing fades by itself
		if push ~= 0 then
			local dir = if math.abs(w) < 0.4 then math.sign(push) else math.sign(w)
			a += Vine.PUMP / L * math.min(math.abs(push), 1) * dir
		end
		w += a * h
		w -= w * Vine.DRAG * h
		th += w * h
		local e = 0.5 * w * w + k * (1 - math.cos(th))
		if e > cap then
			if math.abs(th) >= AMP then
				th = math.sign(th) * AMP
				w = 0
			else
				local room = math.max(cap - k * (1 - math.cos(th)), 0)
				w = math.sign(w) * math.sqrt(2 * room)
			end
		end
	end
	return th, w
end

-- The grab: the rope angle for a root at (s, y) from the pivot, and the angular speed from your velocity (vs, vy)
-- and the rope's own `ropeW` (radians/s).
function Vine.grab(arm: number, s: number, y: number, vs: number, vy: number, ropeW: number): (number, number)
	local th = math.clamp(math.atan2(s, -y), -AMP, AMP)
	-- your speed along the swing at that angle (the direction the root moves for a growing angle)
	local ts, ty = Vine.velocityAt(arm, th, 1)
	local n = math.sqrt(ts * ts + ty * ty)
	local along = if n > 1e-6 then (vs * ts + vy * ty) / n else 0
	local w = Vine.CARRY * along / Vine.length(arm) + Vine.ROPE * ropeW
	-- never more than the cap allows at that angle
	local most = Vine.speedAt(arm, th, AMP)
	return th, math.clamp(w, -most, most)
end

-- The rope angle that hangs a root at (s, y) from the pivot (rootAt turned back, lean included), within AMP_MAX;
-- nil when the root is further than the rope's length plus HOLD_SLACK from the pivot (not hanging on it).
function Vine.angleAt(arm: number, s: number, y: number): number?
	if s * s + y * y > (Vine.length(arm) + Vine.HOLD_SLACK) ^ 2 then
		return nil
	end
	local phi = math.atan2(s, -y)
	local th = phi
	for _ = 1, 6 do
		local rs, ry = Vine.rootAt(arm, th)
		th += phi - math.atan2(rs, -ry)
	end
	return math.clamp(th, -AMP, AMP)
end

-- Whether a knob centre at (kx, ky, kz) is within `reach` of a body whose root is at (x, y, z) (feet to head).
function Vine.touches(x: number, y: number, z: number, kx: number, ky: number, kz: number, reach: number): boolean
	local cy = math.clamp(ky, y - Vine.FEET, y + Vine.HEAD)
	local dx, dy, dz = kx - x, ky - cy, kz - z
	return dx * dx + dy * dy + dz * dz <= reach * reach
end

return table.freeze(Vine)
