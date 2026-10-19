--!strict
--[[
	PvpEffectsLogic (pure, FEATURES.PvP, CONTRACT.md §26.1 "Client effects")

	Which visual / sound each PvpEvent `Effect` gets, and the bookkeeping that keeps the client effects transient.
	No Roblox APIs (colors are {r, g, b} 0..1 tables), so Lune tests it; ui/PvpEffects builds the instances.

	  PvpEffectsLogic.plan(payload, pvp, low)      -> Plan? (nil = nothing to show / unknown effect)
	  PvpEffectsLogic.marker(itemId, tool, pvp)    -> Marker? (Goo Trap puddle / Bounce Pad disc, TrapPlaced)
	  PvpEffectsLogic.markerFor(itemId, tools, pvp) the same, looking the tool up in Config.PVP_TOOLS
	  PvpEffectsLogic.markerLook(marker, isOwner)  a trap glows for its owner and is a faint shimmer for everyone else
	  PvpEffectsLogic.blobVelocity(from, to, t, g)  the start velocity of the goo blob particle (the server's arc)
	  PvpEffectsLogic.pogoTimes(heights, g)        when each Bounce Glove pogo lands (the next bounce starts there)
	  PvpEffectsLogic.shakeOffset(t, seconds, amp) -> x, y camera offset (decaying)
	  PvpEffectsLogic.scaleCount(n, low)           particle counts at low graphics quality
	  PvpEffectsLogic.tracker()                    acquire / release counters (activeCount() must end at 0)
]]

local PvpEffectsLogic = {}

export type RGB = { number }
export type Burst = {
	count: number,
	colors: { RGB },
	texture: string?,
	speed: number, -- studs/s
	size: number,
	lift: number, -- upward acceleration (balloons / bubbles float up), negative = falls
	ring: boolean?, -- horizontal ring (Bounce)
	height: number?, -- emit this many studs above the position (Fireworks); on a character, above its root (< 0 = feet)
}
export type Plan = {
	effect: string,
	seconds: number, -- every instance of this effect is gone by now
	sfx: string?,
	burst: Burst?,
	ring: Burst?, -- a second, flat ring burst (impact shock wave, goo splash)
	highlight: { color: RGB, seconds: number, impact: RGB? }?, -- impact = the colour of the first instant
	beam: { seconds: number, color: RGB, width: number? }?,
	shake: { amplitude: number, seconds: number }?, -- victim only
	trail: number?, -- seconds (Bounce)
	applyVelocity: boolean, -- the victim's client launches its own root with payload.velocity
	onTarget: boolean, -- emit at the target's character (else at payload.position)
	attackerAnim: boolean, -- the attacker plays the item's use animation (ui/PvpAnim); false for traps / pads springing
	targetHit: boolean, -- the target plays the `hit` recoil (it was pushed)
	popup: { text: string, color: RGB, seconds: number }?, -- a word over the target ("BONK!", "CHOMP!")
	bolt: { color: RGB, seconds: number }?, -- lightning from payload.from to the target (Thunder Glove chain)
	pogo: { number }?, -- the victim's client bounces this high after the push (Bounce Glove), each studs
	blob: { size: number, color: RGB }?, -- the flying goo blob (payload from / to / flight)
	delay: number?, -- seconds the impact waits for the blob to land
	splat: { radius: number, seconds: number, color: RGB }?, -- goo left on the ground at payload.position
	screenSplat: number?, -- seconds of goo on the edge of the victim's screen
}
export type Marker = {
	shape: "puddle" | "pad",
	diameter: number,
	color: RGB,
	ownerOnly: boolean,
	seconds: number?,
	glows: boolean?, -- a trap: glowing for its owner, a faint shimmer for everyone else (markerLook)
}
export type MarkerLook = { transparency: number, material: string }

PvpEffectsLogic.FX_RANGE = 220 -- studs: farther effects are skipped (clients may skip beyond their stream radius)
PvpEffectsLogic.HIGHLIGHT_CAP = 8 -- Roblox allows ~31 Highlights in total; we stay far below
PvpEffectsLogic.SHAKE_SECONDS = 0.3
PvpEffectsLogic.SHAKE_AMPLITUDE = 0.35 -- studs
PvpEffectsLogic.FLASH_SECONDS = 0.22
PvpEffectsLogic.FEET = -2.6 -- studs below the root: where a goo splash ring sits
PvpEffectsLogic.MISS_BEAM_SECONDS = 0.4
PvpEffectsLogic.BOUNCE_TRAIL_SECONDS = 0.6
PvpEffectsLogic.POPUP_SECONDS = 0.8
PvpEffectsLogic.BOLT_SECONDS = 0.3
PvpEffectsLogic.MAX_FLIGHT = 2 -- seconds: a blob never flies longer (junk payloads)
PvpEffectsLogic.MAX_SPLAT_SECONDS = 6 -- a ground splat / pool never lasts longer
PvpEffectsLogic.MAX_POGO = 3 -- bounces
PvpEffectsLogic.BLOB_SIZES = table.freeze({ 1, 1.3, 2.4 }) -- Squirter, Blaster, Cannon (studs)
PvpEffectsLogic.MARKER_OWNER = table.freeze({ transparency = 0.25, material = "Neon" })
PvpEffectsLogic.MARKER_OTHERS = table.freeze({ transparency = 0.88, material = "Glass" })

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local WHITE: RGB = { 1, 1, 1 }
local GOO: RGB = { 0.35, 0.9, 0.3 }
local GOO_DARK: RGB = { 0.2, 0.7, 0.2 }
local TIER_COLORS: { RGB } = {
	{ 1, 1, 1 },
	{ 0.6, 0.9, 1 },
	{ 1, 0.85, 0.3 },
	{ 1, 0.55, 0.2 },
	{ 1, 0.35, 0.7 },
}
local CONFETTI: { RGB } = { { 1, 0.3, 0.4 }, { 1, 0.85, 0.2 }, { 0.3, 0.8, 1 }, { 0.5, 1, 0.4 }, { 0.8, 0.4, 1 } }
local GOLD: RGB = { 1, 0.85, 0.23 }
local GOLD_CONFETTI: { RGB } = { GOLD, { 1, 0.95, 0.6 }, { 0.95, 0.7, 0.15 } }
local BOLT: RGB = { 1, 0.95, 0.35 }
local BOOM: RGB = { 1, 0.55, 0.15 }

local function clampSeconds(d: any, lo: number, hi: number): number
	if type(d) ~= "number" or d ~= d then
		return hi
	end
	return math.clamp(d, lo, hi)
end
PvpEffectsLogic.clampSeconds = clampSeconds

function PvpEffectsLogic.scaleCount(n: number, low: boolean): number
	return math.max(1, if low then math.floor(n / 2) else n)
end

-- "KnockGlove3" -> 3 (1..5), else 1.
function PvpEffectsLogic.tierOf(itemId: string?): number
	local n = if itemId then tonumber(string.match(itemId, "(%d+)$")) else nil
	return math.clamp(n or 1, 1, #TIER_COLORS)
end

-- A decaying shake offset at `t` seconds into a `seconds` long shake (0 outside it). Deterministic.
function PvpEffectsLogic.shakeOffset(t: number, seconds: number, amplitude: number): (number, number)
	if seconds <= 0 or t < 0 or t >= seconds then
		return 0, 0
	end
	local k = (1 - t / seconds)
	k = k * k * amplitude
	return math.sin(t * 90) * k, math.cos(t * 70) * k
end

local function cosmetic(itemId: string, pvp: any, duration: any): Plan
	local plan: Plan = {
		effect = "Cosmetic",
		seconds = pvp.FX_SECONDS,
		sfx = "PvpPop",
		burst = { count = 30, colors = CONFETTI, texture = SPARK, speed = 18, size = 0.5, lift = -20 },
		applyVelocity = false,
		onTarget = false,
		attackerAnim = true,
		targetHit = false,
	}
	local burst = plan.burst :: Burst
	if itemId == "FunBalloon" then
		plan.burst = {
			count = 10,
			colors = { { 1, 0.35, 0.5 }, { 0.4, 0.7, 1 } },
			texture = SMOKE,
			speed = 6,
			size = 1.6,
			lift = 14,
		}
	elseif itemId == "FunBubbles" then
		plan.sfx = "PvpBubble"
		plan.burst =
			{ count = 16, colors = { { 0.7, 0.9, 1 }, WHITE }, texture = SMOKE, speed = 5, size = 1.0, lift = 6 }
	elseif itemId == "FunHatLauncher" then
		plan.burst = {
			count = 14,
			colors = { { 1, 0.85, 0.2 }, { 1, 0.55, 0.2 } },
			texture = SPARK,
			speed = 14,
			size = 0.7,
			lift = -10,
		}
	elseif itemId == "FunFireworks" then
		plan.sfx = "PvpFirework"
		plan.seconds = clampSeconds(duration, pvp.FX_SECONDS, pvp.FIREWORKS_SECONDS)
		plan.burst = { count = 60, colors = CONFETTI, texture = FIRE, speed = 30, size = 0.8, lift = -12, height = 12 }
	elseif itemId == "FunSqueaky" then
		plan.sfx = "PvpSqueak"
		plan.onTarget = true
		plan.applyVelocity = true
		plan.targetHit = true
		plan.burst = { count = 8, colors = { { 1, 0.9, 0.3 } }, texture = SPARK, speed = 8, size = 0.5, lift = 0 }
	else
		plan.burst = burst -- FunConfetti and unknown cosmetics: the default confetti
	end
	return plan
end

--[[
	The look of one PvpEvent `Effect` payload. `pvp` = Config.PVP (FX_SECONDS, CONTROL_MAX_SECONDS, SLOW_MAX_SECONDS,
	FIREWORKS_SECONDS). `low` = low graphics quality (fewer particles). Durations are clamped: nothing outlives
	FX_SECONDS except the highlight of a Freeze / Slow / Dance (its `duration`, at most the server's own cap) and Fireworks.
]]
function PvpEffectsLogic.plan(payload: any, pvp: any, low: boolean): Plan?
	if type(payload) ~= "table" then
		return nil
	end
	local effect, itemId, fx = payload.effect, payload.itemId, pvp.FX_SECONDS
	local plan: Plan?
	if effect == "Knockback" then
		local color = TIER_COLORS[PvpEffectsLogic.tierOf(itemId)]
		local knock: Plan = {
			effect = "Knockback",
			seconds = fx,
			sfx = "PvpHit",
			burst = { count = 16, colors = { color, WHITE }, texture = SPARK, speed = 18, size = 0.8, lift = 0 },
			ring = {
				count = 12,
				colors = { WHITE, color },
				texture = SPARK,
				speed = 24,
				size = 0.6,
				lift = 0,
				ring = true,
			},
			highlight = { color = color, seconds = PvpEffectsLogic.FLASH_SECONDS, impact = WHITE },
			shake = { amplitude = PvpEffectsLogic.SHAKE_AMPLITUDE, seconds = PvpEffectsLogic.SHAKE_SECONDS },
			applyVelocity = true,
			onTarget = true,
			attackerAnim = payload.chained ~= true,
			targetHit = true,
		}
		PvpEffectsLogic.special(knock, payload, pvp)
		plan = knock
	elseif effect == "Freeze" then
		local seconds = clampSeconds(payload.duration, 0.1, pvp.CONTROL_MAX_SECONDS)
		plan = {
			effect = "Freeze",
			seconds = math.max(fx, seconds),
			sfx = "PvpGoo",
			burst = { count = 18, colors = { GOO, GOO_DARK }, texture = SMOKE, speed = 12, size = 1.2, lift = -6 },
			ring = {
				count = 14,
				colors = { GOO, GOO_DARK },
				texture = SMOKE,
				speed = 14,
				size = 1.4,
				lift = -4,
				ring = true,
				height = PvpEffectsLogic.FEET,
			},
			highlight = { color = GOO, seconds = seconds, impact = WHITE },
			applyVelocity = false,
			onTarget = true,
			attackerAnim = false,
			targetHit = false,
		}
		local freeze = plan :: Plan
		if itemId == "GooTrap3" then
			freeze.popup = { text = "CHOMP!", color = GOO, seconds = PvpEffectsLogic.POPUP_SECONDS }
			if freeze.burst then
				freeze.burst.count *= 2
			end
		elseif type(payload.hold) == "number" and payload.hold <= 0 then
			freeze.burst = nil -- a Puddle: goo on the feet only
		end
	elseif effect == "Slow" and type(payload.from) ~= "nil" then
		plan = PvpEffectsLogic.blobPlan(payload, pvp)
	elseif effect == "Slow" then
		local hit = payload.target ~= nil
		local seconds = clampSeconds(payload.duration, 0.1, pvp.SLOW_MAX_SECONDS)
		if hit then
			plan = {
				effect = "Slow",
				seconds = math.max(fx, seconds),
				sfx = "PvpSquirt",
				burst = { count = 16, colors = { GOO, GOO_DARK }, texture = SMOKE, speed = 12, size = 1.1, lift = -10 },
				ring = { count = 10, colors = { GOO }, texture = SMOKE, speed = 16, size = 0.9, lift = -6, ring = true },
				highlight = { color = GOO, seconds = seconds, impact = WHITE },
				-- a splash / pool victim was not shot at: no beam from the shooter's hand
				beam = if payload.splash == true
					then nil
					else { seconds = PvpEffectsLogic.FLASH_SECONDS + 0.08, color = GOO, width = 0.9 },
				applyVelocity = false,
				onTarget = true,
				attackerAnim = true,
				targetHit = false,
			}
		else
			plan = {
				effect = "Slow",
				seconds = PvpEffectsLogic.MISS_BEAM_SECONDS,
				sfx = "PvpSquirt",
				beam = { seconds = PvpEffectsLogic.MISS_BEAM_SECONDS, color = GOO, width = 0.7 },
				applyVelocity = false,
				onTarget = false,
				attackerAnim = true,
				targetHit = false,
			}
		end
	elseif effect == "Dance" then
		local seconds = clampSeconds(payload.duration, 0.1, pvp.CONTROL_MAX_SECONDS)
		plan = {
			effect = "Dance",
			seconds = math.max(fx, seconds),
			sfx = "PvpPop",
			burst = { count = 20, colors = CONFETTI, texture = SPARK, speed = 10, size = 0.6, lift = 4 },
			highlight = { color = { 1, 0.7, 0.95 }, seconds = seconds },
			applyVelocity = false,
			onTarget = true,
			attackerAnim = true,
			targetHit = false,
		}
	elseif effect == "Bounce" then
		plan = {
			effect = "Bounce",
			seconds = math.max(fx, PvpEffectsLogic.BOUNCE_TRAIL_SECONDS),
			sfx = "PvpBoing",
			burst = {
				count = 12,
				colors = { WHITE, { 0.8, 0.95, 1 } },
				texture = SMOKE,
				speed = 14,
				size = 1.0,
				lift = 0,
				ring = true,
			},
			trail = PvpEffectsLogic.BOUNCE_TRAIL_SECONDS,
			applyVelocity = true,
			onTarget = true,
			attackerAnim = false,
			targetHit = true,
		}
	elseif effect == "Cosmetic" then
		plan = cosmetic(type(itemId) == "string" and itemId or "", pvp, payload.duration)
	end
	if not plan then
		return nil
	end
	if plan.burst and plan.burst.count > 0 then
		plan.burst.count = PvpEffectsLogic.scaleCount(plan.burst.count, low)
	end
	if plan.ring then
		plan.ring.count = PvpEffectsLogic.scaleCount(plan.ring.count, low)
	end
	-- Nothing outlives its own `seconds`: the highlight / trail / beam fit inside it.
	local ceiling = plan.seconds
	if plan.highlight then
		plan.highlight.seconds = math.min(plan.highlight.seconds, ceiling)
	end
	if plan.trail then
		plan.trail = math.min(plan.trail, ceiling)
	end
	if plan.beam then
		plan.beam.seconds = math.min(plan.beam.seconds, ceiling)
	end
	return plan
end

-- Knockback specials (payload.special): the BONK! popup, the pogo, the boom ring, the lightning, the gold confetti;
-- a power punch (payload.charged) is bigger. Mutates `plan`.
function PvpEffectsLogic.special(plan: Plan, payload: any, pvp: any)
	local special = payload.special
	if payload.charged == true then
		if plan.burst then
			plan.burst.count = math.floor(plan.burst.count * 1.5)
			plan.burst.speed *= 1.3
		end
		if plan.shake then
			plan.shake.amplitude *= 1.5
		end
	end
	if special == "bonk" then
		plan.popup = { text = "BONK!", color = GOLD, seconds = PvpEffectsLogic.POPUP_SECONDS }
	elseif special == "bounce" and type(payload.pogo) == "table" then
		local heights = {}
		for i, h in payload.pogo do
			if i > PvpEffectsLogic.MAX_POGO then
				break
			end
			if type(h) == "number" and h == h and h > 0 then
				table.insert(heights, math.min(h, pvp.KNOCKBACK_ARC_HEIGHT))
			end
		end
		plan.pogo = if #heights > 0 then heights else nil
		plan.sfx = "PvpBoing"
	elseif special == "boom" then
		plan.ring = {
			count = 24,
			colors = { BOOM, WHITE },
			texture = FIRE,
			speed = 34,
			size = 1.1,
			lift = 0,
			ring = true,
		}
	elseif special == "thunder" then
		if plan.burst then
			plan.burst.colors = { BOLT, WHITE }
		end
		if payload.chained == true then
			plan.bolt = { color = BOLT, seconds = PvpEffectsLogic.BOLT_SECONDS }
		end
	elseif special == "royal" then
		plan.burst = { count = 40, colors = GOLD_CONFETTI, texture = SPARK, speed = 22, size = 0.7, lift = -14 }
	end
end

-- The look of one goo blob (an Effect "Slow" with `from`): the blob flies `flight` seconds, then splats on its
-- target (goo on the victim's screen edge, a green tint) or on the ground (a splat / pool for its seconds).
function PvpEffectsLogic.blobPlan(payload: any, pvp: any): Plan
	local tier = PvpEffectsLogic.tierOf(payload.itemId)
	local flight = clampSeconds(payload.flight, 0, PvpEffectsLogic.MAX_FLIGHT)
	local hit = payload.target ~= nil
	local seconds = clampSeconds(payload.duration, 0.1, pvp.SLOW_MAX_SECONDS)
	local plan: Plan = {
		effect = "Slow",
		seconds = flight + math.max(pvp.FX_SECONDS, if hit then seconds else 0),
		sfx = "PvpSquirt",
		burst = { count = 14, colors = { GOO, GOO_DARK }, texture = SMOKE, speed = 12, size = 1.1, lift = -10 },
		ring = { count = 10, colors = { GOO }, texture = SMOKE, speed = 16, size = 0.9, lift = -6, ring = true },
		highlight = if hit then { color = GOO, seconds = seconds, impact = WHITE } else nil,
		applyVelocity = false,
		onTarget = hit,
		attackerAnim = true,
		targetHit = false,
		blob = { size = PvpEffectsLogic.BLOB_SIZES[tier] or 1, color = GOO },
		delay = flight,
		screenSplat = if hit then seconds else nil,
	}
	local splat = payload.splat
	if type(splat) == "table" and type(splat.radius) == "number" and splat.radius == splat.radius then
		local lasts = clampSeconds(splat.seconds, 0.5, PvpEffectsLogic.MAX_SPLAT_SECONDS)
		plan.splat = { radius = math.clamp(splat.radius, 0.5, 12), seconds = lasts, color = GOO_DARK }
		plan.seconds = math.max(plan.seconds, flight + lasts)
	end
	return plan
end

-- Start velocity of a particle that leaves `from` and is at `to` after `t` seconds under gravity `g` (studs/s^2):
-- the same arc the server tested (PvpBlasterRules.arc).
function PvpEffectsLogic.blobVelocity(from: any, to: any, t: number, g: number): { X: number, Y: number, Z: number }
	local time = math.max(t, 0.05)
	return {
		X = (to.X - from.X) / time,
		Y = (to.Y - from.Y) / time + 0.5 * g * time,
		Z = (to.Z - from.Z) / time,
	}
end

-- Seconds after the push at which each pogo bounce starts: a bounce of height h lasts 2 * sqrt(2 h / g).
function PvpEffectsLogic.pogoTimes(heights: { number }, g: number): { number }
	local out = {}
	local t = 0
	for i, h in heights do
		if i > 1 then
			table.insert(out, t)
		end
		t += 2 * math.sqrt(2 * math.max(h, 0) / math.max(g, 1))
	end
	return out
end

-- How a placed trap looks to this client: glowing for its owner, a faint shimmer for everyone else.
function PvpEffectsLogic.markerLook(marker: Marker, isOwner: boolean): MarkerLook
	if not marker.glows then
		return { transparency = 0.4, material = "SmoothPlastic" }
	end
	return if isOwner then PvpEffectsLogic.MARKER_OWNER else PvpEffectsLogic.MARKER_OTHERS
end

-- The ground marker of a TrapPlaced: nil for items without one.
function PvpEffectsLogic.marker(itemId: any, tool: any, pvp: any): Marker?
	if type(itemId) ~= "string" then
		return nil
	end
	if itemId == "FunBouncePad" then
		return {
			shape = "pad",
			diameter = pvp.BOUNCE_PAD_RADIUS * 2,
			color = { 1, 0.4, 0.8 },
			ownerOnly = false,
			seconds = pvp.BOUNCE_PAD_SECONDS + 2,
		}
	end
	if tool and tool.line == "Trap" and type(tool.radius) == "number" then
		return {
			shape = "puddle",
			diameter = tool.radius * 2,
			color = GOO_DARK,
			ownerOnly = false,
			seconds = pvp.TRAP_LIFETIME_SECONDS + 2,
			glows = true,
		}
	end
	return nil
end

-- The marker of a TrapPlaced `itemId`, its tool looked up by id in `tools` (Config.PVP_TOOLS, a list).
function PvpEffectsLogic.markerFor(itemId: any, tools: { any }, pvp: any): Marker?
	local tool: any = nil
	for _, def in tools do
		if def.id == itemId then
			tool = def
			break
		end
	end
	return PvpEffectsLogic.marker(itemId, tool, pvp)
end

function PvpEffectsLogic.markerVisible(marker: Marker, ownerUserId: number, localUserId: number): boolean
	return not marker.ownerOnly or ownerUserId == localUserId
end

function PvpEffectsLogic.inRange(distance: number): boolean
	return distance == distance and distance <= PvpEffectsLogic.FX_RANGE
end

-- Live-instance counters per kind. activeCount() is what the probe asserts to be 0 after the effects ended.
function PvpEffectsLogic.tracker()
	local counts: { [string]: number } = {}
	local self = {}
	function self.acquire(kind: string)
		counts[kind] = (counts[kind] or 0) + 1
	end
	function self.release(kind: string)
		local n = (counts[kind] or 0) - 1
		counts[kind] = if n > 0 then n else nil
	end
	function self.count(kind: string?): number
		if kind then
			return counts[kind] or 0
		end
		local total = 0
		for _, n in counts do
			total += n
		end
		return total
	end
	return self
end

return PvpEffectsLogic
