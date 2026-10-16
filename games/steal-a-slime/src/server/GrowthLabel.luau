--!strict
--[[
	GrowthLabel (Roblox adapter, FEATURES.GrowingSlimes)

	Scales a slime model to its growth and keeps the "Growth N%" BillboardGui
	above it. The text and offsets are pure (Growth). The label is always on top
	so the slime's own mesh, crown or halo never hides it, and floats above the
	whole model rather than above the invisible Body ball.
	Studio only: a model attribute PcwGrowth (whole percent) replaces the real
	growth, so the pc-watcher shot can show a known 50% (never active live).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Genome = require(ReplicatedStorage.Shared.Genome)
local Growth = require(ReplicatedStorage.Shared.Growth)

local GrowthLabel = {}

-- Whole percent to show for this model: the Studio override, else the slime's real growth.
function GrowthLabel.percentFor(model: Instance, slime: Genome.Slime): number
	local override = if RunService:IsStudio() then model:GetAttribute(Constants.GROWTH_OVERRIDE_ATTRIBUTE) else nil
	if type(override) == "number" then
		return Growth.percentAt(override / 100)
	end
	return Growth.percent(slime)
end

local function build(): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = Constants.GROWTH_LABEL_NAME
	billboard.Size = UDim2.fromOffset(120, 26)
	billboard.MaxDistance = 80
	billboard.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(190, 255, 170)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard
	return billboard
end

-- Re-applied only when the whole percent changes (model attribute Growth) or the label is missing.
function GrowthLabel.apply(model: Model, body: BasePart, slime: Genome.Slime)
	local percent = GrowthLabel.percentFor(model, slime)
	local text = Growth.labelText(percent)
	local gui = body:FindFirstChild(Constants.GROWTH_LABEL_NAME)
	local shown = model:GetAttribute(Constants.GROWTH_ATTRIBUTE) or 0
	if shown == percent and (gui ~= nil) == (text ~= nil) then
		return
	end
	model:SetAttribute(Constants.GROWTH_ATTRIBUTE, percent)
	model:ScaleTo(Growth.scaleAt(percent / 100))
	if not text then
		if gui then
			gui:Destroy()
		end
		return
	end
	local billboard = if gui and gui:IsA("BillboardGui") then gui else build()
	-- After ScaleTo: measured on the scaled model, from Body's centre to the highest part.
	local box, size = model:GetBoundingBox()
	billboard.StudsOffsetWorldSpace =
		Vector3.new(0, Growth.labelOffset(box.Position.Y + size.Y / 2 - body.Position.Y), 0)
	billboard.Adornee = body
	billboard.Parent = body
	local label = billboard:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

return GrowthLabel
