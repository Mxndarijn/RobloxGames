--!strict
--[[
	SlimeShineView (Roblox adapter)
	A shining slime (Genome.Slime.shine, Config.SHINES) sparkles in its shine's colour: one ParticleEmitter
	"ShineFx" on its Body, made when the shine appears and removed when it goes. A model without a shine has none.
	The sparkles twinkle on the slime's surface (white glints fading into the shine's colour, a rainbow for a rainbow
	shine), matching its recoloured kit (SlimeMesh).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local Genome = require(ReplicatedStorage.Shared.Genome)

local SlimeShineView = {}

local FX = "ShineFx"
local TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- Particles per second, by shine.
local RATE = table.freeze({ Gold = 12, Diamond = 16, Rainbow = 12 })

-- Colour sequence of a shine: a rainbow shine cycles hues, the others a white glint fading into their colour.
local function colors(row: Genome.ShineRow): ColorSequence
	if row.rainbow then
		local keys = {}
		for i = 0, 6 do
			table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.7, 1)))
		end
		return ColorSequence.new(keys)
	end
	return ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(row.color[1], row.color[2], row.color[3]))
end

local function emitter(row: Genome.ShineRow): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = FX
	e.Texture = TEXTURE
	e.Color = colors(row)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.Rate = RATE[row.id] or 12
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(0.2, 0.8)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	return e
end

function SlimeShineView.apply(model: Model, slime: Genome.Slime)
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body then
		return
	end
	local row = Genome.shine(slime)
	local fx = body:FindFirstChild(FX)
	model:SetAttribute(Constants.SHINE_ATTRIBUTE, if row then row.id else nil)
	if not row then
		if fx then
			fx:Destroy()
		end
		return
	end
	if fx and fx:GetAttribute("Shine") == row.id then
		return
	end
	if fx then
		fx:Destroy()
	end
	local e = emitter(row)
	e:SetAttribute("Shine", row.id)
	e.Parent = body
end

return SlimeShineView
