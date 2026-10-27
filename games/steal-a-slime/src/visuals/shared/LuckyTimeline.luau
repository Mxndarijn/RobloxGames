--!strict
--[[
	LuckyTimeline (pure, contract/lucky-charm.md)

	The Lucky Charm show as numbers. Time `t` is seconds since the deposit (server time, the model's LuckyAt):
	  glow   0 .. MORPH          the caught slime pulses gold
	  burst  MORPH ..            the promoted slime's model: a flash, a ring, sparkles; the highlight turns from gold
	                             to the new rarity colour; the title floats up over TITLE_SECONDS
	No Roblox APIs; numbers and tables only.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

local LuckyTimeline = {}

LuckyTimeline.MORPH = Config.LUCKY_SHOW.MORPH_SECONDS
LuckyTimeline.LATE = 2 -- a promoted model that reaches a client more than this long after the morph gets no burst
LuckyTimeline.REBUILD_WAIT = 0.6 -- the caught model keeps glowing this long past the morph while the server rebuilds it
LuckyTimeline.BURST_SECONDS = 1
LuckyTimeline.TITLE_SECONDS = 2.8
LuckyTimeline.SPARKS = 30
LuckyTimeline.GOLD = table.freeze({ 255, 214, 90 })
LuckyTimeline.CLOVER = table.freeze({ 90, 220, 110 })

export type Phase = "glow" | "burst"

-- What a model tagged LuckyAt plays at `t`: the glow before the morph, the burst within LATE after it, else nil.
function LuckyTimeline.phase(t: number): Phase?
	if t < 0 then
		return nil
	elseif t < LuckyTimeline.MORPH then
		return "glow"
	elseif t < LuckyTimeline.MORPH + LuckyTimeline.LATE then
		return "burst"
	end
	return nil
end

-- Highlight fill transparency of the glow at `t`: pulses faster and brighter towards the morph.
function LuckyTimeline.glow(t: number): number
	local u = math.clamp(t / LuckyTimeline.MORPH, 0, 1)
	local pulse = 0.5 + 0.5 * math.sin(t * (10 + 14 * u))
	return 0.85 - (0.25 + 0.3 * u) * pulse
end

export type BurstLook = {
	ring: number, -- ring diameter, studs
	ringFade: number, -- ring transparency
	light: number, -- flash brightness
	mix: number, -- highlight colour, 0 = gold .. 1 = the new rarity colour
	fill: number, -- highlight fill transparency
}

-- The burst `s` seconds after it starts; nil once it is over.
function LuckyTimeline.burst(s: number): BurstLook?
	if s < 0 or s >= LuckyTimeline.BURST_SECONDS then
		return nil
	end
	local u = s / LuckyTimeline.BURST_SECONDS
	return {
		ring = 2 + 14 * (1 - (1 - u) ^ 3),
		ringFade = 0.1 + 0.9 * u,
		light = 8 * (1 - u) ^ 2,
		mix = math.clamp(u * 2, 0, 1),
		fill = 0.3 + 0.7 * u,
	}
end

-- Title rise (studs) and transparency `s` seconds into the burst; nil once it is over.
function LuckyTimeline.titleLook(s: number): (number?, number?)
	if s < 0 or s >= LuckyTimeline.TITLE_SECONDS then
		return nil, nil
	end
	local u = s / LuckyTimeline.TITLE_SECONDS
	local fade = if u < 0.7 then 0 else (u - 0.7) / 0.3
	return 2.5 * u, fade
end

local function rarity(tier: number): Config.Rarity
	return Config.RARITIES[math.clamp(math.floor(tier), 1, Config.MAX_TIER)]
end

local function hex(c: { number }): string
	return string.format("#%02X%02X%02X", c[1], c[2], c[3])
end

-- The title's two lines: "🍀 LUCKY!" and the rarity step as RichText ("Legendary → Mythic", each in its colour).
function LuckyTimeline.title(fromTier: number, tier: number): (string, string)
	local from, to = rarity(fromTier), rarity(tier)
	return "🍀 LUCKY!",
		`<font color="{hex(from.color)}">{from.name}</font> → <font color="{hex(to.color)}">{to.name}</font>`
end

return table.freeze(LuckyTimeline)
