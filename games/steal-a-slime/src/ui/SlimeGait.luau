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
	  SlimeGait.step(state, persona, x, z, hx, hz, now, rand, out?) -> Pose
	      (x, z) anchor; (hx, hz) unit heading of the Body (used while it stands)
	  SlimeGait.shape(stage, u, height, kind) -> Shape    one hop moment (pure)
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local ParadeLane = if Shared then require(Shared.ParadeLane) else require("../shared/ParadeLane")
local SlimePersona = if Shared then require(Shared.SlimePersona) else require("../shared/SlimePersona")

local SlimeGait = {}

SlimeGait.CROUCH = 0.13 -- seconds of anticipation squat before every jump
SlimeGait.MAX_GAP = 9 -- studs between the visible body and the anchor before it snaps back
SlimeGait.MIN_SPEED = 0.3 -- studs / s: slower than this counts as standing (no new jump)
SlimeGait.VELOCITY_RATE = 8 -- 1 / s: how fast the anchor velocity estimate follows (the Body replicates in steps)
SlimeGait.STRING_SHARE = 0.28 -- share of the air time the goo string hangs on
-- studs to the side a zig-zag hop lands: a third to 0.6 of the lane room beside the outermost walking line
SlimeGait.ZIG = table.freeze({ ParadeLane.ROOM / 3, ParadeLane.ROOM * 0.6 })
SlimeGait.SHY = 0.7 -- Shy hoppers jump this much lower
SlimeGait.JIGGLE = { stiff = 45, damp = 4.5, gain = 0.04, max = 0.35 } -- crown lag: spring on the visible acceleration

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
	phase: number, -- per-slime offset for the float bob
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
		phase = phase or 0,
	}
end

-- One hop moment. stage "crouch" | "air": u 0..1; "land": u = seconds since landing.
function SlimeGait.shape(stage: string, u: number, height: number, kind: string): Shape
	local k = math.sqrt(math.max(height, 0.3) / 1.4)
	local o: Shape = { lift = 0, sx = 1, sy = 1, tilt = 0, face = nil, vy = 0 }
	if stage == "crouch" then
		local c = smooth(u)
		o.sy = 1 - 0.24 * k * c
		o.sx = 1 + 0.16 * k * c
		o.tilt = -0.1 * c -- leans back, loading the spring
		o.face = if kind == "boing" then "excited" else nil
	elseif stage == "air" then
		o.lift = height * 4 * u * (1 - u)
		o.vy = height * 4 * (1 - 2 * u)
		local st = math.abs(math.cos(math.pi * u)) ^ 1.6 -- stretched while fast, round at the top
		o.sy = 1 + 0.3 * k * st
		o.sx = 1 - 0.15 * k * st
		o.tilt = 0.3 * -math.cos(math.pi * u) -- nose up going up, nose down coming down
		if kind == "boing" then
			o.tilt = 2 * math.pi * smooth((u - 0.12) / 0.72) -- a full forward flip
			o.face = "excited"
		elseif kind == "belly" then
			o.tilt = if u < 0.55 then 0.3 * -math.cos(math.pi * u) else 1.35 * smooth((u - 0.55) / 0.45)
			o.face = if u > 0.55 then "surprised" else "happy"
		elseif u > 0.18 and u < 0.82 then
			o.face = "happy"
		end
	else
		if kind == "belly" then
			if u < 0.55 then
				o.sy = 0.5 + 0.05 * math.sin(u * 30) * (1 - u / 0.55)
				o.sx = 1.45
				o.face = "dizzy"
			else
				local v = u - 0.55
				o.sy = 1 - 0.5 * math.exp(-6 * v) * math.cos(12 * v)
				o.sx = 1 / math.sqrt(math.max(0.4, o.sy))
				o.face = if v < 0.3 then "dizzy" else nil
			end
		else
			local a = (if kind == "boing" then 0.48 elseif kind == "small" then 0.16 else 0.32) * k
			o.sy = 1 - a * math.exp(-7 * u) * math.cos(17 * u) -- splat, then a jelly wobble that dies out
			o.sx = 1 / math.sqrt(math.max(0.4, o.sy))
			if u < 0.12 then
				o.face = "squeeze"
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
	if temper == "Bouncy" and x < 0.08 then
		return "boing"
	elseif (temper == "Bouncy" or temper == "Curious") and x < 0.13 then
		return "belly"
	elseif temper ~= "Shy" and temper ~= "Lazy" and x < 0.25 then
		return "zig"
	end
	return if st.n % 3 == 2 then "big" else "normal"
end

local function blankPose(out: Pose?): Pose
	local p: Pose = out or {} :: any
	p.dx, p.dz, p.lift, p.sx, p.sy, p.tilt, p.roll, p.jiggle = 0, 0, 0, 1, 1, 0, 0, 0
	p.air, p.vy, p.face, p.landed = false, 0, nil, 0
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
		p.dx, p.dz = st.visX - x, st.visZ - z
		p.air = true
		p.kind = st.kind
		return
	end
	-- On the ground: settle (splat + wobble), then wait for the anchor to get a leap ahead.
	local since = now - st.landedAt
	local s = SlimeGait.shape("land", since, st.height, st.kind)
	p.dx, p.dz = st.visX - x, st.visZ - z
	p.sx, p.sy, p.face = s.sx, s.sy, s.face
	p.kind = st.kind
	local settle = style.settle + (if st.kind == "belly" then 0.75 elseif st.kind == "boing" then 0.35 else 0)
	local ahead = (x - st.visX) * fx + (z - st.visZ) * fz
	if since > settle and speed > SlimeGait.MIN_SPEED and ahead > style.wait * shy then
		st.nextKind = nextKind(persona, st, rand)
		st.stage = "crouch"
		st.t0 = now
	end
end

local function stride(st: State, persona: SlimePersona.Persona, now: number, p: Pose)
	local speed = math.sqrt(st.vx * st.vx + st.vz * st.vz)
	local gate = smooth(speed / 2.2) -- a standing slime doesn't step
	local gait = persona.gait
	local f = (st.travelled / (SlimeGait.STRIDES[gait] or 2)) % 1
	local g = math.sin(math.pi * f)
	if gait == "Ooze" then
		-- inchworm surge: stretches forward, then pulls its back in
		p.sx = 1 + 0.16 * g * gate
		p.sy = 1 - 0.13 * g * gate
		p.tilt = 0.1 * math.sin(2 * math.pi * f) * gate
	elseif gait == "Waddle" then
		local step = math.floor(st.travelled / SlimeGait.STRIDES.Waddle) % 2
		p.roll = (if step == 0 then -1 else 1) * 0.2 * g * gate
		p.lift = 0.18 * g * gate
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
	out: Pose?
): Pose
	local p = blankPose(out)
	local dt = now - st.lastT
	if dt > 0 then
		-- The Body replicates in steps: follow its velocity smoothly.
		local k = 1 - math.exp(-dt * SlimeGait.VELOCITY_RATE)
		local mx, mz = (x - st.lastX) / dt, (z - st.lastZ) / dt
		if mx * mx + mz * mz > 60 * 60 then -- a teleport, not a walk
			mx, mz = st.vx, st.vz
		end
		st.vx += (mx - st.vx) * k
		st.vz += (mz - st.vz) * k
		st.travelled += math.sqrt((x - st.lastX) ^ 2 + (z - st.lastZ) ^ 2)
		st.lastX, st.lastZ, st.lastT = x, z, now
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
