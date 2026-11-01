--!strict
--[[
	ObbyParts (shared visuals, contract/obby.md §5 and contract/obby-sections.md §8, §10b)

	Builds the obby course as Instances from ObbyCourse data: one Part per ObbyCourse.Part (a TrussPart for
	ladders), its readability decor (markers, lock icons, particles), and the Goo Ring's decor behind the start pad.
	The client builds it (visuals/client/ObbyCourseView) from the slot the server publishes, like the backdrop, so the
	server's world and its part budget never carry the course. Also holds the obby's sign colours and label helper,
	which server/ObbyView's portal shares.

	Data for the client scripts (§10b): the Course model carries ObbyFrame (the course frame: X forward, Y up,
	Z right). Every part carries ObbyId; a part with any behaviour also carries ObbySpec (the JSON of exactly its
	behaviour fields, course-local as in the data) and ObbyBase (its rest CFrame in world space). ObbyFx and ObbyMoves
	read those; this module plays nothing. Belts get a surface velocity, ice no friction.

	Rotation: `yaw`, `pitch`, `roll` (degrees) turn a part round its course-local Y, X and Z axes, in Roblox's YXZ
	order (CFrame.fromEulerAnglesYXZ). A positive `roll` lifts the part's +X (forward) end: that is how a ramp climbs.

	Markers (`marker`) and lock icons are small anchored ghost parts parented directly under their host part (no
	welds): ObbyFx keeps each direct child BasePart at its rest offset from the host and fades it with the host, so
	markers on moving parts follow. The one exception is `ghostStop`, which marks where a moving part stops: it stays
	put in the world and sits in the Course model (named "GhostStop", attribute ObbyHost = the host's id). Particles
	and ring adornments add no parts. MARKER_PARTS lists how many parts each marker adds, for the part budget (§9).

	Signs: a `sign:<text>` marker is a SurfaceGui board (guides/roblox-world-labels.md): its 1.3-stud line reads from
	about 26 studs on a phone; MaxDistance 60. The Goo Ring sign is a SurfaceGui too: its 1-stud line reads from about
	20 studs on a phone; the runner appears about 7 studs from it.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ObbyCourse = require(Shared:WaitForChild("ObbyCourse"))

local ObbyParts = {}

-- Sign and ring colours, shared with the portal (server/ObbyView).
ObbyParts.COLORS = table.freeze({
	ring = Color3.fromRGB(150, 230, 70),
	floor = Color3.fromRGB(170, 255, 140),
	sign = Color3.fromRGB(46, 38, 70),
	ink = Color3.fromRGB(255, 255, 255),
	stroke = Color3.fromRGB(30, 22, 48),
})
ObbyParts.FONT = Enum.Font.FredokaOne
ObbyParts.PIXELS_PER_STUD = 50

-- Parts each marker kind adds (the most it can add), for the part budget (contract §9). `rings1`..`rings3` are one
-- carrier part with ring adornments; a gate adds one lock part per key it needs on top of this.
ObbyParts.MARKER_PARTS = table.freeze({
	rings1 = 1,
	rings2 = 1,
	rings3 = 1,
	chevrons = 4,
	arrows = 3,
	handprints = 3,
	cracks = 3,
	star = 2,
	rail = 2,
	ghostStop = 2,
	sign = 1,
})

-- Look per part kind: colour (or three tones), material, transparency. No Neon on big parts: it blooms into blobs
-- against the obby sky, so even the "glow" tiles are saturated SmoothPlastic. No Glass anywhere.
type Look = { colors: { Color3 }, material: Enum.Material, transparency: number? }
local LOOKS: { [string]: Look } = {
	start = { colors = { Color3.fromRGB(120, 226, 170) }, material = Enum.Material.SmoothPlastic },
	pad = { colors = { Color3.fromRGB(214, 226, 238) }, material = Enum.Material.SmoothPlastic },
	finish = { colors = { Color3.fromRGB(255, 206, 64) }, material = Enum.Material.SmoothPlastic },
	jelly = {
		colors = { Color3.fromRGB(255, 120, 190), Color3.fromRGB(120, 220, 120), Color3.fromRGB(110, 170, 255) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.15,
	},
	goo = {
		colors = { Color3.fromRGB(150, 230, 70), Color3.fromRGB(120, 205, 60) },
		material = Enum.Material.SmoothPlastic,
	},
	bubble = {
		colors = { Color3.fromRGB(170, 235, 255), Color3.fromRGB(200, 225, 255), Color3.fromRGB(190, 255, 240) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.3,
	},
	-- A narrow walkway (the checks allow beams down to Kit.BEAM_MIN wide).
	beam = {
		colors = { Color3.fromRGB(240, 200, 120), Color3.fromRGB(225, 180, 100) },
		material = Enum.Material.Wood,
	},
	rope = {
		colors = { Color3.fromRGB(230, 180, 90), Color3.fromRGB(210, 160, 80), Color3.fromRGB(240, 200, 110) },
		material = Enum.Material.Wood,
	},
	tile = {
		colors = { Color3.fromRGB(160, 110, 240), Color3.fromRGB(255, 160, 60), Color3.fromRGB(110, 200, 230) },
		material = Enum.Material.SmoothPlastic,
	},
	post = { colors = { Color3.fromRGB(70, 60, 90) }, material = Enum.Material.SmoothPlastic },
	bar = { colors = { Color3.fromRGB(235, 70, 120) }, material = Enum.Material.SmoothPlastic },
	cannon = { colors = { Color3.fromRGB(70, 66, 96), Color3.fromRGB(255, 140, 40) }, material = Enum.Material.Metal },
	blob = {
		colors = { Color3.fromRGB(130, 230, 90) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.1,
	},
	pipe = {
		colors = { Color3.fromRGB(150, 230, 70) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.7,
	},
	truss = { colors = { Color3.fromRGB(255, 120, 190) }, material = Enum.Material.SmoothPlastic },
	fan = { colors = { Color3.fromRGB(90, 96, 120) }, material = Enum.Material.DiamondPlate },
	plank = {
		colors = { Color3.fromRGB(200, 150, 90), Color3.fromRGB(180, 130, 75) },
		material = Enum.Material.Wood,
	},
	glow = {
		colors = { Color3.fromRGB(255, 200, 50), Color3.fromRGB(80, 215, 120), Color3.fromRGB(70, 170, 240) },
		material = Enum.Material.SmoothPlastic,
	},
	log = {
		colors = { Color3.fromRGB(160, 105, 60), Color3.fromRGB(140, 90, 50) },
		material = Enum.Material.Wood,
	},
	wave = {
		colors = { Color3.fromRGB(110, 220, 90) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.15,
	},
	-- One look per behaviour (contract §8).
	hazard = {
		colors = { Color3.fromRGB(235, 70, 90) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.45,
	},
	sticky = {
		colors = { Color3.fromRGB(175, 240, 40), Color3.fromRGB(150, 215, 30) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.05,
	},
	spring = {
		colors = { Color3.fromRGB(255, 150, 50), Color3.fromRGB(255, 120, 40) },
		material = Enum.Material.SmoothPlastic,
	},
	ice = { colors = { Color3.fromRGB(190, 230, 255) }, material = Enum.Material.Ice },
	wind = {
		colors = { Color3.fromRGB(205, 230, 250) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.85,
	},
	-- Speed strips: yellow speeds you up, tone 2 (dusky blue) is a back strip that slows you.
	boost = {
		colors = { Color3.fromRGB(255, 215, 50), Color3.fromRGB(110, 120, 200) },
		material = Enum.Material.SmoothPlastic,
	},
	-- Belts: orange pushes right, blue pushes left.
	belt = {
		colors = { Color3.fromRGB(255, 150, 50), Color3.fromRGB(70, 170, 255) },
		material = Enum.Material.SmoothPlastic,
	},
	-- A key is small, so a Neon body is fine (it reads as a gold glint, not a bloom).
	key = { colors = { Color3.fromRGB(255, 205, 60) }, material = Enum.Material.Neon },
	gate = { colors = { Color3.fromRGB(150, 90, 220) }, material = Enum.Material.SmoothPlastic, transparency = 0.2 },
	moon = {
		colors = { Color3.fromRGB(200, 190, 255) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.86,
	},
	dark = {
		colors = { Color3.fromRGB(25, 20, 50) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.7,
	},
}

-- Old look names some drafts still use, mapped onto the one look for their behaviour.
local ALIASES: { [string]: string } = {
	trampoline = "spring",
	puncher = "hazard",
	gust = "wind",
}

-- Decor colours and sizes (studs).
local MARK = table.freeze({
	ink = Color3.fromRGB(40, 30, 60), -- chevrons and arrows on light floors
	light = Color3.fromRGB(255, 255, 255), -- chevrons and arrows on dark floors, rings, rails
	print = Color3.fromRGB(95, 145, 20), -- handprints on sticky walls
	crack = Color3.fromRGB(60, 40, 45),
	star = Color3.fromRGB(255, 220, 80),
	lockOff = Color3.fromRGB(70, 60, 90), -- a lock still shut (ObbyFx turns it gold per key)
	lift = 0.03, -- flat decor sits this far above the top it lies on, so it never z-fights
	flat = 0.06, -- thickness of flat decor (chevrons, arrows, cracks)
	bar = 0.4, -- width of a chevron or arrow stroke
	printSize = 1.4, -- handprint diameter
	railHeight = 0.35,
	railWidth = 0.25,
	starSize = 1.6, -- each of the star's two squares
	starLift = 2.5, -- the star's centre above the top
	ghostTransparency = 0.82,
	lockSize = Vector3.new(0.9, 0.8, 0.3), -- body; the shackle is a ring adornment on top
	lockGap = 1.3, -- lock spacing on the gate face
})

-- Sign boards (sign:<text> markers). The text line is 1.3 studs: about 26 studs read distance on a phone.
local SIGN = table.freeze({
	size = Vector3.new(8, 1.8, 0.2),
	lift = 4.5, -- bottom of the board above the host's top: above a character's head
	maxDistance = 60,
})

-- Particle rates are kept low on purpose: a course can have a dozen ice or wind parts in view.
local FX = table.freeze({
	sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	frostRate = 2,
	leafRate = 4,
	keyRate = 4,
	moonRate = 3,
	dripRate = 1.5,
})

-- The Goo Ring home (`Course.home`): the yard's ring at `scale`, standing on the start pad's back edge and facing
-- along the course, so a runner pops out of it facing the sections. "BACK TO BASE" is painted on the start pad in
-- front of it (a SurfaceGui on the pad's top: a 1.1-stud line reads from the start pad on a phone).
local HOME = table.freeze({
	scale = 0.72, -- of the yard ring: about 9 studs tall, a 6-stud opening a character walks through
	labelSize = Vector3.new(1.5, 0.05, 6.4), -- studs, lying on the start pad (a Top canvas is Z wide, X tall)
	labelInset = 4.6, -- studs from the ring's middle to the label's centre: clear of the ring's puddle
	labelTurn = 90, -- degrees about Y
	maxDistance = 60,
	text = "BACK TO BASE",
})

local ICE = PhysicalProperties.new(0.9, 0, 0.5, 100, 1)

-- Behaviour fields that go into ObbySpec (contract §10b), exactly these.
local SPEC_FIELDS = {
	"motion",
	"hazard",
	"boost",
	"slide",
	"sticky",
	"vine",
	"cannon",
	"zone",
	"key",
	"gate",
	"trigger",
	"start",
	"beat",
	"conveyor",
	"marker",
}

-- A part as ObbyParts reads it: ObbyCourse.Part plus the section-kit fields (contract §3, §10b). Read through this
-- type so this module does not depend on how ObbyCourse spells its own types.
type Vec = { number }
type PartSpec = {
	id: string?,
	size: Vec,
	pos: Vec,
	look: string,
	shape: string?,
	ghost: boolean?,
	motion: { [string]: any }?,
	conveyor: Vec?,
	ice: boolean?,
	tone: number?,
	yaw: number?,
	pitch: number?,
	roll: number?,
	hazard: boolean?,
	boost: { speed: number, carry: number? }?,
	slide: { [string]: any }?,
	sticky: { [string]: any }?,
	vine: { [string]: any }?,
	cannon: { [string]: any }?,
	zone: { kind: string, [string]: any }?,
	key: string?,
	gate: { group: string, need: number }?,
	trigger: string?,
	start: string?,
	marker: string?,
	beat: number?,
}

-- The course frame as a CFrame: X forward, Y up, Z right (ObbyCourse's course-local axes).
function ObbyParts.frameCFrame(frame: ObbyCourse.Frame): CFrame
	local a = math.rad(frame.yaw)
	local forward = Vector3.new(math.sin(a), 0, math.cos(a))
	local right = Vector3.new(-math.cos(a), 0, math.sin(a))
	local o = frame.origin
	return CFrame.fromMatrix(Vector3.new(o[1], o[2], o[3]), forward, Vector3.yAxis, right)
end

local function decor(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- The look a part shows: a behaviour forces its one look (contract §8), else the data's look (old names aliased).
local function lookName(spec: PartSpec): string
	if spec.hazard then
		return "hazard"
	elseif spec.key then
		return "key"
	elseif spec.gate then
		return "gate"
	elseif spec.zone and spec.zone.kind == "moon" then
		return "moon"
	elseif spec.zone and spec.zone.kind == "dark" then
		return "dark"
	elseif spec.sticky then
		return "sticky"
	elseif spec.slide then
		return "ice"
	end
	return ALIASES[spec.look] or spec.look
end

-- True when the part has any behaviour field, so it needs ObbySpec and ObbyBase.
local function specOf(spec: PartSpec): { [string]: any }?
	local raw = spec :: any
	local out: { [string]: any } = {}
	local any = false
	for _, field in SPEC_FIELDS do
		if raw[field] ~= nil then
			out[field] = raw[field]
			any = true
		end
	end
	return if any then out else nil
end

--------------------------------------------------------------------------------------------------------------------
-- Particles and adornments (no parts: they don't count toward the budget)

local function emitter(parent: Instance, color: ColorSequence, rate: number, props: { [string]: any }): ParticleEmitter
	local fx = Instance.new("ParticleEmitter")
	fx.Texture = FX.sparkles
	fx.Color = color
	fx.Rate = rate
	fx.LightEmission = 0.6
	fx.Lifetime = NumberRange.new(1, 1.6)
	fx.Speed = NumberRange.new(0.5, 1)
	fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	fx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fx.RotSpeed = NumberRange.new(-90, 90)
	for k, v in props do
		(fx :: any)[k] = v
	end
	fx.Parent = parent
	return fx
end

-- A flat ring (a real hole in the middle) lying on `adornee`'s local XZ plane at `offset`.
local function ringAdornment(adornee: BasePart, offset: CFrame, outer: number, inner: number, color: Color3)
	local ring = Instance.new("CylinderHandleAdornment")
	ring.Adornee = adornee
	-- A cylinder adornment's axis is its Z: tip it onto Y so the ring lies flat.
	ring.CFrame = offset * CFrame.Angles(math.rad(90), 0, 0)
	ring.Radius = outer
	ring.InnerRadius = inner
	ring.Height = MARK.flat
	ring.Color3 = color
	ring.Transparency = 0.1
	ring.ZIndex = 0
	ring.Parent = adornee
end

-- The particles and adornments each behaviour look carries. `size` is the data size (x, y, z) and `up` the part's
-- face that points up (a disc is a cylinder laid on its side: its top is its Right face).
local function lookFx(part: BasePart, look: string, size: Vector3, up: Enum.NormalId)
	if look == "ice" then
		emitter(part, ColorSequence.new(Color3.fromRGB(235, 250, 255)), FX.frostRate, {
			EmissionDirection = up,
		})
	elseif look == "wind" then
		-- Leaves rising up the column, roughly reaching its top.
		local speed = 10
		emitter(part, ColorSequence.new(Color3.fromRGB(150, 220, 90), Color3.fromRGB(240, 250, 220)), FX.leafRate, {
			EmissionDirection = up,
			Speed = NumberRange.new(speed * 0.8, speed),
			Lifetime = NumberRange.new(math.clamp(size.Y / speed, 0.6, 3)),
			Size = NumberSequence.new(0.4),
			SpreadAngle = Vector2.new(10, 10),
		})
		-- Two faint rings round the column's top: "you rise to here".
		local radius = math.min(size.X, size.Z) / 2
		local top = CFrame.new(0, size.Y / 2, 0)
		ringAdornment(part, top, radius, radius - 0.3, MARK.light)
		ringAdornment(part, top * CFrame.new(0, -1, 0), radius * 0.8, radius * 0.8 - 0.25, MARK.light)
	elseif look == "key" then
		emitter(part, ColorSequence.new(Color3.fromRGB(255, 240, 160)), FX.keyRate, { LightEmission = 1 })
	elseif look == "moon" then
		emitter(part, ColorSequence.new(Color3.fromRGB(230, 220, 255)), FX.moonRate, {
			Speed = NumberRange.new(0.2, 0.5),
			Lifetime = NumberRange.new(2, 3),
			LightEmission = 1,
		})
	elseif look == "sticky" then
		-- Slow drops falling off the goo.
		emitter(part, ColorSequence.new(Color3.fromRGB(175, 240, 40)), FX.dripRate, {
			EmissionDirection = Enum.NormalId.Bottom,
			Acceleration = Vector3.new(0, -20, 0),
			LightEmission = 0,
			Size = NumberSequence.new(0.3),
		})
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Markers: small anchored ghost parts directly under their host (see the header)

-- An anchored decor part directly under `host`, at world CFrame `cf` (ObbyFx moves it with the host).
local function stuck(
	host: BasePart,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	decor(part)
	part.Parent = host
	return part
end

-- Rotates a flat direction (x, z) by `angle` radians in the XZ plane.
local function turn(x: number, z: number, angle: number): (number, number)
	local c, s = math.cos(angle), math.sin(angle)
	return x * c - z * s, x * s + z * c
end

-- A flat stroke lying on the top frame `top` (Y up), centred at (x, z), running along direction (dx, dz).
local function flatStroke(
	host: BasePart,
	name: string,
	top: CFrame,
	x: number,
	z: number,
	dx: number,
	dz: number,
	length: number,
	color: Color3
)
	local cf = top * CFrame.new(x, MARK.lift + MARK.flat / 2, z) * CFrame.Angles(0, math.atan2(-dz, dx), 0)
	stuck(host, name, Vector3.new(length, MARK.flat, MARK.bar), cf, color)
end

-- The flat way a marker points on the part's top, in the part's own axes: its belt direction, else forward (+X).
local function pointing(spec: PartSpec, ref: CFrame, frameCf: CFrame): (number, number)
	local v = spec.conveyor
	if v then
		local world = frameCf:VectorToWorldSpace(Vector3.new(v[1], v[2], v[3]))
		local here = ref:VectorToObjectSpace(world)
		local flat = Vector3.new(here.X, 0, here.Z)
		if flat.Magnitude > 1e-3 then
			flat = flat.Unit
			return flat.X, flat.Z
		end
	end
	return 1, 0
end

-- `ref` is the part's CFrame without the disc turn (Y up through its top), `s` its data size (x, y, z).
local function addMarker(
	host: BasePart,
	spec: PartSpec,
	kind: string,
	ref: CFrame,
	s: Vector3,
	frameCf: CFrame,
	model: Instance
)
	local top = ref * CFrame.new(0, s.Y / 2, 0)
	local short = math.min(s.X, s.Z)
	local onDark = lookName(spec) == "belt" or lookName(spec) == "gate"
	local ink = if onDark then MARK.light else MARK.ink
	local rings = string.match(kind, "^rings([123])$")
	if rings then
		-- 1-3 rings for a spring's power, on one invisible carrier.
		local carrier =
			stuck(host, "Rings", Vector3.new(short, MARK.flat, short), top * CFrame.new(0, MARK.lift, 0), MARK.light)
		carrier.Transparency = 1
		local outer = short * 0.42
		for i = 1, tonumber(rings) :: number do
			local r = outer * (1 - (i - 1) * 0.3)
			ringAdornment(carrier, CFrame.identity, r, r - 0.35, MARK.light)
		end
	elseif kind == "chevrons" or kind == "arrows" then
		local dx, dz = pointing(spec, ref, frameCf)
		local length = math.clamp(short * 0.3, 0.8, 3)
		local reach = math.abs(dx) * s.X / 2 + math.abs(dz) * s.Z / 2 -- half the top's extent along the arrow
		local spacing = math.min(length * 1.4, reach * 0.6)
		local tips: { number } = if kind == "chevrons" then { -spacing / 2, spacing / 2 } else { length * 0.6 }
		for i, along in tips do
			local tx, tz = dx * along, dz * along
			for _, side in { 3 * math.pi / 4, -3 * math.pi / 4 } do
				local ax, az = turn(dx, dz, side)
				local half = length * 0.5
				flatStroke(host, "Chevron", top, tx + ax * half * 0.9, tz + az * half * 0.9, ax, az, length, ink)
			end
			if kind == "arrows" and i == 1 then
				flatStroke(
					host,
					"Arrow",
					top,
					tx - dx * length * 0.75,
					tz - dz * length * 0.75,
					dx,
					dz,
					length * 1.5,
					ink
				)
			end
		end
	elseif kind == "handprints" then
		-- Each print is a short cylinder through the wall's thin axis, so one part shows on both faces.
		local thinX = s.X < s.Z
		local long = if thinX then s.Z else s.X
		local thick = math.min(s.X, s.Z) + 0.12
		local spots = { { -0.25, 0.2 }, { 0.15, -0.1 }, { 0.3, 0.3 } } -- fractions of (long, height) from the centre
		for _, p in spots do
			local along, up = p[1] * long, p[2] * s.Y
			local at = if thinX
				then CFrame.new(0, up, along)
				else CFrame.new(along, up, 0) * CFrame.Angles(0, math.rad(90), 0)
			local hand =
				stuck(host, "Handprint", Vector3.new(thick, MARK.printSize, MARK.printSize), ref * at, MARK.print)
			hand.Shape = Enum.PartType.Cylinder
		end
	elseif kind == "cracks" then
		-- Fixed-looking cracks across the top; ObbyFx darkens them in during the melt/drop warning.
		local length = math.clamp(short * 0.5, 1, 5)
		local cracks = { { -0.2, -0.15, 20 }, { 0.15, 0.2, -35 }, { 0.05, -0.25, 70 } } -- (x, z fraction, degrees)
		for _, c in cracks do
			local a = math.rad(c[3])
			flatStroke(host, "Crack", top, c[1] * s.X, c[2] * s.Z, math.cos(a), math.sin(a), length, MARK.crack)
		end
	elseif kind == "star" then
		-- Two squares turned 45 degrees apart: an eight-point star floating over the part, facing the runner.
		local centre = top * CFrame.new(0, MARK.starLift, 0) * CFrame.Angles(0, math.rad(90), 0)
		local size = Vector3.new(MARK.starSize, MARK.starSize, 0.2)
		local a = stuck(host, "Star", size, centre, MARK.star, Enum.Material.Neon)
		stuck(host, "Star", size, centre * CFrame.Angles(0, 0, math.rad(45)), MARK.star, Enum.Material.Neon)
		emitter(a, ColorSequence.new(Color3.fromRGB(255, 240, 170)), FX.keyRate, { LightEmission = 1 })
	elseif kind == "rail" then
		-- Low bars along both long edges of the top.
		local alongX = s.X >= s.Z
		local length = if alongX then s.X else s.Z
		local edge = (if alongX then s.Z else s.X) / 2 - MARK.railWidth / 2
		for _, side in { -1, 1 } do
			local at = if alongX
				then CFrame.new(0, MARK.railHeight / 2, side * edge)
				else CFrame.new(side * edge, MARK.railHeight / 2, 0)
			local size = if alongX
				then Vector3.new(length, MARK.railHeight, MARK.railWidth)
				else Vector3.new(MARK.railWidth, MARK.railHeight, length)
			stuck(host, "Rail", size, top * at, MARK.light).Transparency = 0.2
		end
	elseif kind == "ghostStop" then
		-- A see-through copy where the part stops: both ends of a slide, the far end of a punch, the farthest point
		-- of a path. Anchored in the world (it must not follow the host).
		local m = spec.motion
		local offsets: { Vector3 } = {}
		if m and (m.kind == "slide" or m.kind == "punch") then
			-- Kit.offsetAt's axes: "x", "z", anything else (nil included) is up.
			local axis = if m.axis == "x" then Vector3.xAxis elseif m.axis == "z" then Vector3.zAxis else Vector3.yAxis
			local amp = (m.amp :: number?) or 0
			table.insert(offsets, axis * amp)
			if m.kind == "slide" then
				table.insert(offsets, -axis * amp)
			end
		elseif m and m.kind == "path" and type(m.points) == "table" then
			local far = Vector3.zero
			for _, p in m.points :: { Vec } do
				local v = Vector3.new(p[1], p[2], p[3])
				if v.Magnitude > far.Magnitude then
					far = v
				end
			end
			table.insert(offsets, far)
		end
		for _, offset in offsets do
			local ghost = host:Clone()
			ghost:ClearAllChildren()
			for name in ghost:GetAttributes() do
				ghost:SetAttribute(name, nil)
			end
			ghost.Name = "GhostStop"
			ghost.CFrame = host.CFrame + frameCf:VectorToWorldSpace(offset)
			ghost.Transparency = MARK.ghostTransparency
			ghost.AssemblyLinearVelocity = Vector3.zero
			decor(ghost)
			ghost:SetAttribute("ObbyHost", spec.id)
			ghost.Parent = model
		end
	elseif string.sub(kind, 1, 5) == "sign:" then
		-- A small board over the part's near (-X) end, its face towards the runner coming from -X.
		local text = string.sub(kind, 6)
		local at = CFrame.new(-s.X / 2 + 0.5, SIGN.lift + SIGN.size.Y / 2, 0) * CFrame.Angles(0, math.rad(90), 0)
		local board = stuck(host, "Sign", SIGN.size, top * at, ObbyParts.COLORS.sign)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = ObbyParts.PIXELS_PER_STUD
		gui.MaxDistance = SIGN.maxDistance
		gui.LightInfluence = 0
		gui.Adornee = board
		ObbyParts.signLabel(gui, "Text", text, 0.14, 0.72, ObbyParts.PIXELS_PER_STUD)
		gui.Parent = board
	end
end

-- Lock icons on a gate, one per key it needs, across the face the runner meets (the thinner horizontal axis). Each
-- lock body goes through the gate so it shows on both faces; its shackle is a ring adornment. Named "Lock1".."LockN"
-- (attribute ObbyLock = n); ObbyFx turns them gold as keys come in.
local function addLocks(host: BasePart, need: number, ref: CFrame, s: Vector3)
	local thinX = s.X < s.Z
	local depth = math.min(s.X, s.Z) + 0.12
	for i = 1, need do
		local along = (i - (need + 1) / 2) * MARK.lockGap
		local at = if thinX
			then CFrame.new(0, 0, along)
			else CFrame.new(along, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
		local size = Vector3.new(depth, MARK.lockSize.Y, MARK.lockSize.X)
		local lock = stuck(host, "Lock" .. i, size, ref * at, MARK.lockOff)
		lock:SetAttribute("ObbyLock", i)
		-- The shackle: an upright ring over the body, facing the way the gate does.
		local shackle = Instance.new("CylinderHandleAdornment")
		shackle.Adornee = lock
		shackle.CFrame = CFrame.new(0, MARK.lockSize.Y / 2 + 0.2, 0) * CFrame.Angles(0, math.rad(90), 0)
		shackle.Radius = 0.32
		shackle.InnerRadius = 0.2
		shackle.Height = depth
		shackle.Color3 = MARK.lockOff
		shackle.Parent = lock
	end
end

--------------------------------------------------------------------------------------------------------------------
-- Parts

local function makePart(data: ObbyCourse.Part, frameCf: CFrame, model: Instance)
	local spec = (data :: any) :: PartSpec
	local lookId = lookName(spec)
	local look = LOOKS[lookId] or LOOKS.pad
	local part: BasePart = if spec.shape == "truss" then Instance.new("TrussPart") else Instance.new("Part")
	part.Name = lookId
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = look.material
	local tone = spec.tone or (if spec.boost and spec.boost.speed < 16 then 2 else 1) -- 16 = normal WalkSpeed
	part.Color = look.colors[math.clamp(tone, 1, #look.colors)]
	part.Transparency = look.transparency or 0
	part.CastShadow = false
	local turnCf =
		CFrame.fromEulerAnglesYXZ(math.rad(spec.pitch or 0), math.rad(spec.yaw or 0), math.rad(spec.roll or 0))
	local ref = frameCf * CFrame.new(spec.pos[1], spec.pos[2], spec.pos[3]) * turnCf
	local s = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
	if spec.shape == "disc" then
		-- A cylinder's axis is its X: lay it on its side so a flat face points up.
		(part :: Part).Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(s.Y, s.X, s.Z)
		part.CFrame = ref * CFrame.Angles(0, 0, math.rad(90))
	else
		if spec.shape == "ball" then
			(part :: Part).Shape = Enum.PartType.Ball
		elseif spec.shape == "log" then
			-- A cylinder's axis is its X, which already runs along the course.
			(part :: Part).Shape = Enum.PartType.Cylinder
		end
		part.Size = s
		part.CFrame = ref
	end
	if lookId == "moon" then
		-- The moon zone's box shows as a bubble dome filling it.
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end

	-- Collision. Hazards, keys and zones never hold you up; hazards and keys are found by touch (CanTouch), zones by
	-- ObbyMoves' box maths. None of them take queries, so ground raycasts (ObbyFx, ObbyFall) never stand on them.
	local touchy = spec.hazard or spec.key ~= nil or spec.trigger ~= nil or spec.vine ~= nil or spec.cannon ~= nil
	if spec.ghost or spec.hazard or spec.key or spec.zone then
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = touchy == true
	end
	if spec.ice or spec.slide then
		part.CustomPhysicalProperties = ICE
	end
	if spec.conveyor then
		local v = spec.conveyor
		part.AssemblyLinearVelocity = frameCf.XVector * v[1] + frameCf.YVector * v[2] + frameCf.ZVector * v[3]
	end

	if spec.id then
		part:SetAttribute(Constants.OBBY_ID, spec.id)
	end
	local behaviour = specOf(spec)
	if behaviour then
		part:SetAttribute(Constants.OBBY_SPEC, HttpService:JSONEncode(behaviour))
		part:SetAttribute(Constants.OBBY_BASE, part.CFrame)
	end
	part.Parent = model

	lookFx(part, lookId, s, if spec.shape == "disc" then Enum.NormalId.Right else Enum.NormalId.Top)
	if spec.gate then
		addLocks(part, math.max(1, spec.gate.need), ref, s)
	end
	if spec.marker then
		addMarker(part, spec, spec.marker, ref, s, frameCf, model)
	end
end

function ObbyParts.signLabel(parent: Instance, name: string, text: string, y: number, h: number, maxSize: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.05, y)
	label.Size = UDim2.fromScale(0.9, h)
	label.Font = ObbyParts.FONT
	label.Text = text
	label.TextColor3 = ObbyParts.COLORS.ink
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = ObbyParts.COLORS.stroke
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = parent
end

-- The Goo Ring: kit meshes (shared/modeling-kit models obby_goo_ring, obby_goo_swirl; Shared.MeshAssets), shared by
-- the yard portal (server/ObbyView, swapped by server/MeshSwap) and the ring home (buildHome, swapped on the client by
-- visuals/client/ObbyCourseView). The numbers are the yard size (scale 1), from the kit model.
ObbyParts.GOO = table.freeze({
	ring = "obby_goo_ring_eyes", -- MeshAsset names
	swirl = "obby_goo_swirl",
	ringSize = Vector3.new(12.489, 12.076, 5.438), -- the ring mesh's native size (studs)
	swirlSize = Vector3.new(9.2, 9.2, 0.9),
	centre = 5.914, -- the ring's centre above its foot (the kit model's CZ)
	swirlBack = 0.3, -- the swirl stands this far behind the ring's middle, so the drips hang in front of it
	spin = 1.2, -- radians a second the swirl turns (visuals/client/ObbyFx)
	-- The ring, swirl and sign kit models were built facing kit +Y, so after the import yaw they face the slot's +Z:
	-- their slots are turned this much so the eyes and the sign's face look along the slot's front (-Z).
	faceTurn = CFrame.Angles(0, math.pi, 0),
	glow = Color3.fromRGB(170, 120, 255),
	sparkle = { Color3.fromRGB(255, 200, 245), Color3.fromRGB(190, 160, 255) },
})

-- An invisible, non-colliding box the mesh swap fills with kit mesh `name` (attribute MeshAsset).
local function meshSlot(name: string, asset: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Transparency = 1
	decor(part)
	part:SetAttribute("MeshAsset", asset)
	part.Parent = parent
	return part
end

-- A standing Goo Ring at `scale` of the yard size: the ring mesh and the swirl inside it, which turns on each client
-- (Constants.GOO_SPIN and GOO_PIVOT on the swirl's slot, played by visuals/client/ObbyFx) with a purple glow and
-- sparkles drifting into it. `ground` is the point under the ring's centre, its LookVector the way the eyes face (you
-- walk through along that axis). Decor only. Names are `prefix` .. "GooRing" / "GooSwirl". Returns the swirl slot.
function ObbyParts.gooRing(ground: CFrame, scale: number, parent: Instance, prefix: string): Part
	local G = ObbyParts.GOO
	local size = G.ringSize * scale
	meshSlot(prefix .. "GooRing", G.ring, size, ground * CFrame.new(0, size.Y / 2, 0) * G.faceTurn, parent)
	local centre = ground * CFrame.new(0, G.centre * scale, G.swirlBack * scale) -- +Z: away from the way it faces
	local swirl = meshSlot(prefix .. "GooSwirl", G.swirl, G.swirlSize * scale, centre * G.faceTurn, parent)
	swirl:SetAttribute(Constants.GOO_SPIN, G.spin)
	swirl:SetAttribute(Constants.GOO_PIVOT, centre)
	local light = Instance.new("PointLight")
	light.Color = G.glow
	light.Brightness = 1.6
	light.Range = 14 * scale
	light.Shadows = false
	light.Parent = swirl
	-- Sparkles drifting in towards the vortex's core: a disc emitter in the ring's plane, shooting inwards.
	local at = Instance.new("Attachment")
	at.Name = "Sparkles"
	at.CFrame = CFrame.Angles(math.rad(90), 0, 0) -- the attachment's Y axis along the ring's normal: its disc is the swirl
	at.Parent = swirl
	local fx = Instance.new("ParticleEmitter")
	fx.Shape = Enum.ParticleEmitterShape.Disc
	fx.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	fx.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	fx.ShapePartial = 1
	fx.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fx.Color = ColorSequence.new(G.sparkle[1], G.sparkle[2])
	fx.LightEmission = 1
	fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * scale), NumberSequenceKeypoint.new(1, 0) })
	fx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fx.Lifetime = NumberRange.new(1.2, 1.8)
	fx.Speed = NumberRange.new(2 * scale, 2.6 * scale)
	fx.Rate = 10
	fx.RotSpeed = NumberRange.new(-90, 90)
	fx.LockedToPart = true
	fx.Parent = at
	return swirl
end

-- The Goo Ring home on the start pad's back edge (x = 0 in the course frame), facing along the course, and the
-- "BACK TO BASE" label painted on the start pad in front of it.
local function buildHome(frameCf: CFrame, parent: Instance)
	local ground = frameCf * CFrame.lookAt(Vector3.zero, Vector3.xAxis) -- course-local: X forward, the eyes look down it
	ObbyParts.gooRing(ground, HOME.scale, parent, "Home")
	local label = Instance.new("Part")
	label.Name = "HomeLabel"
	label.Size = HOME.labelSize
	label.Transparency = 1
	-- lying on the pad's top, turned so the text runs across the course and reads from the start pad
	label.CFrame = ground
		* CFrame.new(0, HOME.labelSize.Y / 2 + 0.01, -HOME.labelInset)
		* CFrame.Angles(0, math.rad(HOME.labelTurn), 0)
	decor(label)
	label.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Name = "HomeLabelGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ObbyParts.PIXELS_PER_STUD
	gui.MaxDistance = HOME.maxDistance
	gui.LightInfluence = 0
	gui.Adornee = label
	ObbyParts.signLabel(gui, "Title", HOME.text, 0.08, 0.84, ObbyParts.PIXELS_PER_STUD)
	gui.Parent = label
end

-- The course as a Model named Constants.OBBY_COURSE (attributes Slot and ObbyFrame), in the frame given; not
-- parented.
function ObbyParts.build(course: ObbyCourse.Course, frame: ObbyCourse.Frame): Model
	local model = Instance.new("Model")
	model.Name = Constants.OBBY_COURSE
	model:SetAttribute("Slot", course.slot)
	local frameCf = ObbyParts.frameCFrame(frame)
	model:SetAttribute(Constants.OBBY_FRAME, frameCf)
	for _, spec in course.parts do
		makePart(spec, frameCf, model)
	end
	buildHome(frameCf, model)
	return model
end

return ObbyParts
