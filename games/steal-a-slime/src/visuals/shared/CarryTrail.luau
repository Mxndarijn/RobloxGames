--!strict
--[[
	CarryTrail (contract/exclusive-shop.md §9)

	The look of a carry trail: what streams behind a player while they carry a slime, for the equipped
	Config.EXCLUSIVE_SHOP.trails id (Player attribute CarryTrail). Pure: no Roblox APIs, so the specs run under
	Lune; visuals/client/CarryTrailFx turns a Look into a Trail + ParticleEmitter on the HumanoidRootPart.

	Every position is in the root part's frame (Roblox: +Y up, +Z behind the player). Rules the spec holds:
	  * always visible: the trail and the particles stay opaque for most of their life (never faint, never tiny);
	  * never over the carried slime: the slime sits on the head (about SLIME_SEAT studs above the root centre);
	    the trail ribbon stays below HEAD_CLEAR, behind the back, and no particle rises to the seat;
	  * cheap on phones: a few particles per player, only the MAX_DRAWN nearest carriers within MAX_DISTANCE.

	  def(id)        the trail definition, or nil for an unknown id
	  shows(...)     whether a player's trail is drawn (known id, carrying, within MAX_DISTANCE)
	  pick(...)      the nearest MAX_DRAWN of the players that show one
	  look(def)      trail + particle numbers for one definition (colour keypoints in 0-255)
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")

export type Def = { id: string, name: string, robux: number, colors: { { number } }, style: string }
export type ColorKey = { t: number, rgb: { number } }
export type NumberKey = { t: number, v: number }
export type TrailLook = {
	colors: { ColorKey },
	transparency: { NumberKey },
	width: { NumberKey }, -- WidthScale along the trail
	lifetime: number,
	lightEmission: number,
	top: number, -- Attachment0 Y
	bottom: number, -- Attachment1 Y
	back: number, -- both attachments' Z (behind the back)
}
export type ParticleLook = {
	texture: string,
	colors: { ColorKey },
	transparency: { NumberKey },
	size: { NumberKey },
	rate: number, -- per second
	lifetime: { number }, -- min, max seconds
	speed: { number }, -- min, max studs/s, emitted backwards (+Z) within `spread` degrees
	spread: number,
	accel: { number }, -- x, y, z studs/s^2 (world)
	drag: number,
	rotation: { number },
	rotSpeed: { number },
	lightEmission: number,
	offset: { number }, -- emitter attachment x, y, z
}
export type Look = { trail: TrailLook, particles: ParticleLook }

local CarryTrail = {}

CarryTrail.MAX_DISTANCE = 160 -- studs from the camera: further away nothing is drawn
CarryTrail.MAX_DRAWN = 8 -- carriers drawn at once (the nearest)
CarryTrail.SWEEP_EVERY = 0.2 -- seconds between looks at the players (attributes, characters, distances)
CarryTrail.HEAD_CLEAR = 0.9 -- studs above the root centre the ribbon may reach (the head starts higher)
CarryTrail.SLIME_SEAT = 2.0 -- studs above the root centre where a carried slime starts (the head top)
CarryTrail.MAX_ALIVE = 16 -- particles alive per carrier (rate x longest lifetime)

-- Built-in client textures (no uploads). The trail itself never needs one, so a texture that goes missing in a client
-- update only drops the particles, never the trail.
CarryTrail.TEXTURES = table.freeze({
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	blob = "rbxasset://textures/whiteCircle.png",
	heart = "rbxasset://textures/ui/Moments/Reactions/heart-large@3x.png",
	star = "rbxasset://textures/ui/InspectMenu/ico_favorite@3x.png",
})

CarryTrail.STYLES = table.freeze({ "sparkle", "drip", "hearts", "stars", "ribbon" })

local defs: { [string]: Def } = {}
for _, def in Config.EXCLUSIVE_SHOP.trails do
	defs[def.id] = def :: any
end

function CarryTrail.def(id: any): Def?
	return if type(id) == "string" then defs[id] else nil
end

-- Whether a player's trail is drawn: a known equipped id, carrying a slime (attribute Carrying set) and near enough.
function CarryTrail.shows(trailId: any, carrying: any, distance: number): boolean
	return CarryTrail.def(trailId) ~= nil and carrying ~= nil and distance <= CarryTrail.MAX_DISTANCE
end

-- The keys of the nearest `max` candidates (default MAX_DRAWN), as a set.
function CarryTrail.pick(candidates: { { key: any, distance: number } }, max: number?): { [any]: boolean }
	local sorted = table.clone(candidates)
	table.sort(sorted, function(a, b)
		return a.distance < b.distance
	end)
	local out = {}
	for i = 1, math.min(#sorted, max or CarryTrail.MAX_DRAWN) do
		out[sorted[i].key] = true
	end
	return out
end

-- Colour keypoints spread evenly over 0..1 (a single colour repeats at both ends).
local function spread(colors: { { number } }): { ColorKey }
	local out = {}
	local n = #colors
	if n == 1 then
		return { { t = 0, rgb = colors[1] }, { t = 1, rgb = colors[1] } }
	end
	for i, c in colors do
		table.insert(out, { t = (i - 1) / (n - 1), rgb = c })
	end
	return out
end

local function keys(pairs: { { number } }): { NumberKey }
	local out = {}
	for _, p in pairs do
		table.insert(out, { t = p[1], v = p[2] })
	end
	return out
end

local TRAIL_BASE = {
	transparency = { { 0, 0.05 }, { 0.6, 0.25 }, { 1, 0.55 } },
	width = { { 0, 1 }, { 1, 0.35 } },
	lifetime = 0.55,
	lightEmission = 0.35,
	top = 0.5,
	bottom = -1.1,
	back = 0.45,
}

-- Per style: what differs from TRAIL_BASE and the particles.
local STYLE: { [string]: { trail: { [string]: any }, particles: { [string]: any } } } = {
	sparkle = { -- twinkling glints that hang in the air behind you
		trail = {},
		particles = {
			texture = "sparkle",
			transparency = { { 0, 0 }, { 0.7, 0.1 }, { 1, 0.6 } },
			size = { { 0, 0.35 }, { 0.3, 0.75 }, { 0.6, 0.4 }, { 1, 0.15 } }, -- swells then twinkles out
			rate = 12,
			lifetime = { 0.6, 1.0 },
			speed = { 0.6, 1.6 },
			spread = 60,
			accel = { 0, 0, 0 },
			drag = 2,
			rotation = { 0, 360 },
			rotSpeed = { -120, 120 },
			lightEmission = 0.7,
			offset = { 0, -0.2, 0.6 },
		},
	},
	drip = { -- fat goo blobs that drop off behind you and fall
		trail = { lightEmission = 0.15 },
		particles = {
			texture = "blob",
			transparency = { { 0, 0 }, { 0.8, 0.05 }, { 1, 0.5 } },
			size = { { 0, 0.3 }, { 0.2, 0.42 }, { 1, 0.3 } },
			rate = 9,
			lifetime = { 0.7, 1.0 },
			speed = { 0.5, 1.2 },
			spread = 25,
			accel = { 0, -22, 0 },
			drag = 0,
			rotation = { 0, 0 },
			rotSpeed = { 0, 0 },
			lightEmission = 0.1,
			offset = { 0, -0.1, 0.6 },
		},
	},
	hearts = { -- hearts floating gently up and back
		trail = {},
		particles = {
			texture = "heart",
			transparency = { { 0, 0 }, { 0.75, 0.05 }, { 1, 0.6 } },
			size = { { 0, 0.3 }, { 0.25, 0.6 }, { 1, 0.45 } },
			rate = 7,
			lifetime = { 1.0, 1.4 },
			speed = { 0.8, 1.4 },
			spread = 30,
			accel = { 0, 0.6, 0 },
			drag = 1,
			rotation = { -20, 20 },
			rotSpeed = { -40, 40 },
			lightEmission = 0.3,
			offset = { 0, -0.6, 0.6 },
		},
	},
	stars = { -- little stars tumbling down behind you
		trail = {},
		particles = {
			texture = "star",
			transparency = { { 0, 0 }, { 0.75, 0.05 }, { 1, 0.6 } },
			size = { { 0, 0.5 }, { 1, 0.3 } },
			rate = 9,
			lifetime = { 0.8, 1.2 },
			speed = { 0.8, 1.6 },
			spread = 45,
			accel = { 0, -5, 0 },
			drag = 0.5,
			rotation = { 0, 360 },
			rotSpeed = { -180, 180 },
			lightEmission = 0.5,
			offset = { 0, 0, 0.6 },
		},
	},
	ribbon = { -- a wide rainbow ribbon (the colours run along it) with a few glints
		trail = {
			transparency = { { 0, 0 }, { 0.7, 0.15 }, { 1, 0.5 } },
			width = { { 0, 1 }, { 1, 0.6 } },
			lifetime = 0.8,
			lightEmission = 0.3,
			top = 0.7,
			bottom = -1.4,
		},
		particles = {
			texture = "sparkle",
			transparency = { { 0, 0 }, { 0.7, 0.1 }, { 1, 0.6 } },
			size = { { 0, 0.3 }, { 0.4, 0.55 }, { 1, 0.15 } },
			rate = 6,
			lifetime = { 0.6, 0.9 },
			speed = { 0.6, 1.4 },
			spread = 60,
			accel = { 0, 0, 0 },
			drag = 2,
			rotation = { 0, 360 },
			rotSpeed = { -90, 90 },
			lightEmission = 0.6,
			offset = { 0, -0.3, 0.6 },
		},
	},
}

-- The trail and particle numbers for one trail definition (an unknown style draws like "sparkle").
function CarryTrail.look(def: Def): Look
	local style = STYLE[def.style] or STYLE.sparkle
	local t = style.trail
	local p = style.particles
	local colors = spread(def.colors)
	local trail: TrailLook = {
		colors = colors,
		transparency = keys(t.transparency or TRAIL_BASE.transparency),
		width = keys(t.width or TRAIL_BASE.width),
		lifetime = t.lifetime or TRAIL_BASE.lifetime,
		lightEmission = t.lightEmission or TRAIL_BASE.lightEmission,
		top = t.top or TRAIL_BASE.top,
		bottom = t.bottom or TRAIL_BASE.bottom,
		back = t.back or TRAIL_BASE.back,
	}
	local particles: ParticleLook = {
		texture = CarryTrail.TEXTURES[p.texture],
		colors = colors,
		transparency = keys(p.transparency),
		size = keys(p.size),
		rate = p.rate,
		lifetime = p.lifetime,
		speed = p.speed,
		spread = p.spread,
		accel = p.accel,
		drag = p.drag,
		rotation = p.rotation,
		rotSpeed = p.rotSpeed,
		lightEmission = p.lightEmission,
		offset = p.offset,
	}
	return { trail = trail, particles = particles }
end

-- The highest a particle can get above the root centre (studs): its start height, the steepest upward launch and
-- any upward acceleration over its longest life (drag only slows it, so this is an upper bound).
function CarryTrail.maxRise(p: ParticleLook): number
	local life = p.lifetime[2]
	local up = p.speed[2] * math.sin(math.rad(math.min(p.spread, 90)))
	return p.offset[2] + up * life + 0.5 * math.max(p.accel[2], 0) * life * life
end

-- Particles alive at once for one carrier (rate x longest lifetime).
function CarryTrail.alive(p: ParticleLook): number
	return p.rate * p.lifetime[2]
end

return CarryTrail
