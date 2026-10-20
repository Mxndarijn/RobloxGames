--!strict
--[[
	RareSpawn (owner: Archer)

	Client-only "rare drop" effects on wild slimes (model attribute
	State == "Wild"), scaled by the factory's Tier attribute (1..7):

	  tier 1  nothing
	  tier 2  soft PointLight glow
	  tier 3  + sparkles
	  tier 4..6  stronger glow, more sparkles
	  tier 7  the tier 6 look plus `orbit` Neon motes circling the slime
	            (Secret; PlotVisuals also stands a beam on the fountain)

	No beam stands on a slime and nothing lies flat on the ground: no slime
	has a rarity ring under it.

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
	orbit: number?, -- Neon motes circling the slime (place() moves them)
}

local RareSpawn = {}

RareSpawn.TIERS = table.freeze({
	{},
	{ glow = { brightness = 1.5, range = 8 } },
	{ glow = { brightness = 1.5, range = 10 }, sparkles = 4 },
	{ glow = { brightness = 2, range = 14 }, sparkles = 7 },
	{
		glow = { brightness = 3, range = 18 },
		sparkles = 10,
	},
	{
		glow = { brightness = 4, range = 24 },
		sparkles = 14,
	},
	{
		glow = { brightness = 4.5, range = 26 },
		sparkles = 16,
		orbit = 3,
	},
}) :: { TierFx }

-- Orbit radius and height of the motes, in slime diameters.
RareSpawn.ORBIT_RADIUS = 0.85
RareSpawn.ORBIT_HEIGHT = 0.6

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

-- Offset from the slime pivot (bottom centre), kept on the part itself so place() can re-pose every part from
-- the pivot alone. (A weak-keyed side table lost these when the GC collected the child userdata, leaving the
-- parts frozen where the slime spawned.)
RareSpawn.OFFSET_ATTRIBUTE = "FxOffset"

local function at(p: Part, offset: CFrame)
	p:SetAttribute(RareSpawn.OFFSET_ATTRIBUTE, offset)
end

function RareSpawn.build(tier: number, size: number?): Model?
	local fx = RareSpawn.TIERS[tier]
	if not fx or not (fx.glow or fx.sparkles) then
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
	for k = 1, fx.orbit or 0 do
		local m = 0.18 * d
		local mote = part(`Orbit_{k}`, Enum.PartType.Ball, Vector3.new(m, m, m), Color3.new(1, 1, 1), 0.1)
		mote:SetAttribute("Orbit", k)
		at(mote, CFrame.new(0, d * RareSpawn.ORBIT_HEIGHT, 0))
		mote.Parent = model
	end
	model:SetAttribute("Diameter", d)
	return model
end

-- Offset of orbit mote `k` of `n` around a slime `d` studs wide at time `t` (bottom-centre space).
function RareSpawn.orbitOffset(t: number, k: number, n: number, d: number): (number, number, number)
	local a = t * 1.6 + (k - 1) * 2 * math.pi / math.max(n, 1)
	local r = d * RareSpawn.ORBIT_RADIUS
	return math.cos(a) * r, d * RareSpawn.ORBIT_HEIGHT + 0.2 * r * math.sin(t * 2.3 + k), math.sin(a) * r
end

-- Poses fx on a slime pivot (bottom centre); t (seconds) drives the pulse and the orbit.
function RareSpawn.place(fx: Model, pivot: CFrame, t: number)
	local base = CFrame.new(pivot.Position)
	local d = fx:GetAttribute("Diameter")
	local fxTier = fx:GetAttribute("Tier")
	local tierFx = if type(fxTier) == "number" then RareSpawn.TIERS[fxTier] else nil
	local motes = if tierFx then tierFx.orbit or 0 else 0
	for _, child in fx:GetChildren() do
		if child:IsA("BasePart") then
			local offset = child:GetAttribute(RareSpawn.OFFSET_ATTRIBUTE)
			local k = child:GetAttribute("Orbit")
			if type(k) == "number" and type(d) == "number" and typeof(offset) == "CFrame" then
				local x, y, z = RareSpawn.orbitOffset(t, k, motes, d)
				child.CFrame = base + Vector3.new(x, y, z)
			elseif typeof(offset) == "CFrame" then
				child.CFrame = base * offset
			else
				-- never leave a part behind at a stale spot: park it on the slime, invisible
				child.CFrame = base
				child.Transparency = 1
			end
		end
	end
end

-- Children of the fx folder that no live slime owns (orphans to destroy). live: slime -> its fx model.
function RareSpawn.orphans(children: { Instance }, live: { [Model]: Model }): { Instance }
	local owned: { [Instance]: boolean } = {}
	for _, model in live do
		owned[model] = true
	end
	local out = {}
	for _, child in children do
		if not owned[child] then
			table.insert(out, child)
		end
	end
	return out
end

return table.freeze(RareSpawn)
