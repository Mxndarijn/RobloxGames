--!strict
--[[
	SlimeLayout (owner: Archer)

	SlimeLayout.build(slimeData: Types.SlimeData): { PartSpec }

	Pure geometry for a slime: a list of primitive part specs in model space
	(origin = bottom centre, front = -Z, studs, orientation in degrees).
	specs[1] is always the Body ball. No Roblox APIs, so the render proof
	runs it under Lune; ModelFactory just instantiates the list.

	Looks:
	  * tier 1..6: tier-coloured rim under the puddle; 2 sprout, 3-4 horns,
	    4+ halo, 5+ crown, 6 aura + orbiting gems (all grow with tier)
	  * pattern Plain / Spots / Stripes / Belly
	  * eyes Round / Sleepy / Angry / Happy / Cyclops / Wide
	  * mouth Smile / Open / Flat / Fang
	  * body material: the slime type's SlimeLooks material (unknown type -> SmoothPlastic)
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local LayoutMath = if script then require(script.Parent.LayoutMath) else require("./LayoutMath")
local SlimeLooks = if script
	then require(script.Parent.Parent.Shared.SlimeLooks)
	else require("../../shared/SlimeLooks")
local Types = if script then require(script.Parent.Parent.Shared.Types) else require("../../shared/Types")

type Vec = LayoutMath.Vec

export type PartSpec = {
	name: string,
	shape: string, -- "Ball" | "Block" | "Cylinder" (Enum.PartType name)
	size: Vec,
	pos: Vec,
	rot: Vec, -- orientation degrees, CFrame.fromOrientation order
	color: Vec, -- RGB 0..255
	material: string, -- Enum.Material name
	transparency: number,
}

local WHITE = { 255, 255, 255 }
local INK = { 30, 20, 30 }
local MOUTH = { 60, 15, 30 }
-- Face lines on dark bodies would vanish in INK.
local INK_ON_DARK = { 255, 225, 190 }
local MOUTH_ON_DARK = { 255, 150, 110 }
local TONGUE = { 255, 120, 150 }
local IVORY = { 245, 235, 210 }
local CROWN_GOLD = { 255, 205, 60 }
local LEAF = { 90, 200, 80 }

local EYE_PITCH = 14
local MOUTH_PITCH = -15

local SlimeLayout = {}

local function shade(c: Vec, k: number): Vec
	return {
		math.clamp(math.floor(c[1] * k + 0.5), 0, 255),
		math.clamp(math.floor(c[2] * k + 0.5), 0, 255),
		math.clamp(math.floor(c[3] * k + 0.5), 0, 255),
	}
end

local function mix(a: Vec, b: Vec, t: number): Vec
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end

local function luminance(c: Vec): number
	return 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
end

-- Builder state shared by the feature helpers below.
type Ctx = {
	d: number, -- body diameter
	r: number, -- body radius
	centre: Vec,
	specs: { PartSpec },
	ink: Vec, -- brows, lashes, closed eyes
	mouth: Vec,
}

local function push(ctx: Ctx, spec: PartSpec)
	table.insert(ctx.specs, spec)
end

local function part(
	name: string,
	shape: string,
	size: Vec,
	pos: Vec,
	rot: Vec,
	color: Vec,
	material: string,
	transparency: number?
): PartSpec
	return {
		name = name,
		shape = shape,
		size = size,
		pos = pos,
		rot = rot,
		color = color,
		material = material,
		transparency = transparency or 0,
	}
end

-- A part on the body surface at yaw/pitch, pushed `out` studs along the
-- normal, front face pointing outwards and rolled `roll` degrees.
local function onSurface(
	ctx: Ctx,
	name: string,
	shape: string,
	size: Vec,
	yaw: number,
	pitch: number,
	out: number,
	color: Vec,
	material: string,
	roll: number?,
	transparency: number?
)
	local n = LayoutMath.direction(yaw, pitch)
	local pos = LayoutMath.add(ctx.centre, LayoutMath.scale(n, ctx.r + out))
	push(ctx, part(name, shape, size, pos, LayoutMath.facing(n, roll), color, material, transparency))
end

-- Degrees of arc covered by `studs` on the body surface.
local function arc(ctx: Ctx, studs: number): number
	return math.deg(studs / ctx.r)
end

local function bodyLook(slime: Types.SlimeData): (Vec, string)
	local c = { slime.color[1], slime.color[2], slime.color[3] }
	-- The slime type's SlimeLooks material; unknown or missing types keep plain plastic.
	local look = SlimeLooks.get(slime.species)
	if look and SlimeLooks.isMaterial(look.material) then
		return c, look.material
	end
	return c, "SmoothPlastic"
end

-- Patterns ---------------------------------------------------------------

local SPOTS = {
	{ 62, 28, 1.0 },
	{ -62, 28, 1.0 },
	{ 98, -12, 0.85 },
	{ -98, -12, 0.85 },
	{ 140, 30, 1.1 },
	{ -140, 30, 1.1 },
	{ 180, -12, 1.0 },
	{ 42, -52, 0.7 },
	{ -42, -52, 0.7 },
}

local STRIPE_YAWS = { 56, 86, 116, 148, 212, 244, 274, 304 }
local STRIPE_PITCHES = { -32, 0, 32 }

local function addPattern(ctx: Ctx, pattern: string, base: Vec, material: string)
	local d = ctx.d
	local dark = if luminance(base) < 80 then mix(base, WHITE, 0.4) else shade(base, 0.6)
	if pattern == "Spots" then
		for i, s in SPOTS do
			local w = 0.2 * d * s[3]
			onSurface(ctx, `Spot{i}`, "Ball", { w, w, w * 0.25 }, s[1], s[2], -0.01 * d, dark, material)
		end
	elseif pattern == "Stripes" then
		for i, yaw in STRIPE_YAWS do
			for j, pitch in STRIPE_PITCHES do
				local size = { 0.075 * d, 0.3 * d, 0.05 * d }
				onSurface(ctx, `Stripe{i}_{j}`, "Block", size, yaw, pitch, 0, dark, material)
			end
		end
	elseif pattern == "Belly" then
		local light = mix(base, WHITE, 0.55)
		onSurface(ctx, "Belly", "Ball", { 0.62 * d, 0.42 * d, 0.14 * d }, 0, -38, -0.03 * d, light, material)
	end
end

-- Eyes -------------------------------------------------------------------

local function eyeball(ctx: Ctx, i: number, yaw: number, pitch: number, e: number, p: number, iris: Vec?)
	onSurface(ctx, `EyeWhite{i}`, "Ball", { e, e, e * 0.45 }, yaw, pitch, 0, WHITE, "SmoothPlastic")
	local out = e * 0.2
	if iris then
		onSurface(ctx, `Iris{i}`, "Ball", { p, p, p * 0.4 }, yaw, pitch, out, iris, "SmoothPlastic")
		p *= 0.45
		out += 0.05 * ctx.d
	end
	onSurface(ctx, `Pupil{i}`, "Ball", { p, p, p * 0.4 }, yaw, pitch, out, INK, "SmoothPlastic")
	local h = 0.3 * p + 0.02 * ctx.d
	local hy, hp = yaw - arc(ctx, p * 0.25), pitch + arc(ctx, p * 0.25)
	onSurface(ctx, `Shine{i}`, "Ball", { h, h, h * 0.5 }, hy, hp, out + p * 0.2, WHITE, "SmoothPlastic")
end

local function addEyes(ctx: Ctx, eyes: string, bodyColor: Vec, tierColor: Vec)
	local d = ctx.d
	if eyes == "Cyclops" then
		eyeball(ctx, 1, 0, EYE_PITCH + 2, 0.4 * d, 0.2 * d, tierColor)
		return
	end
	local wide = eyes == "Wide"
	local spread = if wide then 27 else 19
	local e = if wide then 0.3 * d else 0.22 * d
	for i, side in { -1, 1 } do
		local yaw = side * spread
		if eyes == "Round" or eyes == "Wide" then
			eyeball(ctx, i, yaw, EYE_PITCH, e, if wide then 0.08 * d else 0.11 * d)
		elseif eyes == "Angry" then
			eyeball(ctx, i, yaw, EYE_PITCH - 1, e, 0.11 * d)
			-- Brows slope down towards the middle: \ /
			local brow = { 0.22 * d, 0.05 * d, 0.05 * d }
			onSurface(
				ctx,
				`Brow{i}`,
				"Block",
				brow,
				yaw,
				EYE_PITCH + arc(ctx, 0.62 * e),
				0.06 * d,
				ctx.ink,
				"SmoothPlastic",
				side * -22
			)
		elseif eyes == "Sleepy" then
			onSurface(ctx, `EyeWhite{i}`, "Ball", { e, e, e * 0.45 }, yaw, EYE_PITCH, 0, WHITE, "SmoothPlastic")
			local p = 0.1 * d
			onSurface(ctx, `Pupil{i}`, "Ball", { p, p, p * 0.4 }, yaw, EYE_PITCH - 3, e * 0.2, INK, "SmoothPlastic")
			local lidPitch = EYE_PITCH + arc(ctx, 0.27 * e)
			onSurface(
				ctx,
				`Lid{i}`,
				"Ball",
				{ e * 1.1, e * 0.62, e * 0.5 },
				yaw,
				lidPitch,
				e * 0.08,
				bodyColor,
				"SmoothPlastic"
			)
			local lash = { e * 1.0, 0.03 * d, 0.03 * d }
			onSurface(
				ctx,
				`Lash{i}`,
				"Block",
				lash,
				yaw,
				EYE_PITCH - arc(ctx, 0.03 * e),
				e * 0.26,
				ctx.ink,
				"SmoothPlastic"
			)
		elseif eyes == "Happy" then
			-- Closed happy eyes: ^ ^
			local arm = { 0.13 * d, 0.045 * d, 0.04 * d }
			local off = arc(ctx, 0.045 * d)
			onSurface(ctx, `HappyL{i}`, "Block", arm, yaw - off, EYE_PITCH, 0.01 * d, ctx.ink, "SmoothPlastic", -35)
			onSurface(ctx, `HappyR{i}`, "Block", arm, yaw + off, EYE_PITCH, 0.01 * d, ctx.ink, "SmoothPlastic", 35)
			local blush = { 0.12 * d, 0.06 * d, 0.03 * d }
			onSurface(ctx, `Blush{i}`, "Ball", blush, side * 30, EYE_PITCH - 14, 0, TONGUE, "SmoothPlastic", 0, 0.2)
		end
	end
end

-- Mouths -----------------------------------------------------------------

local function addSmile(ctx: Ctx, width: number)
	local d = ctx.d
	local seg = { width * 0.45, 0.035 * d, 0.035 * d }
	local off = arc(ctx, width * 0.4)
	onSurface(ctx, "MouthMid", "Block", seg, 0, MOUTH_PITCH - 1.5, 0.005 * d, ctx.mouth, "SmoothPlastic")
	onSurface(ctx, "MouthL", "Block", seg, -off, MOUTH_PITCH + 1, 0.005 * d, ctx.mouth, "SmoothPlastic", 28)
	onSurface(ctx, "MouthR", "Block", seg, off, MOUTH_PITCH + 1, 0.005 * d, ctx.mouth, "SmoothPlastic", -28)
end

local function addMouth(ctx: Ctx, mouth: string)
	local d = ctx.d
	if mouth == "Smile" then
		addSmile(ctx, 0.24 * d)
	elseif mouth == "Open" then
		onSurface(
			ctx,
			"Mouth",
			"Ball",
			{ 0.2 * d, 0.17 * d, 0.07 * d },
			0,
			MOUTH_PITCH - 2,
			0,
			ctx.mouth,
			"SmoothPlastic"
		)
		local tongue = { 0.11 * d, 0.06 * d, 0.05 * d }
		onSurface(ctx, "Tongue", "Ball", tongue, 0, MOUTH_PITCH - 5, 0.02 * d, TONGUE, "SmoothPlastic")
	elseif mouth == "Flat" then
		onSurface(
			ctx,
			"Mouth",
			"Block",
			{ 0.18 * d, 0.035 * d, 0.035 * d },
			0,
			MOUTH_PITCH,
			0.005 * d,
			ctx.mouth,
			"SmoothPlastic"
		)
	elseif mouth == "Fang" then
		addSmile(ctx, 0.28 * d)
		local fang = { 0.04 * d, 0.07 * d, 0.03 * d }
		local below = MOUTH_PITCH - 1.5 - arc(ctx, 0.045 * d)
		for i, side in { -1, 1 } do
			onSurface(ctx, `Fang{i}`, "Block", fang, side * arc(ctx, 0.05 * d), below, 0.01 * d, WHITE, "SmoothPlastic")
		end
	end
end

-- Tier accents -----------------------------------------------------------

local function addTier(ctx: Ctx, tier: number, tierColor: Vec, bodyColor: Vec)
	local d, r = ctx.d, ctx.r
	-- Body-coloured goo puddle under the ball. No rarity-coloured ring: rarity shows in the accents below.
	local puddleD = 0.92 * d
	push(
		ctx,
		part(
			"Puddle",
			"Cylinder",
			{ 0.1 * d, puddleD, puddleD },
			{ 0, 0.06 * d, 0 },
			{ 0, 0, 90 },
			shade(bodyColor, 0.85),
			"SmoothPlastic"
		)
	)

	if tier == 2 then
		push(
			ctx,
			part(
				"Sprout",
				"Cylinder",
				{ 0.14 * d, 0.04 * d, 0.04 * d },
				{ 0, d + 0.05 * d, 0 },
				{ 0, 0, 90 },
				LEAF,
				"SmoothPlastic"
			)
		)
		for i, side in { -1, 1 } do
			local pos = { side * 0.07 * d, d + 0.12 * d, 0 }
			push(
				ctx,
				part(
					`Leaf{i}`,
					"Ball",
					{ 0.15 * d, 0.035 * d, 0.08 * d },
					pos,
					{ 0, 0, side * -25 },
					LEAF,
					"SmoothPlastic"
				)
			)
		end
	end

	if tier == 3 or tier == 4 then
		local k = if tier == 3 then 1 else 1.35
		local hornColor = mix(tierColor, IVORY, 0.55)
		for i, side in { -1, 1 } do
			local n = LayoutMath.direction(side * 72, 52)
			local base = LayoutMath.add(ctx.centre, LayoutMath.scale(n, r * 0.95))
			local outward = { n[1], 0, n[3] }
			local sizes = { 0.15, 0.11, 0.07 }
			local steps = { { 0, 0 }, { 0.05, 0.1 }, { 0.09, 0.19 } }
			for j = 1, 3 do
				local w = sizes[j] * d * k
				local pos = LayoutMath.add(
					base,
					LayoutMath.add(LayoutMath.scale(outward, steps[j][1] * d * k), { 0, steps[j][2] * d * k, 0 })
				)
				push(ctx, part(`Horn{i}_{j}`, "Ball", { w, w, w }, pos, { 0, 0, 0 }, hornColor, "SmoothPlastic"))
			end
		end
	end

	local crownTop = d
	if tier >= 5 then
		local k = if tier == 5 then 1 else 1.2
		local bandD, bandH = 0.5 * d * k, 0.12 * d * k
		local bandY = d - 0.02 * d
		push(
			ctx,
			part("CrownBand", "Cylinder", { bandH, bandD, bandD }, { 0, bandY, 0 }, { 0, 0, 90 }, CROWN_GOLD, "Foil")
		)
		local spike = 0.1 * d * k
		local spikeY = bandY + bandH / 2 + spike * 0.25
		for i = 1, tier do
			local yaw = (i - 1) * 360 / tier
			local n = LayoutMath.direction(yaw, 0)
			local pos = LayoutMath.add({ 0, spikeY, 0 }, LayoutMath.scale(n, bandD / 2 - 0.015 * d))
			push(
				ctx,
				part(`CrownSpike{i}`, "Block", { spike, spike, 0.03 * d }, pos, { 0, yaw, 45 }, CROWN_GOLD, "Foil")
			)
			local gemPos = LayoutMath.add({ 0, bandY, 0 }, LayoutMath.scale(n, bandD / 2 + 0.01 * d))
			local g = 0.05 * d * k
			push(ctx, part(`CrownGem{i}`, "Ball", { g, g, g * 0.6 }, gemPos, { 0, yaw, 0 }, tierColor, "Neon"))
		end
		crownTop = spikeY + spike * 0.7
	end

	if tier >= 4 then
		local count = 6 + 2 * (tier - 2)
		local radius = (0.22 + 0.03 * tier) * d
		local y = crownTop + 0.18 * d
		local tilt = LayoutMath.orientation({ 12, 0, 0 })
		local bead = (0.05 + 0.008 * tier) * d
		for i = 1, count do
			local a = (i - 1) * 2 * math.pi / count
			local offset = LayoutMath.apply(tilt, { math.cos(a) * radius, 0, math.sin(a) * radius })
			push(
				ctx,
				part(
					`Halo{i}`,
					"Ball",
					{ bead, bead, bead },
					LayoutMath.add({ 0, y, 0 }, offset),
					{ 0, 0, 0 },
					tierColor,
					"Neon"
				)
			)
		end
	end

	if tier >= 6 then
		local aura = 1.3 * d
		push(ctx, part("Aura", "Ball", { aura, aura, aura }, ctx.centre, { 0, 0, 0 }, tierColor, "Neon", 0.88))
		local orbit = { { 35, 0.95 }, { 155, 1.35 }, { 275, 1.1 } }
		for i, o in orbit do
			local n = LayoutMath.direction(o[1], 0)
			local pos = { n[1] * 0.78 * d, r * o[2], n[3] * 0.78 * d }
			local g = 0.12 * d
			push(
				ctx,
				part(`OrbitGem{i}`, "Block", { g, g, g }, pos, { 45, o[1], 45 }, mix(tierColor, WHITE, 0.25), "Neon")
			)
		end
	end
end

-- Public -----------------------------------------------------------------

function SlimeLayout.diameter(size: number): number
	return Config.SLIME_BASE_DIAMETER * size
end

function SlimeLayout.build(slime: Types.SlimeData): { PartSpec }
	local d = SlimeLayout.diameter(slime.size)
	local r = d / 2
	local tier = math.clamp(math.floor(tonumber(slime.tier) or 1), 1, Config.MAX_TIER)
	local tierColor = Config.RARITIES[tier].color
	local tierRgb = { tierColor[1], tierColor[2], tierColor[3] }
	local bodyColor, bodyMaterial = bodyLook(slime)
	local dark = luminance(bodyColor) < 70
	local ctx: Ctx = {
		d = d,
		r = r,
		centre = { 0, r, 0 },
		specs = {},
		ink = if dark then INK_ON_DARK else INK,
		mouth = if dark then MOUTH_ON_DARK else MOUTH,
	}

	local body = part("Body", "Ball", { d, d, d }, ctx.centre, { 0, 0, 0 }, bodyColor, bodyMaterial)
	push(ctx, body)

	local patternMaterial = if bodyMaterial == "Neon" then "SmoothPlastic" else bodyMaterial
	addPattern(ctx, slime.pattern, bodyColor, patternMaterial)
	addEyes(ctx, slime.eyes, bodyColor, tierRgb)
	addMouth(ctx, slime.mouth)
	onSurface(ctx, "Gloss", "Ball", { 0.16 * d, 0.1 * d, 0.05 * d }, -38, 42, 0, WHITE, "SmoothPlastic", -30, 0.35)
	addTier(ctx, tier, tierRgb, bodyColor)
	return ctx.specs
end

return table.freeze(SlimeLayout)
