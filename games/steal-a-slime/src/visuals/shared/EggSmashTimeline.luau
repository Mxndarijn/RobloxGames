--!strict
--[[
	EggSmashTimeline (pure, contract/mystery-egg.md 40.7)

	A dropped wild Mystery Egg smashing on the ground, as numbers. Time `s` is
	seconds since this client started the show (it sees EggSmashedAt):
	  fall    0 .. fallSeconds(drop)   the egg drops with gravity, tipping forward
	  squash  for SQUASH_SECONDS       it flattens on the ground
	  burst   after the squash         shell shards fly out, bounce once and fade;
	                                   a goo splat spreads, a jagged ring of shell
	                                   stays a moment, a dust ring rolls out
	No Roblox APIs; numbers and tables only.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

local EggSmashTimeline = {}

EggSmashTimeline.GRAVITY = 110 -- studs/s^2: a bit heavier than the world's, so the drop reads as a smack
EggSmashTimeline.MIN_DROP = 2.5 -- studs: an egg already near the ground still drops from this high
EggSmashTimeline.MAX_FALL = 0.6 -- seconds: a long drop (off a ledge) is cut to this
EggSmashTimeline.TIP = math.rad(50) -- how far the egg tips over on its way down
EggSmashTimeline.SQUASH_SECONDS = 0.09
EggSmashTimeline.SQUASH_WIDE = 1.35 -- width x at the flattest
EggSmashTimeline.SQUASH_TALL = 0.5 -- height x at the flattest
EggSmashTimeline.SHARDS = 14
EggSmashTimeline.SHARD_SECONDS = 1.4 -- a shard's life after the burst; it fades out over the last FADE
EggSmashTimeline.FADE = 0.4
EggSmashTimeline.BOUNCE = 0.35 -- a shard keeps this share of its speed after it hits the ground
EggSmashTimeline.CROWN = 7 -- jagged shell pieces left standing where it landed
EggSmashTimeline.SPLAT_SIZE = 5 -- studs across, the goo splat at its widest
EggSmashTimeline.SPLAT_GROW = 0.12
EggSmashTimeline.SPLAT_HOLD = 0.9 -- seconds after the burst before the splat starts to fade
EggSmashTimeline.RING_SECONDS = 0.45
EggSmashTimeline.RING_SIZE = 11 -- studs across, the dust ring at its widest
EggSmashTimeline.LATE_SECONDS = 1 -- a client that sees EggSmashedAt later than this skips the show
-- The server keeps the egg model this long: enough for a late client to still copy it.
EggSmashTimeline.SERVER_SECONDS = Config.MYSTERY_EGG.SMASH_SECONDS

-- Seconds the fall takes from `drop` studs above the ground.
function EggSmashTimeline.fallSeconds(drop: number): number
	local h = math.max(drop, EggSmashTimeline.MIN_DROP)
	return math.min(math.sqrt(2 * h / EggSmashTimeline.GRAVITY), EggSmashTimeline.MAX_FALL)
end

-- Height above the ground and tip angle at `t` seconds into a fall from `drop` studs.
function EggSmashTimeline.fall(t: number, drop: number): (number, number)
	local h = math.max(drop, EggSmashTimeline.MIN_DROP)
	local total = EggSmashTimeline.fallSeconds(drop)
	local u = math.clamp(t / total, 0, 1)
	return h * (1 - u * u), EggSmashTimeline.TIP * u * u
end

-- Width and height scale `t` seconds into the squash: flattens fast, then holds.
function EggSmashTimeline.squash(t: number): (number, number)
	local u = math.clamp(t / EggSmashTimeline.SQUASH_SECONDS, 0, 1)
	local e = 1 - (1 - u) * (1 - u)
	return 1 + (EggSmashTimeline.SQUASH_WIDE - 1) * e, 1 + (EggSmashTimeline.SQUASH_TALL - 1) * e
end

-- A fixed spread per shard, so every viewer's burst looks alike: [0, 1).
local function spread(i: number, salt: number): number
	local x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

--[[
	Shard `i` of `n` at `s` seconds after the burst: offset (x, y, z) from the impact point (y above the ground),
	its spin in radians and its transparency. It flies out and up, bounces once at BOUNCE, then slides to a stop.
]]
function EggSmashTimeline.shard(i: number, n: number, s: number): (number, number, number, number, number)
	local g = EggSmashTimeline.GRAVITY
	local angle = (i / n) * math.pi * 2 + (spread(i, 1) - 0.5) * 0.6
	local out = 5 + 5 * spread(i, 2)
	local up = 10 + 7 * spread(i, 3)
	local y0 = 0.6 + 0.8 * spread(i, 4)
	-- First flight: from y0 up and down to the ground.
	local t1 = (up + math.sqrt(up * up + 2 * g * y0)) / g
	local y, dist
	if s <= t1 then
		y = y0 + up * s - 0.5 * g * s * s
		dist = out * s
	else
		local b = up * EggSmashTimeline.BOUNCE
		local t2 = 2 * b / g
		local s2 = math.min(s - t1, t2)
		y = math.max(0, b * s2 - 0.5 * g * s2 * s2)
		local slide = out * EggSmashTimeline.BOUNCE
		local rest = math.max(0, s - t1 - t2)
		dist = out * t1 + slide * s2 + slide * 0.5 * math.min(rest, 0.3) * (2 - math.min(rest, 0.3) / 0.3)
	end
	local spinTime = math.min(s, t1 + 0.25)
	local spin = spinTime * (8 + 6 * spread(i, 5))
	local fade = math.clamp((s - EggSmashTimeline.SHARD_SECONDS + EggSmashTimeline.FADE) / EggSmashTimeline.FADE, 0, 1)
	return math.cos(angle) * dist, y, math.sin(angle) * dist, spin, fade
end

-- The goo splat's diameter and transparency at `s` seconds after the burst.
function EggSmashTimeline.splat(s: number): (number, number)
	local grow = math.clamp(s / EggSmashTimeline.SPLAT_GROW, 0, 1)
	local size = EggSmashTimeline.SPLAT_SIZE * (1 - (1 - grow) ^ 3)
	local fadeEnd = EggSmashTimeline.SHARD_SECONDS
	local fade = math.clamp((s - EggSmashTimeline.SPLAT_HOLD) / (fadeEnd - EggSmashTimeline.SPLAT_HOLD), 0, 1)
	return size, 0.1 + 0.9 * fade
end

-- The standing ring of shell: how far it has sunk (0..1) and its transparency.
function EggSmashTimeline.crown(s: number): (number, number)
	local u = math.clamp(
		(s - EggSmashTimeline.SPLAT_HOLD) / (EggSmashTimeline.SHARD_SECONDS - EggSmashTimeline.SPLAT_HOLD),
		0,
		1
	)
	return u, u
end

-- The dust ring's diameter and transparency.
function EggSmashTimeline.ring(s: number): (number, number)
	local u = math.clamp(s / EggSmashTimeline.RING_SECONDS, 0, 1)
	return 1.5 + (EggSmashTimeline.RING_SIZE - 1.5) * (1 - (1 - u) ^ 2), 0.35 + 0.65 * u
end

-- Seconds from the start of the show until everything is gone.
function EggSmashTimeline.total(drop: number): number
	return EggSmashTimeline.fallSeconds(drop) + EggSmashTimeline.SQUASH_SECONDS + EggSmashTimeline.SHARD_SECONDS
end

return table.freeze(EggSmashTimeline)
