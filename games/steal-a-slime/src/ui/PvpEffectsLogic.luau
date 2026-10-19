--!strict
--[[
	PvpEffectsLogic (pure, FEATURES.PvP, CONTRACT.md §26.1 "Client effects")

	Which visual / sound each PvpEvent `Effect` gets, and the bookkeeping that keeps the client effects transient.
	No Roblox APIs (colors are {r, g, b} 0..1 tables), so Lune tests it; ui/PvpEffects builds the instances.

	  PvpEffectsLogic.plan(payload, pvp, low)      -> Plan? (nil = nothing to show / unknown effect)
	  PvpEffectsLogic.marker(itemId, tool)         -> Marker? (Goo Trap puddle, TrapPlaced)
	  PvpEffectsLogic.markerFor(itemId, tools)      the same, looking the tool up in Config.PVP_TOOLS
	  PvpEffectsLogic.markerVisible(...)           traps only to their owner
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
	ring: boolean?, -- horizontal ring (impact shock wave, goo splash)
	height: number?, -- emit this many studs above the position; on a character, above its root (< 0 = feet)
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
	applyVelocity: boolean, -- the victim's client launches its own root with payload.velocity
	onTarget: boolean, -- emit at the target's character (else at payload.position)
	attackerAnim: boolean, -- the attacker plays the item's use animation (ui/PvpAnim); false for a trap springing
	targetHit: boolean, -- the target plays the `hit` recoil (it was pushed)
}
export type Marker = { shape: "puddle", diameter: number, color: RGB, ownerOnly: boolean, seconds: number? }

PvpEffectsLogic.FX_RANGE = 220 -- studs: farther effects are skipped (clients may skip beyond their stream radius)
PvpEffectsLogic.HIGHLIGHT_CAP = 8 -- Roblox allows ~31 Highlights in total; we stay far below
PvpEffectsLogic.SHAKE_SECONDS = 0.3
PvpEffectsLogic.SHAKE_AMPLITUDE = 0.35 -- studs
PvpEffectsLogic.FLASH_SECONDS = 0.22
PvpEffectsLogic.FEET = -2.6 -- studs below the root: where a goo splash ring sits
PvpEffectsLogic.MISS_BEAM_SECONDS = 0.4

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

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

--[[
	The look of one PvpEvent `Effect` payload (Knockback, Freeze, Slow; the Fun items' effects are ui/PvpFunFx's).
	`pvp` = Config.PVP (FX_SECONDS, CONTROL_MAX_SECONDS, SLOW_MAX_SECONDS). `low` = low graphics quality (fewer
	particles). Durations are clamped: nothing outlives FX_SECONDS except the highlight of a Freeze / Slow (its
	`duration`, at most the server's own cap).
]]
function PvpEffectsLogic.plan(payload: any, pvp: any, low: boolean): Plan?
	if type(payload) ~= "table" then
		return nil
	end
	local effect, itemId, fx = payload.effect, payload.itemId, pvp.FX_SECONDS
	local plan: Plan?
	if effect == "Knockback" then
		local color = TIER_COLORS[PvpEffectsLogic.tierOf(itemId)]
		plan = {
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
			attackerAnim = true,
			targetHit = true,
		}
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
				beam = { seconds = PvpEffectsLogic.FLASH_SECONDS + 0.08, color = GOO, width = 0.9 },
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
	-- Nothing outlives its own `seconds`: the highlight / beam fit inside it.
	local ceiling = plan.seconds
	if plan.highlight then
		plan.highlight.seconds = math.min(plan.highlight.seconds, ceiling)
	end
	if plan.beam then
		plan.beam.seconds = math.min(plan.beam.seconds, ceiling)
	end
	return plan
end

-- The ground marker of a TrapPlaced: nil for items without one.
function PvpEffectsLogic.marker(itemId: any, tool: any): Marker?
	if type(itemId) ~= "string" then
		return nil
	end
	if tool and tool.line == "Trap" and type(tool.radius) == "number" then
		return { shape = "puddle", diameter = tool.radius * 2, color = GOO_DARK, ownerOnly = true, seconds = nil }
	end
	return nil
end

-- The marker of a TrapPlaced `itemId`, its tool looked up by id in `tools` (Config.PVP_TOOLS, a list).
function PvpEffectsLogic.markerFor(itemId: any, tools: { any }): Marker?
	local tool: any = nil
	for _, def in tools do
		if def.id == itemId then
			tool = def
			break
		end
	end
	return PvpEffectsLogic.marker(itemId, tool)
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
