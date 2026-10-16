--!strict
--[[
	RareSpawn (owner: Archer)

	Client-only "rare drop" effects on wild slimes (model attribute
	State == "Wild"), scaled by the factory's Tier attribute (1..6):

	  tier 1  nothing
	  tier 2  soft PointLight glow, faint ground ring
	  tier 3  + sparkles, short thin beam
	  tier 4  + taller beam, brighter ring
	  tier 5  + beam with a white core, more sparkles
	  tier 6  + tallest beam (still MAX_BEAM_HEIGHT), second ring, strongest glow
	            (VisualsClient cycles its colour)

	RareSpawn.build(tier, size?) -> Model?   (nil for tier 1 / unknown)
	RareSpawn.place(fx, pivot, t)            moves it to a slime's pivot
	                                         (bottom centre) and pulses it

	The Model's parts are anchored, massless, CanCollide / CanQuery /
	CanTouch false. VisualsClient keeps them in a local folder and never
	parents them into the replicated slime model. Pure preset data, no
	services touched at load time (the render proof builds it under Lune).
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local Effects = if script then require(script.Parent.Effects) else require("./Effects")

export type TierFx = {
	glow: { brightness: number, range: number }?,
	sparkles: number?, -- RareSparkle particles/s
	beam: { height: number, width: number, core: boolean? }?,
	rings: number?, -- ground rings
}

local RareSpawn = {}

-- A beam is a marker over its slime, not a sky pillar: at night the Neon beams (rarity colours, bloom) read as
-- huge glowing streaks, so every tier stays under these bounds (guarded by tests/RareSpawn.spec.luau).
RareSpawn.MAX_BEAM_HEIGHT = 24
RareSpawn.MAX_BEAM_WIDTH = 1
RareSpawn.BEAM_TRANSPARENCY = 0.7

RareSpawn.TIERS = table.freeze({
	{},
	{ glow = { brightness = 1.5, range = 8 }, rings = 1 },
	{ glow = { brightness = 1.5, range = 10 }, sparkles = 4, beam = { height = 8, width = 0.3 } },
	{ glow = { brightness = 2, range = 14 }, sparkles = 7, beam = { height = 12, width = 0.45 }, rings = 1 },
	{
		glow = { brightness = 3, range = 18 },
		sparkles = 10,
		beam = { height = 16, width = 0.6, core = true },
		rings = 1,
	},
	{
		glow = { brightness = 4, range = 24 },
		sparkles = 14,
		beam = { height = 22, width = 0.8, core = true },
		rings = 2,
	},
}) :: { TierFx }

function RareSpawn.color(tier: number): Color3
	local rarity = Config.RARITIES[tier] or Config.RARITIES[1]
	local c = rarity.color
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(name: string, shape: Enum.PartType, size: Vector3, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Anchored = true
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- Offsets from the slime pivot (bottom centre), so place() can re-pose every
-- part from the pivot alone.
local offsets: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

local function at(p: Part, offset: CFrame)
	offsets[p] = offset
end

function RareSpawn.build(tier: number, size: number?): Model?
	local fx = RareSpawn.TIERS[tier]
	if not fx or not (fx.glow or fx.beam or fx.sparkles) then
		return nil
	end
	local color = RareSpawn.color(tier)
	local d = Config.SLIME_BASE_DIAMETER * (size or 1)
	local model = Instance.new("Model")
	model.Name = `RareFx_{tier}`
	model:SetAttribute("Tier", tier)

	local core = part("Core", Enum.PartType.Ball, Vector3.new(d, d, d), color, 1)
	at(core, CFrame.new(0, d / 2, 0))
	core.Parent = model
	model.PrimaryPart = core
	if fx.glow then
		local light = Instance.new("PointLight")
		light.Name = "RareGlow"
		light.Color = color
		light.Brightness = fx.glow.brightness
		light.Range = fx.glow.range
		light.Shadows = false
		light.Parent = core
	end
	if fx.sparkles then
		local e = Effects.emitter("RareSparkle")
		e.Rate = fx.sparkles
		e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		e.Parent = core
	end
	if fx.beam then
		local b = fx.beam
		-- Roblox cylinders run along X: roll 90 degrees to stand them up.
		local up = CFrame.new(0, b.height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		local beam = part(
			"Beam",
			Enum.PartType.Cylinder,
			Vector3.new(b.height, b.width, b.width),
			color,
			RareSpawn.BEAM_TRANSPARENCY
		)
		at(beam, up)
		beam.Parent = model
		if b.core then
			local w = b.width * 0.4
			local inner =
				part("BeamCore", Enum.PartType.Cylinder, Vector3.new(b.height, w, w), Color3.new(1, 1, 1), 0.5)
			at(inner, up)
			inner.Parent = model
		end
	end
	for k = 1, fx.rings or 0 do
		local r = d * (1.3 + 0.6 * k)
		local ring = part(`Ring_{k}`, Enum.PartType.Cylinder, Vector3.new(0.12, r, r), color, 0.35 + 0.2 * k)
		at(ring, CFrame.new(0, 0.08 * k, 0) * CFrame.Angles(0, 0, math.rad(90)))
		ring.Parent = model
	end
	return model
end

-- Poses fx on a slime pivot (bottom centre); t (seconds) drives the pulse.
function RareSpawn.place(fx: Model, pivot: CFrame, t: number)
	local base = CFrame.new(pivot.Position)
	for _, child in fx:GetChildren() do
		if child:IsA("BasePart") then
			local offset = offsets[child]
			if offset then
				local spin = if string.find(child.Name, "^Ring_") then CFrame.Angles(t * 0.8, 0, 0) else CFrame.identity
				child.CFrame = base * offset * spin
			end
		end
	end
	local beam = fx:FindFirstChild("Beam")
	if beam and beam:IsA("BasePart") then
		beam.Transparency = RareSpawn.BEAM_TRANSPARENCY + 0.1 * math.sin(t * 3)
	end
end

return table.freeze(RareSpawn)
