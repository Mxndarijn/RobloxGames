--!strict
--[[
	SlimeLife (TODO v28 #17: slimes feel alive)

	Pure numbers for the client-only idle life of wild and pad slimes:
	squish & bounce, small hops, looking around and a per-rarity wobble and
	sparkle. The Roblox side is SlimeLifeRunner.client.luau; this module has
	no Roblox APIs, so tests/ui/SlimeLife.spec.luau covers it under Lune.

	  SlimeLife.params(tier, state) -> Params   tier 1..7, state "Wild" | "Pad"
	  SlimeLife.eligible(info) -> boolean       state / despawn / distance rule
	  SlimeLife.select(cands, active) -> { [id]: true }
	                                            nearest first, at most MAX_ACTIVE,
	                                            with distance hysteresis
	  SlimeLife.sparkleSet(cands, active) -> { [id]: true }
	                                            at most MAX_SPARKLING, rarest first
	  SlimeLife.newClock(params, now, rand) -> Clock
	  SlimeLife.advance(clock, params, now, rand) -> boolean (true = just landed)
	  SlimeLife.pose(params, clock, now) -> Pose
	                                            offset in Body space: lift (studs,
	                                            times Size), yaw / pitch / roll
	                                            (radians), squash scale sx/sy/sz

	Blinking stays with VisualsClient (Archer), which already blinks every
	tagged slime; this module never touches the eyes.
]]

local SlimeLife = {}

SlimeLife.MAX_ACTIVE = 16 -- rigged slimes at once (nearest first)
SlimeLife.MAX_DISTANCE = 80 -- studs from the camera to start animating
SlimeLife.KEEP_DISTANCE = 95 -- an active slime stays active up to here (no flicker at the edge)
SlimeLife.MAX_SPARKLING = 6 -- sparkle emitters at once (rarest first)
SlimeLife.MAX_TIER = 7 -- Secret
SlimeLife.SPARKLE_LIFETIME = { 0.6, 1.1 } -- seconds, per particle
SlimeLife.SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds" -- built-in, same as Effects SPARK
SlimeLife.MAX_SPARKLES_ALIVE = 16 -- per emitter, same limit as tests/Effects.spec
SlimeLife.STATES = { Wild = true, Pad = true }

-- Hop shape (seconds and squash amounts).
SlimeLife.WINDUP = 0.14 -- squat before take-off
SlimeLife.AIR = 0.42 -- time in the air
SlimeLife.LAND = 0.18 -- squash after landing
SlimeLife.HOP_SQUASH = 0.16
SlimeLife.HOP_STRETCH = 0.1
SlimeLife.LOOK_TIME = 0.35 -- seconds to turn to a new look direction
SlimeLife.SQUASH_LIMIT = { 0.78, 1.22 } -- sy is clamped to this

export type Params = {
	tier: number,
	squishAmp: number, -- idle breathing: sy = 1 - amp * sin
	squishSpeed: number, -- rad / s
	wobble: number, -- roll / pitch amplitude, radians
	wobbleSpeed: number, -- rad / s
	hopEvery: { number }, -- {min, max} seconds between hops
	hopHeight: number, -- studs at Size 1
	lookEvery: { number }, -- {min, max} seconds between look turns
	lookYaw: number, -- max |yaw| of a look, radians
	sparkleRate: number, -- particles / s, 0 = no emitter
	landBurst: number, -- sparkles emitted on landing
}

export type Candidate = {
	id: string,
	distance: number, -- studs to the camera
	state: string?,
	despawning: boolean?,
	tier: number?,
	onScreen: boolean?, -- false = outside the camera view (nil = unknown, counts as visible)
}

export type Clock = {
	phase: number, -- random time offset so slimes don't breathe in step
	hopAt: number, -- take-off time of the next (or current) hop
	landedHop: number?, -- hopAt of the last landing reported by advance
	lookFrom: number,
	lookTo: number,
	lookAt: number, -- start of the current turn
	nextLook: number,
}

export type Pose = {
	lift: number,
	yaw: number,
	pitch: number,
	roll: number,
	sx: number,
	sy: number,
	sz: number,
}

type Rand = () -> number -- uniform [0, 1)

local function clampTier(tier: number?): number
	if type(tier) ~= "number" or tier ~= tier then
		return 1
	end
	return math.clamp(math.floor(tier), 1, SlimeLife.MAX_TIER)
end

local SPARKLE_RATE = { 0, 0, 3, 5, 8, 11, 14 } -- by tier; rate * 1.1 s <= 16 alive
local LAND_BURST = { 0, 0, 0, 4, 6, 8, 10 }

function SlimeLife.params(tier: number?, state: string?): Params
	local t = clampTier(tier)
	local k = t - 1 -- 0 (Common) .. 6 (Secret)
	local pad = state == "Pad"
	local often = 1 - 0.05 * k -- rarer slimes hop a bit more often
	return {
		tier = t,
		squishAmp = 0.035 + 0.008 * k,
		squishSpeed = 2.4 + 0.15 * k,
		wobble = 0.02 + 0.012 * k,
		wobbleSpeed = 3 + 0.3 * k,
		hopEvery = if pad then { 7 * often, 14 * often } else { 4.5 * often, 9 * often },
		hopHeight = if pad then 0.45 else 0.9,
		lookEvery = { 2.5, 6 },
		lookYaw = if pad then 0.45 else 0.6,
		sparkleRate = SPARKLE_RATE[t],
		landBurst = LAND_BURST[t],
	}
end

function SlimeLife.eligible(c: Candidate, wasActive: boolean?): boolean
	if not (c.state and SlimeLife.STATES[c.state]) or c.despawning then
		return false
	end
	if c.onScreen == false then
		return false
	end
	local limit = if wasActive then SlimeLife.KEEP_DISTANCE else SlimeLife.MAX_DISTANCE
	return c.distance == c.distance and c.distance <= limit
end

-- Nearest eligible slimes, at most MAX_ACTIVE. `active` (the previous
-- result) only widens the distance limit; it never beats a nearer slime.
function SlimeLife.select(cands: { Candidate }, active: { [string]: boolean }?): { [string]: boolean }
	local pool = {}
	for _, c in cands do
		if SlimeLife.eligible(c, active ~= nil and active[c.id] == true) then
			table.insert(pool, c)
		end
	end
	table.sort(pool, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(#pool, SlimeLife.MAX_ACTIVE) do
		out[pool[i].id] = true
	end
	return out
end

-- Which active slimes get a sparkle emitter: rarest first, then nearest.
function SlimeLife.sparkleSet(cands: { Candidate }, active: { [string]: boolean }): { [string]: boolean }
	local pool = {}
	for _, c in cands do
		if active[c.id] and SlimeLife.params(c.tier, c.state).sparkleRate > 0 then
			table.insert(pool, c)
		end
	end
	table.sort(pool, function(a, b)
		local ta, tb = clampTier(a.tier), clampTier(b.tier)
		if ta ~= tb then
			return ta > tb
		end
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(#pool, SlimeLife.MAX_SPARKLING) do
		out[pool[i].id] = true
	end
	return out
end

local function between(range: { number }, rand: Rand): number
	return range[1] + rand() * (range[2] - range[1])
end

function SlimeLife.newClock(params: Params, now: number, rand: Rand): Clock
	return {
		phase = rand() * 2 * math.pi,
		-- First hop staggered over a whole interval so a crowd doesn't hop together.
		hopAt = now + rand() * params.hopEvery[2],
		lookFrom = 0,
		lookTo = 0,
		lookAt = now,
		nextLook = now + between(params.lookEvery, rand),
	}
end

local function hopEnd(clock: Clock): number
	return clock.hopAt + SlimeLife.AIR + SlimeLife.LAND
end

-- Moves the schedule on to `now`. Returns true on the frame a hop lands.
function SlimeLife.advance(clock: Clock, params: Params, now: number, rand: Rand): boolean
	local landed = false
	local landAt = clock.hopAt + SlimeLife.AIR
	if now >= landAt and now < hopEnd(clock) and clock.landedHop ~= clock.hopAt then
		clock.landedHop = clock.hopAt
		landed = true
	end
	if now >= hopEnd(clock) then
		-- Skipped frames (slime was off-screen) never queue up several hops.
		clock.hopAt = math.max(clock.hopAt + SlimeLife.AIR + between(params.hopEvery, rand), now + SlimeLife.WINDUP)
	end
	if now >= clock.nextLook then
		clock.lookFrom = SlimeLife.lookYaw(clock, now)
		-- Half the turns look back to the front, so the face is seen often.
		clock.lookTo = if rand() < 0.5 then 0 else (rand() * 2 - 1) * params.lookYaw
		clock.lookAt = now
		clock.nextLook = now + between(params.lookEvery, rand)
	end
	return landed
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

function SlimeLife.lookYaw(clock: Clock, now: number): number
	local u = smooth((now - clock.lookAt) / SlimeLife.LOOK_TIME)
	return clock.lookFrom + (clock.lookTo - clock.lookFrom) * u
end

-- Hop lift (studs at Size 1) and extra vertical squash (+ = flatter) at `now`.
function SlimeLife.hop(params: Params, clock: Clock, now: number): (number, number)
	local dt = now - clock.hopAt
	if dt < -SlimeLife.WINDUP then
		return 0, 0
	elseif dt < 0 then
		return 0, SlimeLife.HOP_SQUASH * smooth((dt + SlimeLife.WINDUP) / SlimeLife.WINDUP)
	elseif dt < SlimeLife.AIR then
		local u = dt / SlimeLife.AIR
		local lift = 4 * params.hopHeight * u * (1 - u)
		-- Stretch tall on the way up, back to round at the top.
		return lift, -SlimeLife.HOP_STRETCH * math.max(0, 1 - 2 * u)
	elseif dt < SlimeLife.AIR + SlimeLife.LAND then
		local u = (dt - SlimeLife.AIR) / SlimeLife.LAND
		return 0, SlimeLife.HOP_SQUASH * (1 - smooth(u))
	end
	return 0, 0
end

-- Idle breathing only, scaled by `amp` (the LOD mid tier): the sy of pose() without hop or wobble.
function SlimeLife.squishY(params: Params, clock: Clock, now: number, amp: number): number
	local squash = math.sin((now + clock.phase) * params.squishSpeed) * params.squishAmp * amp
	return math.clamp(1 - squash, SlimeLife.SQUASH_LIMIT[1], SlimeLife.SQUASH_LIMIT[2])
end

-- `out` (optional) is filled and returned instead of a new table, so a per-frame caller allocates nothing.
function SlimeLife.pose(params: Params, clock: Clock, now: number, out: Pose?): Pose
	local t = now + clock.phase
	local lift, hopSquash = SlimeLife.hop(params, clock, now)
	local squash = math.sin(t * params.squishSpeed) * params.squishAmp + hopSquash
	local sy = math.clamp(1 - squash, SlimeLife.SQUASH_LIMIT[1], SlimeLife.SQUASH_LIMIT[2])
	-- Keep the volume roughly constant: flatter = wider.
	local sxz = 1 / math.sqrt(sy)
	local pose: Pose = out or {} :: any
	pose.lift = lift
	pose.yaw = SlimeLife.lookYaw(clock, now)
	pose.pitch = math.sin(t * params.wobbleSpeed * 0.7 + 1) * params.wobble * 0.6
	pose.roll = math.sin(t * params.wobbleSpeed) * params.wobble
	pose.sx = sxz
	pose.sy = sy
	pose.sz = sxz
	return pose
end

return SlimeLife
