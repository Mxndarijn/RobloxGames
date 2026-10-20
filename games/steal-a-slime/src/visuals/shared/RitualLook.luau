--!strict
--[[
	RitualLook (FEATURES.CoopRitual, contract/coop-ritual.md)

	The ritual circle's look, shared by the server parts (server/RitualView: spot and orb colours) and the
	client effects (visuals/client/RitualFx: beams, progress ring, orb motion, completion burst). Pure: no
	Roblox APIs, so the specs run under Lune.

	  ring     fill 0..1 of the ground ring: the HOLD_SECONDS countdown while Charging, the
	           SERVER_COOLDOWN while resting, empty while Idle
	  orb      bob (studs), spin (rad/s) and scale of the orb for a phase and charge
	  shock    radius and transparency of the completion shockwave at progress k (0..1)
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

export type Tint = "idle" | "taken" | "charge" | "rest"

local RitualLook = {}

RitualLook.COLORS = table.freeze({
	idle = table.freeze({ 190, 160, 255 }),
	taken = table.freeze({ 120, 255, 160 }),
	charge = table.freeze({ 255, 226, 120 }),
	rest = table.freeze({ 150, 150, 170 }),
})

-- The rgb colour for a tint.
function RitualLook.color(tint: Tint): { number }
	local c = RitualLook.COLORS
	return if tint == "taken"
		then c.taken
		elseif tint == "charge" then c.charge
		elseif tint == "rest" then c.rest
		else c.idle
end

RitualLook.MAX_DISTANCE = 150 -- studs: further away the effects pause and the emitters stop
RitualLook.RING_SEGMENTS = 24 -- neon dashes round the ground ring
RitualLook.SHOCK_SECONDS = 0.9 -- completion shockwave
RitualLook.FLASH_SECONDS = 0.35 -- completion light flash
RitualLook.BOB = 0.35 -- studs
RitualLook.SPIN = table.freeze({ idle = 0.6, charge = 3.5, rest = 0.15 }) -- rad/s (charge: extra at full charge)
RitualLook.CHARGE_SCALE = 0.35 -- the orb grows by this share at full charge
RitualLook.BEAM_WIDTH = table.freeze({ 0.25, 0.6 }) -- studs: a taken spot, then at full charge

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- How far the charge is (0..1) while Charging, else 0.
function RitualLook.charge(phase: string, chargeEndsAt: number?, now: number): number
	if phase ~= "Charging" or type(chargeEndsAt) ~= "number" then
		return 0
	end
	return clamp01(1 - (chargeEndsAt - now) / Config.RITUAL.HOLD_SECONDS)
end

-- The ground ring: fill 0..1 and its tint.
function RitualLook.ring(phase: string, chargeEndsAt: number?, readyAt: number?, now: number): (number, Tint)
	if phase == "Charging" then
		return RitualLook.charge(phase, chargeEndsAt, now), "charge"
	elseif phase == "Cooldown" and type(readyAt) == "number" then
		return clamp01(1 - (readyAt - now) / Config.RITUAL.SERVER_COOLDOWN), "rest"
	end
	return 0, "idle"
end

-- Orb motion at clock t: bob offset (studs), spin speed (rad/s) and size scale.
function RitualLook.orb(phase: string, charge: number, t: number): (number, number, number)
	local bob = math.sin(t * 1.6) * RitualLook.BOB
	if phase == "Cooldown" then
		return bob * 0.4, RitualLook.SPIN.rest, 1
	elseif phase == "Charging" then
		return bob, RitualLook.SPIN.idle + RitualLook.SPIN.charge * charge, 1 + RitualLook.CHARGE_SCALE * charge
	end
	return bob, RitualLook.SPIN.idle, 1
end

-- Beam width (studs) from a taken spot to the orb.
function RitualLook.beamWidth(charge: number): number
	local w = RitualLook.BEAM_WIDTH
	return w[1] + (w[2] - w[1]) * clamp01(charge)
end

-- Completion shockwave at progress k (0..1): radius (studs) and transparency.
function RitualLook.shock(k: number): (number, number)
	k = clamp01(k)
	local ease = 1 - (1 - k) * (1 - k)
	local from, to = 2, Config.RITUAL.CIRCLE_RADIUS * 2.2
	return from + (to - from) * ease, 0.2 + 0.8 * k
end

-- True when the phase change from `before` to `after` is a finished ritual (not a reset or a cooldown ending).
function RitualLook.completed(before: string?, after: string): boolean
	return before == "Charging" and after == "Cooldown"
end

-- Ring dashes lit for a fill (0..1).
function RitualLook.litSegments(fill: number): number
	return math.floor(clamp01(fill) * RitualLook.RING_SEGMENTS + 0.5)
end

return table.freeze(RitualLook)
