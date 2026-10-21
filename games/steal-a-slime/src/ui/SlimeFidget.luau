--!strict
--[[
	SlimeFidget (pure, contract/slime-life.md "Alive motion")

	What a slime on a pad does between breaths: every EVERY seconds it picks a fidget, weighted by its temperament
	(Shared.SlimePersona) and never the same one twice in a row, and plays its pose curve. Also the put-downs: a
	slime that lands on its pad drops in, splats, shakes off and looks round; a slime moved to another pad hops
	there in an arc. No Roblox APIs; tests/ui/SlimeFidget.spec covers it.

	  SlimeFidget.new(temper, now, rand) -> State
	  SlimeFidget.step(state, now, rand, out?) -> Pose        the pose now (blank between fidgets)
	  SlimeFidget.play(state, kind, now)                       start a fidget or put-down now ("drop", "arrive", ...)
	  SlimeFidget.setMood(state, mood, now, rand)              "near" (the player is close: it greets them soon, then
	                                                           fidgets more often, from WEIGHTS_NEAR) | "idle"
	  SlimeFidget.pose(kind, u, out?) -> Pose                  one moment of a fidget, u = seconds since it started

	Pose: lift (studs at size 1), sx / sy (squash multipliers), tilt (+ = nose down), roll (+ = lean right),
	yaw / yawWeight (a turn from the heading and how much of it to take; a turn past half a circle is a spin),
	carry (0..1: the share of an "arrive" jump still to go, 1 = at the old spot), face, emote (SlimeEmotes names),
	splat (> 0 on the frame it lands: how hard, for the squash spring and the goo splat).
]]

local SlimeFidget = {}

export type Kind =
	"hop"
	| "bounce"
	| "shake"
	| "stretch"
	| "spin"
	| "nap"
	| "peek"
	| "huff"
	| "wiggle"
	| "tilt"
	| "drop"
	| "arrive"

export type Pose = {
	lift: number,
	sx: number,
	sy: number,
	tilt: number,
	roll: number,
	yaw: number,
	yawWeight: number,
	spin: number, -- radians of a spin on top of the heading (0 .. 2 pi): plays as given, never chased
	carry: number,
	face: string?,
	emote: string?,
	splat: number,
}

export type Mood = "idle" | "near"

export type State = {
	temper: string,
	mood: Mood,
	kind: Kind?,
	t0: number,
	nextAt: number,
	last: Kind?,
	splats: number, -- splats of the current fidget reported so far
}

type Rand = () -> number

SlimeFidget.EVERY = table.freeze({ 4, 9 }) -- seconds between fidgets
SlimeFidget.FIRST = table.freeze({ 1, 5 }) -- seconds before a new pad slime's first fidget
SlimeFidget.NEAR_EVERY = table.freeze({ 1.6, 3.4 }) -- seconds between fidgets while the player is close
SlimeFidget.GREET = table.freeze({ 0.3, 0.9 }) -- seconds from the player coming close to the greeting fidget
SlimeFidget.DROP_HEIGHT = 2.6 -- studs at size 1: a put-down falls from this high
SlimeFidget.MOVE_HOP = 0.62 -- seconds of a Move hop from crouch to landing

-- Seconds each kind lasts.
SlimeFidget.SECONDS = table.freeze({
	hop = 0.95,
	bounce = 1.15,
	shake = 0.8,
	stretch = 1.5,
	spin = 1.2,
	nap = 4.5,
	peek = 1.8,
	huff = 1.0,
	wiggle = 1.6,
	tilt = 1.1,
	drop = 2.2,
	arrive = 1.4,
} :: { [string]: number })

-- Fidget weights per temperament (Shared.SlimePersona.TEMPERS); drop / arrive are only played on purpose.
SlimeFidget.WEIGHTS = table.freeze({
	Bouncy = table.freeze({ hop = 3, bounce = 3, wiggle = 2, shake = 1, stretch = 1, spin = 1 }),
	Lazy = table.freeze({ nap = 4, stretch = 3, shake = 1, peek = 1 }),
	Curious = table.freeze({ peek = 4, tilt = 3, hop = 2, shake = 1, stretch = 1, wiggle = 1 }),
	Shy = table.freeze({ peek = 2, shake = 2, stretch = 2, nap = 1, hop = 1, tilt = 1 }),
	Showoff = table.freeze({ spin = 3, wiggle = 3, stretch = 1, hop = 1, bounce = 1 }),
	Feisty = table.freeze({ huff = 4, shake = 2, hop = 2, bounce = 1 }),
} :: { [string]: { [string]: number } })

-- While the player is close (mood "near"): livelier picks, no naps.
SlimeFidget.WEIGHTS_NEAR = table.freeze({
	Bouncy = table.freeze({ bounce = 3, hop = 2, wiggle = 3, spin = 1 }),
	Lazy = table.freeze({ stretch = 2, wiggle = 1, shake = 1, tilt = 1 }),
	Curious = table.freeze({ tilt = 3, peek = 2, hop = 2, wiggle = 1 }),
	Shy = table.freeze({ shake = 2, peek = 2, tilt = 1, stretch = 1 }),
	Showoff = table.freeze({ spin = 3, wiggle = 3, bounce = 1 }),
	Feisty = table.freeze({ huff = 3, hop = 1, bounce = 1, shake = 1 }),
} :: { [string]: { [string]: number } })

-- Splat moments (seconds since the start) per kind: where the squash spring gets its kick.
local SPLATS: { [string]: { number } } = {
	hop = { 0.46 },
	bounce = { 0.36, 0.74 },
	spin = { 0.68 },
	huff = { 0.16, 0.52 },
	drop = { 0.3 },
	arrive = { 0.1 + 0.52 },
}

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function between(range: { number }, rand: Rand): number
	return range[1] + rand() * (range[2] - range[1])
end

local function blank(out: Pose?): Pose
	local p: Pose = out or {} :: any
	p.lift, p.sx, p.sy, p.tilt, p.roll, p.yaw, p.yawWeight, p.carry = 0, 1, 1, 0, 0, 0, 0, 0
	p.spin = 0
	p.face, p.emote, p.splat = nil, nil, 0
	return p
end

-- A hop that starts at `t0` (seconds): crouch, then `air` seconds up to `height`, then a splat that wobbles out.
local function hopAt(p: Pose, u: number, t0: number, crouch: number, air: number, height: number)
	local v = u - t0
	if v < 0 then
		return
	elseif v < crouch then
		local c = smooth(v / crouch)
		p.sy *= 1 - 0.16 * c
		p.sx *= 1 + 0.12 * c
		p.tilt -= 0.06 * c
	elseif v < crouch + air then
		local q = (v - crouch) / air
		p.lift += height * 4 * q * (1 - q)
		local st = math.abs(math.cos(math.pi * q)) ^ 1.5
		p.sy *= 1 + 0.14 * st
		p.sx *= 1 - 0.07 * st
	else
		local w = v - crouch - air
		local s = 1 - 0.2 * math.exp(-8 * w) * math.cos(18 * w)
		p.sy *= s
		p.sx *= 1 / math.sqrt(math.max(0.4, s))
	end
end

function SlimeFidget.pose(kind: string, u: number, out: Pose?): Pose
	local p = blank(out)
	local D = SlimeFidget.SECONDS[kind] or 1
	if u < 0 or u > D then
		return p
	end
	-- everything fades in over the first 0.08 s and out over the last 0.2 s, so a fidget never pops
	local env = smooth(u / 0.08) * smooth((D - u) / 0.2)
	if kind == "hop" then
		hopAt(p, u, 0, 0.12, 0.34, 0.7)
		p.face = if u > 0.12 and u < 0.46 then "happy" else nil
	elseif kind == "bounce" then
		hopAt(p, u, 0, 0.08, 0.28, 0.5)
		hopAt(p, u, 0.38, 0.08, 0.28, 0.32)
		p.face = "happy"
		p.emote = "note"
	elseif kind == "shake" then
		-- a wet-dog shake: fast roll that starts strong and dies out
		local k = (1 - u / D) ^ 1.4 * smooth(u / 0.06)
		p.roll = 0.24 * math.sin(2 * math.pi * 7 * u) * k
		p.yaw, p.yawWeight = 0.18 * math.sin(2 * math.pi * 7 * u + 1.2) * k, k
		p.sy = 1 + 0.05 * k
		p.face = "squeeze"
	elseif kind == "stretch" then
		-- rises tall (a yawn), holds, then flops back with a wobble
		if u < 0.5 then
			local c = smooth(u / 0.5)
			p.sy, p.sx = 1 + 0.22 * c, 1 - 0.1 * c
			p.tilt = -0.12 * c
			p.face = "sleepy"
		elseif u < 0.8 then
			p.sy, p.sx, p.tilt = 1.22, 0.9, -0.12
			p.face = "happy"
		else
			local w = u - 0.8
			local s = 1 - 0.2 * math.exp(-6 * w) * math.cos(14 * w + 1.5)
			p.sy = s
			p.sx = 1 / math.sqrt(math.max(0.4, s))
			p.tilt = -0.12 * math.exp(-8 * w)
		end
	elseif kind == "spin" then
		hopAt(p, u, 0, 0.14, 0.54, 1.1)
		local q = math.clamp((u - 0.14) / 0.54, 0, 1)
		if q > 0 and q < 1 then
			p.spin = 2 * math.pi * smooth(q)
		end
		p.face = if u > 0.14 then "excited" else nil
		p.emote = "star"
	elseif kind == "nap" then
		local sink = smooth(u / 0.5) * smooth((D - u) / 0.4)
		p.sy = 1 - 0.13 * sink + 0.035 * math.sin(u * 2.4) * sink
		p.sx = 1 + 0.07 * sink
		p.tilt = 0.08 * sink
		p.face = if sink > 0.5 then "asleep" else nil
		p.emote = if sink > 0.5 then "sleep" else nil
		-- a little shiver as it wakes
		if D - u < 0.4 then
			p.roll = 0.08 * math.sin(2 * math.pi * 9 * u) * (D - u) / 0.4
		end
	elseif kind == "peek" then
		local lean = smooth(u / 0.3) * smooth((D - u) / 0.3)
		p.tilt = 0.22 * lean
		p.lift = 0.12 * lean
		p.sy = 1 + 0.06 * lean
		-- looks left, then right, then back
		p.yaw, p.yawWeight = 0.6 * math.sin(2 * math.pi * (u - 0.3) / (D - 0.6)) * lean, lean
		p.face = "surprised"
		p.emote = "ask"
	elseif kind == "huff" then
		for _, at in { 0, 0.36 } do
			local v = u - at
			if v >= 0 and v < 0.4 then
				local dip = math.sin(math.pi * math.min(v / 0.16, 1)) * (if v < 0.16 then 1 else 0)
				local w = math.max(v - 0.16, 0)
				p.sy *= (1 - 0.2 * dip) * (1 - 0.1 * math.exp(-9 * w) * math.sin(20 * w))
				p.lift += 0.25 * math.sin(math.pi * math.clamp(v / 0.16, 0, 1)) * (if v < 0.08 then 1 else 0)
			end
		end
		p.tilt = 0.12 * env
		p.face = "angry"
		p.emote = "angry"
	elseif kind == "wiggle" then
		p.roll = 0.2 * math.sin(2 * math.pi * 2.4 * u) * env
		p.yaw, p.yawWeight = 0.3 * math.sin(2 * math.pi * 1.2 * u) * env, env
		p.lift = 0.14 * math.abs(math.sin(2 * math.pi * 2.4 * u)) * env
		p.sy = 1 + 0.05 * math.abs(math.cos(2 * math.pi * 2.4 * u)) * env
		p.face = "happy"
		p.emote = "note"
	elseif kind == "tilt" then
		-- a curious head tilt: cocks its head to one side, holds, straightens up
		local k = smooth(u / 0.25) * smooth((D - u) / 0.3)
		p.roll = 0.22 * k
		p.lift = 0.06 * k
		p.sy = 1 + 0.04 * k
		p.face = if u < 0.35 then "surprised" else "happy"
		p.emote = "ask"
	elseif kind == "drop" then
		local fall = 0.3
		if u < fall then
			local q = u / fall
			p.lift = SlimeFidget.DROP_HEIGHT * (1 - q * q)
			p.sy, p.sx = 1 + 0.18 * q, 1 - 0.08 * q
			p.face = "surprised"
		else
			local w = u - fall
			local s = 1 - 0.36 * math.exp(-6 * w) * math.cos(15 * w)
			p.sy = s
			p.sx = 1 / math.sqrt(math.max(0.4, s))
			p.face = if w < 0.5 then "dizzy" else "happy"
			p.emote = if w < 0.6 then "dizzy" else nil
			-- shake it off, then look round
			local k = math.clamp((w - 0.45) / 0.5, 0, 1)
			if k > 0 and k < 1 then
				p.roll = 0.18 * math.sin(2 * math.pi * 6.5 * (w - 0.45)) * (1 - k)
			end
			local look = smooth((w - 1.0) / 0.25) * smooth((D - u) / 0.3)
			p.yaw, p.yawWeight = 0.55 * math.sin(2 * math.pi * (w - 1.0) / 0.9), look
		end
	elseif kind == "arrive" then
		local crouch, air = 0.1, SlimeFidget.MOVE_HOP - 0.1
		if u < crouch then
			p.carry = 1
		elseif u < crouch + air then
			local q = (u - crouch) / air
			p.carry = 1 - q
		end
		hopAt(p, u, 0, crouch, air, 1.4)
		p.tilt += if u > crouch and u < crouch + air then 0.15 * math.sin(math.pi * (u - crouch) / air) else 0
		p.face = if u > crouch and u < crouch + air + 0.15 then "excited" else nil
	end
	return p
end

local function pick(st: State, rand: Rand): Kind
	local set = if st.mood == "near" then SlimeFidget.WEIGHTS_NEAR else SlimeFidget.WEIGHTS
	local weights = set[st.temper] or set.Bouncy
	local total = 0
	for kind, w in weights do
		if kind ~= st.last then
			total += w
		end
	end
	-- a stable order, so the same rand gives the same pick
	local kinds = {}
	for kind in weights do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	local x = rand() * total
	for _, kind in kinds do
		if kind ~= st.last then
			x -= weights[kind]
			if x <= 0 then
				return kind :: Kind
			end
		end
	end
	return kinds[#kinds] :: Kind
end

function SlimeFidget.new(temper: string, now: number, rand: Rand): State
	return {
		temper = temper,
		mood = "idle",
		kind = nil,
		t0 = now,
		nextAt = now + between(SlimeFidget.FIRST, rand),
		last = nil,
		splats = 0,
	}
end

function SlimeFidget.setMood(st: State, mood: Mood, now: number, rand: Rand)
	if st.mood == mood then
		return
	end
	st.mood = mood
	if not st.kind then
		st.nextAt = now + between(if mood == "near" then SlimeFidget.GREET else SlimeFidget.EVERY, rand)
	end
end

function SlimeFidget.play(st: State, kind: Kind, now: number)
	st.kind, st.t0, st.splats = kind, now, 0
end

function SlimeFidget.step(st: State, now: number, rand: Rand, out: Pose?): Pose
	local kind = st.kind
	if kind and now - st.t0 > (SlimeFidget.SECONDS[kind] or 1) then
		st.last = if kind == "drop" or kind == "arrive" then st.last else kind
		st.kind = nil
		st.nextAt = now + between(if st.mood == "near" then SlimeFidget.NEAR_EVERY else SlimeFidget.EVERY, rand)
		kind = nil
	end
	if not kind and now >= st.nextAt then
		kind = pick(st, rand)
		SlimeFidget.play(st, kind, now)
	end
	if not kind then
		return blank(out)
	end
	local u = now - st.t0
	local p = SlimeFidget.pose(kind, u, out)
	local splats = SPLATS[kind]
	-- each splat is reported once, on the first frame past it
	while splats and st.splats < #splats and u >= splats[st.splats + 1] do
		st.splats += 1
		p.splat = if kind == "drop" then 2 elseif kind == "arrive" then 1.4 else 0.7
	end
	return p
end

return SlimeFidget
