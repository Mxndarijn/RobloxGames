--!strict
--[[
	SlimeShineView (Roblox adapter)
	A shining slime (Genome.Slime.shine, Config.SHINES) sparkles in its shine's colour: one ParticleEmitter
	"ShineFx" on its Body, made when the shine appears and removed when it goes. A model without a shine has none.
	With FEATURES.MutationLooks the sparkles are bigger and twinkle on the slime's surface (white glints fading into
	the shine's colour), matching its recoloured kit (SlimeMesh).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Genome = require(ReplicatedStorage.Shared.Genome)

local SlimeShineView = {}

local FX = "ShineFx"
local TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- Particles per second of the MutationLooks sparkles, by shine.
local RATE = table.freeze({ Gold = 12, Diamond = 16, Rainbow = 12 })

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Colour sequence of a shine: a rainbow shine cycles hues, the others are their own colour (with MutationLooks a
-- white glint fading into it).
local function colors(row: Genome.ShineRow, looks: boolean): ColorSequence
	if row.rainbow then
		local keys = {}
		for i = 0, 6 do
			table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, if looks then 0.7 else 0.6, 1)))
		end
		return ColorSequence.new(keys)
	end
	if looks then
		return ColorSequence.new(Color3.new(1, 1, 1), rgb(row.color))
	end
	return ColorSequence.new(rgb(row.color))
end

local function emitter(row: Genome.ShineRow, looks: boolean): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = FX
	e.Texture = TEXTURE
	e.Color = colors(row, looks)
	e.SpreadAngle = Vector2.new(180, 180)
	if looks then
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
	else
		e.LightEmission = 0.8
		e.Rate = if row.rainbow then 14 else 8
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	end
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
	local e = emitter(row, Config.FEATURES.MutationLooks == true)
	e:SetAttribute("Shine", row.id)
	e.Parent = body
end

return SlimeShineView
