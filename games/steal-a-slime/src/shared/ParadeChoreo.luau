--!strict
--[[
	ParadeChoreo (pure, contract/slime-life.md)

	Small beats on the goo lane: now and then a lane slime stops for a moment
	(looks around, sniffs, naps, does a trick) and then catches up with its
	spot. The plan is a pure function of a seed, the slime's temperament and
	the length of its walk, so the server (position) and the client (pose)
	build the same plan from three model attributes.

	Time t is seconds since the walk starts (the slide mouth,
	spawnedAt + ParadeLane.RIDE_SECONDS). The speed is a multiple m(t) of the
	plain lane pace, piecewise linear between `keys`. A beat is a short
	run-ahead at CATCH_SPEED, a stop (m = 0) and a catch-up at CATCH_SPEED,
	with RAMP-second ramps between; each beat nets out to zero, so the offset
	is 0 between beats and at the end of the walk.

	  ParadeChoreo.seedFor(id) -> number
	  ParadeChoreo.copies(id) -> boolean            a copycat takes the slime ahead's seed
	  ParadeChoreo.plan(seed, temper, walkSeconds, leadSeconds) -> Plan
	  ParadeChoreo.offset(plan, t) -> number        seconds of plain walking ahead (+) or behind (-)
	  ParadeChoreo.speed(plan, t) -> number         m(t)
	  ParadeChoreo.beatAt(plan, t) -> (Beat?, Phase, u)
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local SlimePersona = if script then require(script.Parent.SlimePersona) else require("./SlimePersona")

export type Kind = "look" | "sniff" | "slurp" | "nap" | "trip" | "spin" | "cheer" | "hide" | "zoom" | "huff" | "stuck"
export type Phase = "pre" | "stop" | "post" | "none"

export type Beat = {
	kind: Kind,
	t0: number, -- the beat starts (run-ahead or slow-down)
	s0: number, -- standing still from here
	s1: number, -- ... to here
	e: number, -- back at the plain pace
	stop: number, -- s1 - s0
	pre: boolean, -- an eager beat (runs ahead further first: nap, trip, zoom)
	side: number, -- -1 | 1: which side of the lane a sniff / hide leans to
}

export type Plan = {
	beats: { Beat },
	keys: { { number } }, -- { t, m }, t ascending, m between them linear
	area: { number }, -- integral of (m - 1) from 0 to keys[i].t
}

local ParadeChoreo = {}

ParadeChoreo.CATCH_SPEED = 1.6 -- x the lane pace while running ahead or catching up
ParadeChoreo.RAMP = 0.25 -- seconds for each speed change
ParadeChoreo.LEASH = 1.5 -- most seconds of plain walking a slime gets ahead or behind its spot
ParadeChoreo.QUIET_END = Config.DESPAWN_TELEGRAPH_SECONDS + 2 -- no beat this close to the end of the walk
ParadeChoreo.FIRST_AFTER = 1 -- seconds past the lead-in before the first beat can start
ParadeChoreo.PRE_SHARE = { 0.45, 0.6 } -- run-ahead time as a share of the stop: { calm beat, eager beat (pre) }
ParadeChoreo.COPY_PERCENT = 30 -- copycats among same-species slimes that spawn right behind each other
ParadeChoreo.COPY_WINDOW = Config.SPAWN_INTERVAL * 1.5 -- seconds: "right behind"

-- Per beat: stop seconds { min, max } and whether it is eager (runs ahead further first).
ParadeChoreo.BEATS = table.freeze({
	look = table.freeze({ stop = { 1.4, 2.2 }, pre = false }),
	sniff = table.freeze({ stop = { 1.8, 2.6 }, pre = false }),
	slurp = table.freeze({ stop = { 1.8, 2.6 }, pre = false }),
	nap = table.freeze({ stop = { 2.4, 3.0 }, pre = true }),
	trip = table.freeze({ stop = { 1.2, 1.6 }, pre = true }),
	spin = table.freeze({ stop = { 1.2, 1.5 }, pre = false }),
	cheer = table.freeze({ stop = { 1.2, 1.6 }, pre = false }),
	hide = table.freeze({ stop = { 1.6, 2.4 }, pre = false }),
	zoom = table.freeze({ stop = { 1.4, 2.0 }, pre = true }),
	huff = table.freeze({ stop = { 1.4, 2.0 }, pre = false }),
	stuck = table.freeze({ stop = { 1.5, 1.9 }, pre = false }),
} :: { [string]: { stop: { number }, pre: boolean } })

-- Per temperament: beat weights and the seconds between beats { min, max }.
ParadeChoreo.WEIGHTS = table.freeze({
	Bouncy = { cheer = 3, spin = 2, zoom = 3, look = 1, trip = 2, stuck = 2 },
	Lazy = { nap = 4, slurp = 3, look = 1 },
	Curious = { sniff = 4, look = 4, slurp = 1, cheer = 1, stuck = 1 },
	Shy = { look = 3, hide = 3, sniff = 1 },
	Showoff = { spin = 4, cheer = 3, look = 1 },
	Feisty = { huff = 4, look = 2, zoom = 1, trip = 1 },
} :: { [string]: { [string]: number } })
ParadeChoreo.GAPS = table.freeze({
	Bouncy = { 3, 5.5 },
	Lazy = { 4, 7 },
	Curious = { 3, 5 },
	Shy = { 4, 7 },
	Showoff = { 3.5, 6 },
	Feisty = { 3.5, 6 },
} :: { [string]: { number } })

-- Beat kinds in a fixed order, so a seed picks the same beat everywhere (pairs() order is not stable).
local KINDS: { Kind } = { "look", "sniff", "slurp", "nap", "trip", "spin", "cheer", "hide", "zoom", "huff", "stuck" }
ParadeChoreo.KINDS = table.freeze(KINDS)

ParadeChoreo.SEED_MODULUS = 16777213 -- seeds stay below 2^24: a model attribute carries them exactly even as a float32

function ParadeChoreo.seedFor(id: string): number
	local h = 5381
	for i = 1, #id do
		h = (h * 33 + string.byte(id, i)) % ParadeChoreo.SEED_MODULUS
	end
	return h
end

function ParadeChoreo.copies(id: string): boolean
	return ParadeChoreo.seedFor(id .. "#copy") % 100 < ParadeChoreo.COPY_PERCENT
end

local function pick(roll: number, weights: { [string]: number }): Kind
	local total = 0
	for _, k in KINDS do
		total += weights[k] or 0
	end
	local x = roll * total
	for _, k in KINDS do
		local w = weights[k] or 0
		if w > 0 then
			x -= w
			if x <= 0 then
				return k
			end
		end
	end
	return "look"
end

function ParadeChoreo.plan(seed: number, temper: string?, walkSeconds: number, leadSeconds: number?): Plan
	local rng = Rng.new(seed)
	local t = (if temper and ParadeChoreo.WEIGHTS[temper] then temper else SlimePersona.DEFAULT.temper) :: string
	local weights, gaps = ParadeChoreo.WEIGHTS[t], ParadeChoreo.GAPS[t]
	local r, catch, leash = ParadeChoreo.RAMP, ParadeChoreo.CATCH_SPEED, ParadeChoreo.LEASH
	local up = catch - 1
	local keys: { { number } } = { { 0, 1 } }
	local beats: { Beat } = {}
	local function key(at: number, m: number)
		table.insert(keys, { at, m })
	end
	local last = walkSeconds - ParadeChoreo.QUIET_END
	local at = (leadSeconds or 0) + ParadeChoreo.FIRST_AFTER + gaps[1] * rng:float()
	while true do
		local kind = pick(rng:float(), weights)
		local spec = ParadeChoreo.BEATS[kind]
		local stop = spec.stop[1] + rng:float() * (spec.stop[2] - spec.stop[1])
		local side = if rng:float() < 0.5 then -1 else 1
		-- Every beat runs ahead a little first (that buys a longer stop inside the leash); eager ones more.
		local pre = stop * ParadeChoreo.PRE_SHARE[if spec.pre then 2 else 1]
		-- Keep the lead and the lag inside the leash (the ramps add 0.42 r ahead, 0.22 r / 0.82 r behind).
		pre = math.min(pre, (leash - 0.42 * r) / up)
		stop = math.min(stop, leash + up * pre - (if pre > 0 then 0.22 else 0.82) * r)
		local catchUp, total
		if pre > 0 then
			catchUp = (stop - up * pre - 0.2 * r) / up
			total = r + pre + r + stop + r + catchUp + r
		else
			catchUp = (stop + 0.4 * r) / up
			total = r + stop + r + catchUp + r
		end
		if at + total > last then
			break
		end
		local s0
		if pre > 0 then
			key(at, 1)
			key(at + r, catch)
			key(at + r + pre, catch)
			s0 = at + r + pre + r
		else
			key(at, 1)
			s0 = at + r
		end
		key(s0, 0)
		key(s0 + stop, 0)
		key(s0 + stop + r, catch)
		key(s0 + stop + r + catchUp, catch)
		local e = s0 + stop + r + catchUp + r
		key(e, 1)
		table.insert(beats, {
			kind = kind,
			t0 = at,
			s0 = s0,
			s1 = s0 + stop,
			e = e,
			stop = stop,
			pre = spec.pre,
			side = side,
		})
		at = e + gaps[1] + rng:float() * (gaps[2] - gaps[1])
	end
	key(math.max(walkSeconds, keys[#keys][1]), 1)
	local area = { 0 }
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		area[i] = area[i - 1] + (b[1] - a[1]) * ((a[2] + b[2]) / 2 - 1)
	end
	return { beats = beats, keys = keys, area = area }
end

-- Index of the key segment holding t (keys[i].t <= t < keys[i+1].t), clamped.
local function segment(plan: Plan, t: number): number
	local keys = plan.keys
	local lo, hi = 1, #keys
	if t <= keys[1][1] then
		return 1
	elseif t >= keys[hi][1] then
		return hi
	end
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if keys[mid][1] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

function ParadeChoreo.speed(plan: Plan, t: number): number
	local i = segment(plan, t)
	local a, b = plan.keys[i], plan.keys[i + 1]
	if not b or b[1] <= a[1] then
		return a[2]
	end
	return a[2] + (b[2] - a[2]) * math.clamp((t - a[1]) / (b[1] - a[1]), 0, 1)
end

function ParadeChoreo.offset(plan: Plan, t: number): number
	local i = segment(plan, t)
	local a = plan.keys[i]
	if t <= a[1] or not plan.keys[i + 1] then
		return plan.area[i]
	end
	local m = ParadeChoreo.speed(plan, t)
	return plan.area[i] + (t - a[1]) * ((a[2] + m) / 2 - 1)
end

-- The beat running at t, its phase and how far through that phase (0..1).
function ParadeChoreo.beatAt(plan: Plan, t: number): (Beat?, Phase, number)
	for _, b in plan.beats do
		if t >= b.t0 and t < b.e then
			if t < b.s0 then
				return b, "pre", (t - b.t0) / math.max(b.s0 - b.t0, 1e-6)
			elseif t < b.s1 then
				return b, "stop", (t - b.s0) / math.max(b.stop, 1e-6)
			end
			return b, "post", (t - b.s1) / math.max(b.e - b.s1, 1e-6)
		elseif b.t0 > t then
			break
		end
	end
	return nil, "none", 0
end

return table.freeze(ParadeChoreo)
