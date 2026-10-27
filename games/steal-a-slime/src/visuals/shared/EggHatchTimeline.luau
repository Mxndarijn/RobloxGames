--!strict
--[[
	EggHatchTimeline (pure, contract/mystery-egg.md §40.6)

	The Mystery Egg hatch show as numbers. Two clocks:
	  * egg time `t`: seconds since the hatch (server time, the egg model's HatchedAt). The server keeps the egg
	    on the pad until BURST, so every viewer already has it:
	      wobble 0 .. WOBBLE_END   three rocks with a hop, each harder; a new set of glowing cracks per rock;
	                               the glow climbs the rarity colours up to the tier inside
	      hold   WOBBLE_END .. BURST   the egg swells and shakes, glow at full (a lucky hatch flashes gold)
	      burst  BURST             shards, a lid, a flash, a ring and sparks in the rarity colour
	  * pop time `s`: seconds since the hatched slime's model reached this client (it can lag): the slime springs
	    up from tiny with an overshoot over POP_SECONDS, then the rarity title floats up for TITLE_SECONDS.
	No Roblox APIs; numbers and tables only.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

local EggHatchTimeline = {}

EggHatchTimeline.WOBBLES = 3
EggHatchTimeline.WOBBLE_END = 2.3
EggHatchTimeline.BURST = Config.MYSTERY_EGG.HATCH_BURST_SECONDS
EggHatchTimeline.POP_SECONDS = 0.7
EggHatchTimeline.TITLE_SECONDS = 2.6
EggHatchTimeline.LATE = 3 -- a slime that reaches a client more than this long after the burst gets no pop
EggHatchTimeline.HIDDEN_SCALE = 0.05 -- the popping copy's scale (x the slime's) at the start of the pop
EggHatchTimeline.SHARDS = 12
EggHatchTimeline.SHARD_SECONDS = 1.1
EggHatchTimeline.BEAM_TIER = 4 -- Epic and up get a light pillar
-- Someone else's hatch: the title is a sign in the world (studs, hidden by walls), only for Epic and up, up close.
EggHatchTimeline.OTHERS_TITLE_TIER = 4
EggHatchTimeline.OTHERS_TITLE_DISTANCE = 60 -- studs from the camera
EggHatchTimeline.OTHERS_TITLE_STUDS = { 10, 2 } -- width, height

export type Phase = "wobble" | "hold" | "burst"

function EggHatchTimeline.phase(t: number): Phase
	if t < EggHatchTimeline.WOBBLE_END then
		return "wobble"
	elseif t < EggHatchTimeline.BURST then
		return "hold"
	end
	return "burst"
end

local EACH = EggHatchTimeline.WOBBLE_END / EggHatchTimeline.WOBBLES

-- Which rock (1..WOBBLES) is playing at `t`, or nil outside the wobble.
function EggHatchTimeline.wobble(t: number): number?
	if t < 0 or t >= EggHatchTimeline.WOBBLE_END then
		return nil
	end
	return math.floor(t / EACH) + 1
end

-- 0..1 through rock `n`.
local function within(t: number, n: number): number
	return (t - (n - 1) * EACH) / EACH
end

-- Rock of the egg at `t` (radians, about its base): 10°, 18°, 26°, then a fast shake in the hold.
function EggHatchTimeline.tilt(t: number): number
	local n = EggHatchTimeline.wobble(t)
	if n then
		local u = within(t, n)
		local envelope = if u < 0.6 then 1 else 1 - (u - 0.6) / 0.4 -- each rock settles before the next
		return math.rad(2 + 8 * n) * math.sin(u * math.pi * 3) * envelope
	elseif t >= EggHatchTimeline.WOBBLE_END and t < EggHatchTimeline.BURST then
		return math.rad(5) * math.sin(t * math.pi * 2 * 13)
	end
	return 0
end

-- Hop of the egg at `t` (studs up): a little jump at the start of each rock, higher each time.
function EggHatchTimeline.hop(t: number): number
	local n = EggHatchTimeline.wobble(t)
	if not n then
		return 0
	end
	local u = within(t, n)
	if u >= 0.35 then
		return 0
	end
	return (0.35 + 0.25 * n) * math.sin(u / 0.35 * math.pi)
end

-- Scale of the egg (x its own) at `t`: steady through the rocks, swelling and throbbing in the hold.
function EggHatchTimeline.swell(t: number): number
	if t < EggHatchTimeline.WOBBLE_END then
		return 1
	end
	local span = EggHatchTimeline.BURST - EggHatchTimeline.WOBBLE_END
	local u = math.clamp((t - EggHatchTimeline.WOBBLE_END) / span, 0, 1)
	return 1 + 0.18 * u + 0.03 * math.sin(t * math.pi * 2 * 9)
end

-- How many sets of glowing cracks show at `t` (one more per rock, all of them in the hold).
function EggHatchTimeline.crackSets(t: number): number
	if t < 0 then
		return 0
	end
	return EggHatchTimeline.wobble(t) or EggHatchTimeline.WOBBLES
end

-- The rarity tiers the glow climbs: from the kind's lowest drop up to the hatched tier (one entry at least).
function EggHatchTimeline.steps(lowest: number, tier: number): { number }
	local out = {}
	for step = math.min(lowest, tier), tier do
		table.insert(out, step)
	end
	return out
end

-- The tier whose colour the glow shows at `t`: the first rock at the bottom of `steps`, the last rock and the
-- hold at the top.
function EggHatchTimeline.glowTier(t: number, steps: { number }): number
	local n = EggHatchTimeline.wobble(t)
	if n == nil then
		return steps[#steps]
	end
	local index = 1 + math.floor((#steps - 1) * (n - 1) / (EggHatchTimeline.WOBBLES - 1) + 0.5)
	return steps[math.clamp(index, 1, #steps)]
end

-- Glow brightness at `t`: builds through the rocks, peaks and throbs in the hold.
function EggHatchTimeline.glow(t: number): number
	if t < 0 or t >= EggHatchTimeline.BURST then
		return 0
	elseif t < EggHatchTimeline.WOBBLE_END then
		return 1 + 3 * t / EggHatchTimeline.WOBBLE_END
	end
	return 6 + 2 * math.sin(t * math.pi * 2 * 6)
end

-- Whether a lucky hatch flashes gold at `t` (a beat in the hold).
function EggHatchTimeline.luckyFlash(t: number): boolean
	return t >= EggHatchTimeline.WOBBLE_END + 0.2 and t < EggHatchTimeline.WOBBLE_END + 0.4
end

-- Offset (studs: x, y up, z) of shard `i` of `n`, `s` seconds after the burst: an arc out and down to the floor.
function EggHatchTimeline.shard(i: number, n: number, s: number): (number, number, number)
	local angle = (i - 1) / n * math.pi * 2 + 0.3 * (i % 2)
	local out = 5 + 2 * ((i * 7) % 3)
	local up = 9 + 3 * ((i * 5) % 2)
	local x = math.cos(angle) * out * s
	local z = math.sin(angle) * out * s
	local y = 1.5 + up * s - 0.5 * 30 * s * s
	return x, math.max(y, 0.2), z
end

-- The egg's top flying off at the burst: height above the pad (studs) and spin (radians) `s` seconds after.
function EggHatchTimeline.lid(s: number): (number, number)
	return math.max(0.2, 3 + 12 * s - 0.5 * 30 * s * s), s * 9
end

-- The popping slime's scale (x its own), `s` seconds into the pop: tiny, up past full size, back.
function EggHatchTimeline.popScale(s: number): number
	local u = s / EggHatchTimeline.POP_SECONDS
	if u <= 0 then
		return EggHatchTimeline.HIDDEN_SCALE
	elseif u >= 1 then
		return 1
	elseif u < 0.5 then
		local k = u / 0.5
		return EggHatchTimeline.HIDDEN_SCALE + (1.25 - EggHatchTimeline.HIDDEN_SCALE) * (1 - (1 - k) ^ 3)
	elseif u < 0.8 then
		return 1.25 + (0.92 - 1.25) * (u - 0.5) / 0.3
	end
	return 0.92 + 0.08 * (u - 0.8) / 0.2
end

-- The title over the hatched slime: "LEGENDARY!", "LUCKY! MYTHIC!".
function EggHatchTimeline.title(tier: number, lucky: boolean): string
	local name = string.upper(Config.RARITIES[math.clamp(tier, 1, Config.MAX_TIER)].name)
	return if lucky then `LUCKY! {name}!` else `{name}!`
end

-- How the title shows for a viewer: "screen" (own hatch: fixed size, on top), "world" (someone
-- else's: sized in studs, behind walls, near only) or nil (no title).
export type TitleView = "screen" | "world"

function EggHatchTimeline.titleView(owner: boolean, tier: number): TitleView?
	if owner then
		return "screen"
	end
	return if tier >= EggHatchTimeline.OTHERS_TITLE_TIER then "world" else nil
end

-- Title rise (studs) and transparency `s` seconds into the pop; nil once it is over.
function EggHatchTimeline.titleLook(s: number): (number?, number?)
	if s < 0 or s >= EggHatchTimeline.TITLE_SECONDS then
		return nil, nil
	end
	local u = s / EggHatchTimeline.TITLE_SECONDS
	local fade = if u < 0.75 then 0 else (u - 0.75) / 0.25
	return 2 * u, fade
end

-- Light pillar transparency `s` seconds into the pop for a hatch of `tier` (nil = no pillar now).
function EggHatchTimeline.beam(s: number, tier: number): number?
	if tier < EggHatchTimeline.BEAM_TIER or s < 0 or s >= EggHatchTimeline.TITLE_SECONDS then
		return nil
	end
	return 0.55 + 0.45 * s / EggHatchTimeline.TITLE_SECONDS
end

-- Field of view offset (degrees, subtract) for the hatching owner's camera at egg time `t`.
function EggHatchTimeline.zoom(t: number): number
	local hold = EggHatchTimeline.WOBBLE_END
	local burst = EggHatchTimeline.BURST
	if t < hold or t >= burst + 1.4 then
		return 0
	elseif t < burst then
		return 6 * (t - hold) / (burst - hold)
	elseif t < burst + 0.8 then
		return 6
	end
	return 6 * (1 - (t - burst - 0.8) / 0.6)
end

return table.freeze(EggHatchTimeline)
