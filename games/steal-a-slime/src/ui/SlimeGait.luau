--!strict
--[[
	SlimeGait (pure, contract/slime-life.md)

	How a slime's body moves along the ground, per species gait
	(Shared.SlimePersona): real hops for "Hop", and distance-locked
	surges / waddles / pushes / hovering for the others. No Roblox APIs:
	positions are plain x / z numbers in world studs, so tests/ui/SlimeGait.spec
	steps it under Lune.

	The server moves the slime's Body (the anchor). A hopper's visible body
	waits on the ground while the anchor moves on, squats, then jumps a
	parabola to where the anchor will be when it lands, splats and wobbles.
	The caller turns (dx, dz), the visible spot minus the anchor, into the
	SkinRoot / FaceRoot Transform. A hopper is never more than one leap from
	the anchor; anything further (a teleport, the end of the fountain ride)
	snaps it back.

	  SlimeGait.new(x, z, now, phase?) -> State
	  SlimeGait.step(state, persona, x, z, hx, hz, now, rand, out?, vx?, vz?) -> Pose
	      vx / vz: the anchor's velocity when the caller knows it (else it is measured from x / z)
	      (x, z) anchor; (hx, hz) unit heading of the Body (used while it stands)
	  SlimeGait.shape(stage, u, height, kind) -> Shape    one hop moment (pure)
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local ParadeLane = if Shared then require(Shared.ParadeLane) else require("../shared/ParadeLane")
local SlimePersona = if Shared then require(Shared.SlimePersona) else require("../shared/SlimePersona")

local SlimeGait = {}

SlimeGait.CROUCH = 0.15 -- seconds of anticipation squat before every jump
-- share of the flight it spends pushing off: still on the ground, it springs out of the squat into the take-off
-- stretch (over several frames, never one) and only then leaves the ground
SlimeGait.PUSH = 0.16
SlimeGait.FALL_STRETCH = 0.08 -- how long it is as it lands (x k): small, so the splat isn't a jump in height
SlimeGait.SPLAT_IN = 0.025 -- seconds over which the landing splat comes in
SlimeGait.LEVEL_OUT = 0.06 -- seconds over which the landing tilt eases level
SlimeGait.MAX_GAP = 9 -- studs between the visible body and the anchor before it snaps back
SlimeGait.MIN_SPEED = 0.3 -- studs / s: slower than this counts as standing (no new jump)
-- studs: a hopper this far behind its anchor catches up: it cuts a long landing (a belly flop's lie-down) short and
-- jumps even when the anchor has stopped (a lane beat), so it never sits stranded behind where it should be
SlimeGait.CATCH_UP = 2
-- studs: a hopper that landed past its anchor (it leapt as the lane stopped for a beat or a queue) waits for the lane
-- to catch up instead of hopping back to it facing forward; only this far past it does it hop back
SlimeGait.OVERSHOOT = 4
SlimeGait.VELOCITY_RATE = 5 -- 1 / s: how fast the anchor velocity estimate follows (the Body replicates in steps)
SlimeGait.STILL_AFTER = 0.25 -- seconds without a Body update before the slime counts as standing
SlimeGait.STRING_SHARE = 0.28 -- share of the air time the goo string hangs on
-- studs to the side a zig-zag hop lands: a third to 0.6 of the lane room beside the outermost walking line
SlimeGait.ZIG = table.freeze({ ParadeLane.ROOM / 3, ParadeLane.ROOM * 0.6 })
SlimeGait.SHY = 0.7 -- Shy hoppers jump this much lower
SlimeGait.JIGGLE = { stiff = 40, damp = 7, gain = 0.025, max = 0.25 } -- crown lag: spring on the visible acceleration (well damped: a sway, never a buzz)

export type Kind = "normal" | "big" | "small" | "boing" | "belly" | "zig"

-- Per hop kind: height and air-time multipliers.
SlimeGait.KINDS = table.freeze({
	normal = table.freeze({ height = 1, air = 1 }),
	big = table.freeze({ height = 1.35, air = 1.15 }),
	small = table.freeze({ height = 0.6, air = 0.75 }),
	boing = table.freeze({ height = 2.4, air = 1.5 }),
	belly = table.freeze({ height = 1.2, air = 1.1 }),
	zig = table.freeze({ height = 0.9, air = 0.95 }),
} :: { [string]: { height: number, air: number } })

-- Per gait (not Hop): stride (studs per step at size 1) and how much of it shows.
SlimeGait.STRIDES = table.freeze({ Ooze = 2.0, Waddle = 1.1, Scoot = 1.6, Float = 3.0 } :: { [string]: number })

export type Face = "happy" | "squeeze" | "excited" | "dizzy" | "smug" | "surprised"

export type Shape = {
	lift: number, -- studs (times the slime's size)
	sx: number,
	sy: number,
	tilt: number, -- radians, + = nose down / forward
	face: Face?,
	vy: number, -- vertical speed of the hop, studs / s at size 1 (+ = up)
}

export type State = {
	stage: "ground" | "crouch" | "air",
	visX: number,
	visZ: number,
	side: number, -- current sideways offset (studs, + = the heading's right)
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	sideFrom: number,
	sideTo: number,
	t0: number, -- stage start
	dur: number, -- air seconds
	height: number,
	kind: Kind,
	nextKind: Kind,
	n: number, -- jumps so far
	landedAt: number,
	lastX: number,
	lastZ: number,
	lastT: number,
	vx: number,
	vz: number,
	travelled: number, -- studs the anchor moved (non-hop gaits lock their step to it)
	jig: number,
	jigV: number,
	visVX: number, -- last visible spot (crown lag)
	visVZ: number,
	fwd: number, -- last visible forward speed
	changedAt: number, -- when the anchor last moved (the Body replicates in steps)
	phase: number, -- per-slime offset for the float bob
	stride: number, -- stride multiplier: 1 for a slime; a boss sets its drawn size, so its big body takes big steps
	tricks: boolean, -- false: plain hops only (a boss: a giant belly flop or zig-zag reads as a glitch)
}

export type Pose = {
	dx: number, -- visible spot minus the anchor, world studs
	dz: number,
	lift: number, -- studs at size 1
	sx: number,
	sy: number,
	tilt: number, -- + = forward
	roll: number, -- + = lean to the right
	jiggle: number, -- crown lag, radians (+ = forward)
	air: boolean,
	vy: number,
	face: Face?,
	landed: number, -- > 0 on the frame a hop lands: how hard (0..2)
	launched: number, -- > 0 on the frame a hop takes off: how hard (0..2; the jelly's follow-through kick)
	stringX: number?, -- goo string: the take-off spot while it hangs on
	stringZ: number?,
	stringAlpha: number,
	kind: Kind?,
}

type Rand = () -> number

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

function SlimeGait.new(x: number, z: number, now: number, phase: number?): State
	return {
		stage = "ground",
		visX = x,
		visZ = z,
		side = 0,
		fromX = x,
		fromZ = z,
		toX = x,
		toZ = z,
		sideFrom = 0,
		sideTo = 0,
		t0 = now,
		dur = 0.4,
		height = 1,
		kind = "normal",
		nextKind = "normal",
		n = 0,
		landedAt = now - 10,
		lastX = x,
		lastZ = z,
		lastT = now,
		vx = 0,
		vz = 0,
		travelled = 0,
		jig = 0,
		jigV = 0,
		visVX = x,
		visVZ = z,
		fwd = 0,
		changedAt = now,
		phase = phase or 0,
		stride = 1,
		tricks = true,
	}
end

-- One hop moment. stage "crouch" | "air": u 0..1; "land": u = seconds since landing.
function SlimeGait.shape(stage: string, u: number, height: number, kind: string): Shape
	local k = math.sqrt(math.max(height, 0.3) / 1.4)
	local o: Shape = { lift = 0, sx = 1, sy = 1, tilt = 0, face = nil, vy = 0 }
	if stage == "crouch" then
		local c = smooth(u)
		o.sy = 1 - 0.26 * k * c -- a deep squat: the anticipation reads before every jump
		o.sx = 1 + 0.2 * k * c
		o.tilt = -0.18 * c -- leans back, loading the spring (as far as the take-off starts, so it doesn't snap)
		o.face = if kind == "boing" then "excited" else nil
	elseif stage == "air" then
		-- the push-off (the first PUSH of the flight) keeps its feet down while it springs out of the squat; the arc is
		-- the rest. Shot out tall as it leaves the ground, round at the top, a little long again as it drops.
		local w = math.clamp((u - SlimeGait.PUSH) / (1 - SlimeGait.PUSH), 0, 1)
		o.lift = height * 4 * w * (1 - w)
		o.vy = if u < SlimeGait.PUSH then 0 else height * 4 * (1 - 2 * w) / (1 - SlimeGait.PUSH)
		local st = 0.3 * (1 - w) ^ 3 + SlimeGait.FALL_STRETCH * w ^ 4
		local push = smooth(math.min(u / SlimeGait.PUSH, 1))
		local squatY, squatX = 1 - 0.26 * k, 1 + 0.2 * k
		o.sy = squatY + (1 + k * st - squatY) * push
		o.sx = squatX + (1 - 0.5 * k * st - squatX) * push
		o.tilt = 0.18 * -math.cos(math.pi * w) -- nose up going up, nose down coming down
		-- the tricks take over from the squat's lean-back (-0.18) as it leaves the ground, never in one frame
		local fade = 1 - smooth(math.min(w / 0.15, 1))
		if kind == "boing" then
			o.tilt = -0.18 * fade + 2 * math.pi * smooth((w - 0.05) / 0.8) -- a full forward flip, off the ground
			o.face = "excited"
		elseif kind == "belly" then
			local flop = if w < 0.55 then 0.3 * -math.cos(math.pi * w) else 1.35 * smooth((w - 0.55) / 0.45)
			o.tilt = flop + (-0.18 - -0.3) * fade
			o.face = if w > 0.55 then "surprised" else "happy"
		elseif kind == "big" and w > 0.25 and w < 0.75 then
			-- shut happy eyes only for a big joyful leap: on every hop they hid the eyes a third of the time
			o.face = "happy"
		end
	else
		if kind == "belly" then
			-- flat on its belly: the flop's forward tip eases out instead of snapping upright
			o.tilt = 1.35 * math.exp(-u / (5 * SlimeGait.LEVEL_OUT))
			if u < 0.55 then
				-- it flattens out over SPLAT_IN, like any landing, from the fall's stretch
				local ramp = 1 - math.exp(-u / SlimeGait.SPLAT_IN)
				local fallY = 1 + k * SlimeGait.FALL_STRETCH
				o.sy = fallY + (0.68 + 0.04 * math.sin(u * 12) * (1 - u / 0.55) - fallY) * ramp
				o.sx = 1.22
				o.face = "dizzy"
			else
				local v = u - 0.55
				o.sy = 1 - 0.32 * math.exp(-6 * v) * math.cos(12 * v)
				o.sx = 1 / math.sqrt(math.max(0.4, o.sy))
				o.face = if v < 0.3 then "dizzy" else nil
			end
		else
			-- the impact splat; the jelly wobble after it comes from the actor's squash spring (kicked on landing),
			-- which rings on through the next squat and jump instead of restarting every hop
			local a = (if kind == "boing" then 0.4 elseif kind == "small" then 0.18 else 0.3) * k
			-- it lands still a little long and tipped nose down (the end of the flight): the splat comes in over
			-- SPLAT_IN seconds and the tilt eases level, so the landing frame never snaps the pose
			local ramp = 1 - math.exp(-u / SlimeGait.SPLAT_IN)
			local fallY = 1 + k * SlimeGait.FALL_STRETCH
			o.sy = fallY + (1 - a * math.exp(-14 * u) - fallY) * ramp
			o.sx = 1 / math.sqrt(math.max(0.4, o.sy))
			o.tilt = (if kind == "boing" then 0 else 0.18) * math.exp(-u / SlimeGait.LEVEL_OUT)
			if u < 0.12 and (kind == "big" or kind == "boing") then
				o.face = "squeeze" -- a hard landing only; a plain hop lands with its eyes open
			elseif kind == "boing" and u < 0.6 then
				o.face = "smug"
			end
		end
	end
	return o
end

local function nextKind(persona: SlimePersona.Persona, st: State, rand: Rand): Kind
	if st.kind == "boing" or st.kind == "belly" then
		return "small"
	end
	local temper = persona.temper
	local x = rand()
	if not st.tricks then
		return if st.n % 3 == 2 then "big" else "normal"
	elseif temper == "Bouncy" and x < 0.04 then
		return "boing"
	elseif (temper == "Bouncy" or temper == "Curious") and x < 0.07 then
		return "belly"
	elseif temper ~= "Shy" and temper ~= "Lazy" and x < 0.18 then
		return "zig"
	end
	return if st.n % 3 == 2 then "big" else "normal"
end

local function blankPose(out: Pose?): Pose
	local p: Pose = out or {} :: any
	p.dx, p.dz, p.lift, p.sx, p.sy, p.tilt, p.roll, p.jiggle = 0, 0, 0, 1, 1, 0, 0, 0
	p.air, p.vy, p.face, p.landed, p.launched = false, 0, nil, 0, 0
	p.stringX, p.stringZ, p.stringAlpha, p.kind = nil, nil, 0, nil
	return p
end

local function hop(
	st: State,
	persona: SlimePersona.Persona,
	x: number,
	z: number,
	hx: number,
	hz: number,
	now: number,
	rand: Rand,
	p: Pose
)
	local style = persona.hop
	local shy = if persona.temper == "Shy" then SlimeGait.SHY else 1
	local speed = math.sqrt(st.vx * st.vx + st.vz * st.vz)
	-- Direction of travel: the anchor's motion, or the Body's heading while it stands.
	local fx, fz = hx, hz
	if speed > SlimeGait.MIN_SPEED then
		fx, fz = st.vx / speed, st.vz / speed
	end
	if (st.visX - x) ^ 2 + (st.visZ - z) ^ 2 > SlimeGait.MAX_GAP ^ 2 then
		st.stage, st.visX, st.visZ, st.landedAt = "ground", x, z, now - 10
	end
	if st.stage == "air" then
		local u = (now - st.t0) / st.dur
		if u < 1 then
			local s = SlimeGait.shape("air", u, st.height, st.kind)
			p.dx = st.fromX + (st.toX - st.fromX) * u - x
			p.dz = st.fromZ + (st.toZ - st.fromZ) * u - z
			st.side = st.sideFrom + (st.sideTo - st.sideFrom) * smooth(u)
			p.lift, p.sx, p.sy, p.tilt, p.face = s.lift, s.sx, s.sy, s.tilt, s.face
			p.vy = s.vy / st.dur
			p.air = true
			p.kind = st.kind
			if u < SlimeGait.STRING_SHARE then
				p.stringX, p.stringZ, p.stringAlpha = st.fromX, st.fromZ, 1 - u / SlimeGait.STRING_SHARE
			end
			return
		end
		st.stage = "ground"
		st.visX, st.visZ, st.side = st.toX, st.toZ, st.sideTo
		st.landedAt = now
		p.landed = math.min(2, st.height / 1.2)
	end
	if st.stage == "crouch" then
		local u = (now - st.t0) / SlimeGait.CROUCH
		if u < 1 then
			local s =
				SlimeGait.shape("crouch", u, style.height * SlimeGait.KINDS[st.nextKind].height * shy, st.nextKind)
			p.dx, p.dz = st.visX - x, st.visZ - z
			p.sx, p.sy, p.tilt, p.face = s.sx, s.sy, s.tilt, s.face
			p.kind = st.nextKind
			return
		end
		-- Take off: land where the anchor will be.
		local spec = SlimeGait.KINDS[st.nextKind]
		st.kind = st.nextKind
		st.dur = style.air * spec.air * (if shy < 1 then 0.85 else 1)
		st.height = style.height * spec.height * shy
		st.fromX, st.fromZ = st.visX, st.visZ
		st.toX, st.toZ = x + st.vx * st.dur * 1.05, z + st.vz * st.dur * 1.05
		st.sideFrom = st.side
		if st.kind == "zig" then
			local reach = SlimeGait.ZIG[1] + rand() * (SlimeGait.ZIG[2] - SlimeGait.ZIG[1])
			st.sideTo = (if st.side > 0 then -1 else 1) * reach
		else
			st.sideTo = st.side * 0.5
		end
		st.t0 = now
		st.stage = "air"
		st.n += 1
		p.launched = math.min(2, st.height / 1.2)
		p.dx, p.dz = st.visX - x, st.visZ - z
		-- the take-off frame draws the flight's first pose (a blank pose here blinked every hop)
		local s0 = SlimeGait.shape("air", 0, st.height, st.kind)
		p.lift, p.sx, p.sy, p.tilt, p.face = s0.lift, s0.sx, s0.sy, s0.tilt, s0.face
		p.vy = s0.vy / st.dur
		p.air = true
		p.kind = st.kind
		return
	end
	-- On the ground: settle (splat + wobble), then wait for the anchor to get a leap ahead.
	local since = now - st.landedAt
	local s = SlimeGait.shape("land", since, st.height, st.kind)
	p.dx, p.dz = st.visX - x, st.visZ - z
	p.sx, p.sy, p.tilt, p.face = s.sx, s.sy, s.tilt, s.face
	p.kind = st.kind
	local settle = style.settle + (if st.kind == "belly" then 0.75 elseif st.kind == "boing" then 0.35 else 0)
	local ahead = (x - st.visX) * fx + (z - st.visZ) * fz
	local far = (x - st.visX) ^ 2 + (z - st.visZ) ^ 2
	local behind = far > SlimeGait.CATCH_UP ^ 2 and (ahead > 0 or far > SlimeGait.OVERSHOOT ^ 2)
	local rested = since > settle or (behind and since > style.settle)
	if rested and (speed > SlimeGait.MIN_SPEED or behind) and (ahead > style.wait * shy or behind) then
		st.nextKind = nextKind(persona, st, rand)
		st.stage = "crouch"
		st.t0 = now
	end
end

local function stride(st: State, persona: SlimePersona.Persona, now: number, p: Pose)
	local speed = math.sqrt(st.vx * st.vx + st.vz * st.vz)
	local gate = smooth(speed / 2.2) -- a standing slime doesn't step
	local gait = persona.gait
	local f = (st.travelled / ((SlimeGait.STRIDES[gait] or 2) * st.stride)) % 1
	local g = math.sin(math.pi * f)
	if gait == "Ooze" then
		-- inchworm surge: stretches forward, then pulls its back in
		p.sx = 1 + 0.16 * g * gate
		p.sy = 1 - 0.13 * g * gate
		p.tilt = 0.1 * math.sin(2 * math.pi * f) * gate
	elseif gait == "Waddle" then
		local step = math.floor(st.travelled / (SlimeGait.STRIDES.Waddle * st.stride)) % 2
		-- rocks from foot to foot with its feet on the ground: a body-wide lift reads as flying on flat-footed slimes
		p.roll = (if step == 0 then -1 else 1) * 0.16 * g * gate
		p.lift = 0.03 * g * gate
		p.sy = 1 - 0.05 * (1 - g) * gate
	elseif gait == "Scoot" then
		local k = g ^ 3
		p.sx = 1 + 0.12 * k * gate
		p.sy = 1 - 0.1 * k * gate + 0.06 * (1 - g) ^ 6 * gate
		p.lift = 0.12 * k * gate
		p.tilt = 0.12 * k * gate
	elseif gait == "Float" then
		p.lift = 0.9 + 0.3 * math.sin(now * 2.2 + st.phase)
		p.tilt = 0.12 * math.clamp(speed / 4, 0, 1.5) + 0.05 * math.sin(now * 1.3 + st.phase)
		p.sy = 1 + 0.03 * math.sin(now * 4.4 + st.phase)
	end
end

function SlimeGait.step(
	st: State,
	persona: SlimePersona.Persona,
	x: number,
	z: number,
	hx: number,
	hz: number,
	now: number,
	rand: Rand,
	out: Pose?,
	knownVx: number?,
	knownVz: number?
): Pose
	local p = blankPose(out)
	local dt = now - st.lastT
	if dt > 0 then
		local moved = math.sqrt((x - st.lastX) ^ 2 + (z - st.lastZ) ^ 2)
		if knownVx and knownVz then
			-- The caller knows the anchor's velocity (a lane slime's spot is lane math): no estimate, no jitter.
			st.vx, st.vz = knownVx, knownVz
			st.travelled += moved
			st.lastX, st.lastZ, st.lastT, st.changedAt = x, z, now, now
		elseif moved > 1e-4 or now - st.changedAt > SlimeGait.STILL_AFTER then
			-- The Body replicates in steps (several frames apart): measure over the whole step, not per frame.
			local span = math.max(now - st.changedAt, dt)
			local mx, mz = (x - st.lastX) / span, (z - st.lastZ) / span
			if mx * mx + mz * mz > 60 * 60 then -- a teleport, not a walk
				mx, mz = st.vx, st.vz
			end
			local k = 1 - math.exp(-span * SlimeGait.VELOCITY_RATE)
			st.vx += (mx - st.vx) * k
			st.vz += (mz - st.vz) * k
			st.travelled += moved
			st.lastX, st.lastZ, st.lastT, st.changedAt = x, z, now, now
		else
			st.lastT = now
		end
	end
	if persona.gait == "Hop" then
		hop(st, persona, x, z, hx, hz, now, rand, p)
		-- the zig-zag offset sits across the heading
		local speed = math.sqrt(st.vx * st.vx + st.vz * st.vz)
		local fx, fz =
			if speed > SlimeGait.MIN_SPEED then st.vx / speed else hx,
			if speed > SlimeGait.MIN_SPEED then st.vz / speed else hz
		p.dx += -fz * st.side
		p.dz += fx * st.side
	else
		stride(st, persona, now, p)
	end
	-- Crown lag: a spring driven by the visible body's forward acceleration (a hop's take-off and landing kick it).
	local vx, vz = x + p.dx, z + p.dz
	if dt > 0 then
		local speed = math.sqrt(st.vx * st.vx + st.vz * st.vz)
		local fx, fz =
			if speed > SlimeGait.MIN_SPEED then st.vx / speed else hx,
			if speed > SlimeGait.MIN_SPEED then st.vz / speed else hz
		local forward = ((vx - st.visVX) * fx + (vz - st.visVZ) * fz) / dt
		local accel = math.clamp((forward - st.fwd) / dt, -80, 80)
		st.fwd = forward
		local J = SlimeGait.JIGGLE
		st.jigV += (-J.stiff * st.jig - J.damp * st.jigV - accel * J.gain) * dt
		st.jig = math.clamp(st.jig + st.jigV * dt, -J.max, J.max)
	end
	st.visVX, st.visVZ = vx, vz
	p.jiggle = st.jig
	return p
end

return SlimeGait
