--!strict
--[[
	SlimeShineView (Roblox adapter)
	A shining slime (Genome.Slime.shine, Config.SHINES) sparkles in its shine's colour: one ParticleEmitter
	"ShineFx" on its Body, made when the shine appears and removed when it goes. A model without a shine has none.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)
local Genome = require(ReplicatedStorage.Shared.Genome)

local SlimeShineView = {}

local FX = "ShineFx"
local TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

-- Colour sequence of a shine: Rainbow cycles hues, the others are their own colour.
local function colors(row: any): ColorSequence
	if row.id == "Rainbow" then
		local keys = {}
		for i = 0, 6 do
			table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.6, 1)))
		end
		return ColorSequence.new(keys)
	end
	return ColorSequence.new(Color3.fromRGB(row.color[1], row.color[2], row.color[3]))
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
	local e = Instance.new("ParticleEmitter")
	e.Name = FX
	e.Texture = TEXTURE
	e.Color = colors(row)
	e.LightEmission = 0.8
	e.Rate = if row.id == "Rainbow" then 14 else 8
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e:SetAttribute("Shine", row.id)
	e.Parent = body
end

return SlimeShineView
