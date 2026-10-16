--!strict
--[[
	ModelFactory (owner: Archer)

	ModelFactory.build(slimeData: Types.SlimeData): Model

	Turns a slime genome into an unparented Model. Contract (CONTRACT.md §4):
	  * Name "Slime_<id>", PrimaryPart "Body" (Ball Part, diameter
	    SLIME_BASE_DIAMETER * size), every other part held to Body (decorations through the
    FaceRoot / SkinRoot Motor6D rig of SlimeRig, plus an Animator).
	  * Body.Anchored = true, every part Massless and CanCollide = false;
	    Body.CanQuery = true so ProximityPrompts / raycasts can hit it.
	  * WorldPivot sits at the bottom centre: model:PivotTo(padTopCFrame)
	    rests the slime on the pad. A Model with a PrimaryPart pivots around
	    the PrimaryPart's pivot, so Body.PivotOffset points at the bottom too.
	  * Attributes SlimeId, Tier, Mutation, Size; CollectionService tag
	    Constants.SLIME_TAG.
	  * Pure function of slimeData: no yields, no scripts, no services beyond
	    CollectionService, works on server and client (ViewportFrames).

	The geometry lives in SlimeLayout (pure, Lune-testable); this module only
	turns its part specs into Instances.
]]

local CollectionService = game:GetService("CollectionService")

local Constants = if script then require(script.Parent.Parent.Shared.Constants) else require("../../shared/Constants")
local SlimeRig = if script then require(script.Parent.SlimeRig) else require("./SlimeRig")
local SlimeLayout = if script then require(script.Parent.SlimeLayout) else require("./SlimeLayout")
local Types = if script then require(script.Parent.Parent.Shared.Types) else require("../../shared/Types")

local ModelFactory = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function cframeOf(spec: SlimeLayout.PartSpec): CFrame
	local rot = spec.rot
	return CFrame.new(spec.pos[1], spec.pos[2], spec.pos[3])
		* CFrame.fromOrientation(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
end

local function makePart(spec: SlimeLayout.PartSpec): Part
	local part = Instance.new("Part")
	part.Name = spec.name
	part.Shape = (Enum.PartType :: any)[spec.shape]
	part.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
	part.CFrame = cframeOf(spec)
	part.Color = rgb(spec.color)
	part.Material = (Enum.Material :: any)[spec.material]
	part.Transparency = spec.transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = spec.transparency < 0.5
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = false
	return part
end

function ModelFactory.build(slimeData: Types.SlimeData): Model
	local specs = SlimeLayout.build(slimeData)

	local model = Instance.new("Model")
	model.Name = `Slime_{slimeData.id}`

	local bodySpec = specs[1]
	local body = makePart(bodySpec)
	body.Anchored = true
	body.CanQuery = true
	body.CanTouch = true
	-- Bottom centre of the ball, in Body space.
	body.PivotOffset = CFrame.new(0, -bodySpec.size[2] / 2, 0)
	body.Parent = model
	if bodySpec.light then
		local light = Instance.new("PointLight")
		light.Color = rgb(bodySpec.light.color)
		light.Range = bodySpec.light.range
		light.Brightness = bodySpec.light.brightness
		light.Shadows = false
		light.Parent = body
	end
	if bodySpec.sparkles then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = rgb(bodySpec.sparkles.color)
		sparkles.Parent = body
	end

	for i = 2, #specs do
		local part = makePart(specs[i])
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end

	SlimeRig.attach(model, body)
	model.PrimaryPart = body
	model.WorldPivot = CFrame.new()
	model:SetAttribute("SlimeId", slimeData.id)
	model:SetAttribute("Tier", slimeData.tier)
	model:SetAttribute("Mutation", slimeData.mutation)
	model:SetAttribute("Size", slimeData.size)
	CollectionService:AddTag(model, Constants.SLIME_TAG)
	return model
end

return ModelFactory
