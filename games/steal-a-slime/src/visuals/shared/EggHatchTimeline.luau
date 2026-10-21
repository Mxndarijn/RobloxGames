--!strict
--[[
	EggHatchTimeline (pure, contract/mystery-egg.md §40.6)

	The Mystery Egg hatch show as functions of `t`, the seconds since the
	hatch (server time, so every viewer sees the same moment). Client
	EggHatchFx draws from it:
	  wobble 0 .. WOBBLE_END    three rocks, each harder; the glow climbs the rarity colours
	  hold   WOBBLE_END .. BURST   a fast shiver, full glow (a lucky hatch flashes gold)
	  burst  BURST              the shell breaks into shards, flash, ring, sparks
	  pop    BURST .. REVEAL    the slime springs up from tiny with an overshoot
	  reveal REVEAL .. END      the rarity title floats up; the label is back
	No Roblox APIs; numbers and tables only.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

local EggHatchTimeline = {}

EggHatchTimeline.WOBBLES = 3
EggHatchTimeline.WOBBLE_END = 1.5
EggHatchTimeline.BURST = 2
EggHatchTimeline.REVEAL = Config.MYSTERY_EGG.HATCH_REVEAL_SECONDS
EggHatchTimeline.END = 4.5
EggHatchTimeline.HIDDEN_SCALE = 0.02 -- the slime's scale (x its own) until the burst
EggHatchTimeline.SHARDS = 8
EggHatchTimeline.BEAM_TIER = 4 -- Epic and up get a light pillar

export type Phase = "wobble" | "hold" | "pop" | "reveal" | "done"

function EggHatchTimeline.phase(t: number): Phase
	if t < EggHatchTimeline.WOBBLE_END then
		return "wobble"
	elseif t < EggHatchTimeline.BURST then
		return "hold"
	elseif t < EggHatchTimeline.REVEAL then
		return "pop"
	elseif t < EggHatchTimeline.END then
		return "reveal"
	end
	return "done"
end

-- Which wobble (1..WOBBLES) is playing at `t`, or nil outside the wobble phase.
function EggHatchTimeline.wobble(t: number): number?
	if t < 0 or t >= EggHatchTimeline.WOBBLE_END then
		return nil
	end
	local each = EggHatchTimeline.WOBBLE_END / EggHatchTimeline.WOBBLES
	return math.floor(t / each) + 1
end

-- Rock of the egg at `t` (radians; tilt about its base): wobbles grow 7°, 14°, 21°, then a quick shiver.
function EggHatchTimeline.tilt(t: number): number
	local n = EggHatchTimeline.wobble(t)
	if n then
		local each = EggHatchTimeline.WOBBLE_END / EggHatchTimeline.WOBBLES
		local local01 = (t - (n - 1) * each) / each
		return math.rad(7 * n) * math.sin(local01 * math.pi * 2)
	elseif t >= EggHatchTimeline.WOBBLE_END and t < EggHatchTimeline.BURST then
		return math.rad(3) * math.sin(t * math.pi * 2 * 14)
	end
	return 0
end

-- The rarity tiers the glow climbs: from the kind's lowest drop up to the hatched tier (one entry at least).
function EggHatchTimeline.steps(lowest: number, tier: number): { number }
	local out = {}
	for step = math.min(lowest, tier), tier do
		table.insert(out, step)
	end
	return out
end

-- The tier whose colour the glow shows at `t`: wobble k stops k thirds of the way up `steps`, then the top.
function EggHatchTimeline.glowTier(t: number, steps: { number }): number
	local n = EggHatchTimeline.wobble(t)
	if n == nil then
		return steps[#steps]
	end
	local index = 1 + math.floor((#steps - 1) * (n - 1) / EggHatchTimeline.WOBBLES + 0.5)
	return steps[math.clamp(index, 1, #steps)]
end

-- Glow brightness at `t`: builds through the wobbles, peaks in the hold, gone after the burst.
function EggHatchTimeline.glow(t: number): number
	if t < 0 or t >= EggHatchTimeline.BURST then
		return 0
	elseif t < EggHatchTimeline.WOBBLE_END then
		return 0.6 + 2.4 * t / EggHatchTimeline.WOBBLE_END
	end
	return 4
end

-- Whether a lucky hatch flashes gold at `t` (a beat in the hold).
function EggHatchTimeline.luckyFlash(t: number): boolean
	return t >= 1.7 and t < 1.85
end

-- The slime's scale (x its own) at `t`: tiny until the burst, then up past full size and back.
function EggHatchTimeline.slimeScale(t: number): number
	if t < EggHatchTimeline.BURST then
		return EggHatchTimeline.HIDDEN_SCALE
	end
	local u = (t - EggHatchTimeline.BURST) / (EggHatchTimeline.REVEAL - EggHatchTimeline.BURST)
	if u >= 1 then
		return 1
	elseif u < 0.5 then
		local k = u / 0.5
		return EggHatchTimeline.HIDDEN_SCALE + (1.25 - EggHatchTimeline.HIDDEN_SCALE) * (1 - (1 - k) ^ 3)
	elseif u < 0.8 then
		local k = (u - 0.5) / 0.3
		return 1.25 + (0.92 - 1.25) * k
	end
	local k = (u - 0.8) / 0.2
	return 0.92 + (1 - 0.92) * k
end

-- Offset (studs, egg-local: x, y up, z) of shard `i` of `n`, `s` seconds after the burst: an arc out and down.
function EggHatchTimeline.shard(i: number, n: number, s: number): (number, number, number)
	local angle = (i - 1) / n * math.pi * 2 + 0.3 * (i % 2)
	local out = 4 + 1.5 * ((i * 7) % 3)
	local up = 7 + 2 * ((i * 5) % 2)
	local x = math.cos(angle) * out * s
	local z = math.sin(angle) * out * s
	local y = 1.5 + up * s - 0.5 * 30 * s * s
	return x, math.max(y, 0.2), z
end

-- How long the shards fly after the burst.
EggHatchTimeline.SHARD_SECONDS = 0.9

-- The title over the hatched slime: "LEGENDARY!", "LUCKY! MYTHIC!".
function EggHatchTimeline.title(tier: number, lucky: boolean): string
	local name = string.upper(Config.RARITIES[math.clamp(tier, 1, Config.MAX_TIER)].name)
	return if lucky then `LUCKY! {name}!` else `{name}!`
end

-- Title rise (studs above its start) and transparency at `t`; nil before the burst or after the end.
function EggHatchTimeline.titleLook(t: number): (number?, number?)
	if t < EggHatchTimeline.BURST + 0.3 or t >= EggHatchTimeline.END then
		return nil, nil
	end
	local u = (t - EggHatchTimeline.BURST - 0.3) / (EggHatchTimeline.END - EggHatchTimeline.BURST - 0.3)
	local fade = if u < 0.7 then 0 else (u - 0.7) / 0.3
	return 1.5 * u, fade
end

-- Light pillar transparency at `t` for a hatch of `tier` (nil = no pillar now).
function EggHatchTimeline.beam(t: number, tier: number): number?
	if tier < EggHatchTimeline.BEAM_TIER or t < EggHatchTimeline.BURST or t >= EggHatchTimeline.END then
		return nil
	end
	local u = (t - EggHatchTimeline.BURST) / (EggHatchTimeline.END - EggHatchTimeline.BURST)
	return 0.55 + 0.45 * u
end

-- Field of view offset (degrees, subtract) for the hatching owner's camera at `t`: eases in over the hold.
function EggHatchTimeline.zoom(t: number): number
	if t < EggHatchTimeline.WOBBLE_END or t >= EggHatchTimeline.REVEAL + 0.6 then
		return 0
	elseif t < EggHatchTimeline.BURST then
		return 5 * (t - EggHatchTimeline.WOBBLE_END) / (EggHatchTimeline.BURST - EggHatchTimeline.WOBBLE_END)
	elseif t < EggHatchTimeline.REVEAL then
		return 5
	end
	return 5 * (1 - (t - EggHatchTimeline.REVEAL) / 0.6)
end

return table.freeze(EggHatchTimeline)
