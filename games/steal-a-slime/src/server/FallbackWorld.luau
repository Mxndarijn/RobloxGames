--!strict
--[[
	FallbackWorld (Roblox adapter)

	Greybox stand-in for Archer's WorldBuilder so the server is playable
	before the real hub exists. Builds exactly the names CONTRACT.md §5.3
	promises: workspace.Map.{Volcano.Crater, Chute} and
	workspace.Plots.Plot_1..PLOT_COUNT with Base, Pad_1..Pad_<PADS_MAX>,
	HomeZone, MergeVat, LockButton, Sign and a Slimes folder.

	Only used when workspace.Plots is still missing after
	ReplicatedStorage.Visuals.WorldBuilder ran (or it doesn't exist). Sets
	the same PlotIndex / PadIndex attributes as WorldBuilder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)

local FallbackWorld = {}

FallbackWorld.PLOT_RING_RADIUS = 130
FallbackWorld.PLOT_SIZE = 44

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildMap()
	local map = Instance.new("Model")
	map.Name = Constants.MAP_FOLDER
	part("Ground", Vector3.new(420, 2, 420), CFrame.new(0, -1, 0), Color3.fromRGB(110, 170, 90), map)
	local volcano = Instance.new("Model")
	volcano.Name = "Volcano"
	local cone = part(
		"Cone",
		Vector3.new(24, 40, 40),
		CFrame.new(0, 12, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(90, 70, 60),
		volcano
	)
	cone.Shape = Enum.PartType.Cylinder
	local crater =
		part("Crater", Vector3.new(14, 1, 14), CFrame.new(0, 24.5, 0), Color3.fromRGB(120, 255, 120), volcano)
	crater.Material = Enum.Material.Neon
	volcano.PrimaryPart = crater
	volcano.Parent = map
	part(
		"Chute",
		Vector3.new(8, 1, 30),
		CFrame.new(0, 12, 30) * CFrame.Angles(math.rad(-30), 0, 0),
		Color3.fromRGB(80, 200, 120),
		map
	)
	map.Parent = workspace
end

local function buildPlot(index: number, parent: Instance)
	local angle = (index - 1) / Config.PLOT_COUNT * math.pi * 2
	local center = Vector3.new(math.cos(angle), 0, math.sin(angle)) * FallbackWorld.PLOT_RING_RADIUS
	-- Face the volcano.
	local origin = CFrame.lookAt(center + Vector3.new(0, 0.5, 0), Vector3.new(0, 0.5, 0))
	local size = FallbackWorld.PLOT_SIZE

	local plot = Instance.new("Model")
	plot.Name = `Plot_{index}`
	plot:SetAttribute(Constants.PLOT_INDEX_ATTRIBUTE, index)
	plot:SetAttribute("OwnerUserId", 0)
	plot:SetAttribute("LockUntil", 0)
	plot:SetAttribute("Rebirths", 0)

	local base = part("Base", Vector3.new(size, 1, size), origin, Color3.fromRGB(200, 200, 210), plot)
	plot.PrimaryPart = base

	-- Every pad flat on the Base (no upper floors in the greybox), one floor's worth per row.
	local perRow = Config.PADS_PER_FLOOR
	for pad = 1, Config.PADS_MAX do
		local row = (pad - 1) // perRow
		local col = (pad - 1) % perRow
		local x = (col - (perRow - 1) / 2) * 5
		local z = 2 + row * 5
		local padPart =
			part(`Pad_{pad}`, Vector3.new(4, 1, 4), origin * CFrame.new(x, 1, z), Color3.fromRGB(150, 220, 255), plot)
		padPart:SetAttribute(Constants.PAD_INDEX_ATTRIBUTE, pad)
	end

	local zone = part(
		Constants.HOME_ZONE,
		Vector3.new(size, 12, size),
		origin * CFrame.new(0, 6.5, 0),
		Color3.new(0, 1, 0),
		plot
	)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false

	part(
		"MergeVat",
		Vector3.new(6, 4, 6),
		origin * CFrame.new(-size / 2 + 5, 2.5, -size / 2 + 5),
		Color3.fromRGB(120, 80, 200),
		plot
	)
	part(
		"LockButton",
		Vector3.new(4, 1, 4),
		origin * CFrame.new(size / 2 - 4, 1, -size / 2 + 4),
		Color3.fromRGB(255, 80, 80),
		plot
	)
	part("Sign", Vector3.new(12, 6, 1), origin * CFrame.new(0, 4, -size / 2 + 1), Color3.fromRGB(255, 240, 200), plot)

	local slimes = Instance.new("Folder")
	slimes.Name = Constants.PLOT_SLIMES_FOLDER
	slimes.Parent = plot
	plot.Parent = parent
end

function FallbackWorld.build()
	if not workspace:FindFirstChild(Constants.MAP_FOLDER) then
		buildMap()
	end
	local plots = Instance.new("Folder")
	plots.Name = Constants.PLOTS_FOLDER
	for index = 1, Config.PLOT_COUNT do
		buildPlot(index, plots)
	end
	plots.Parent = workspace
end

return FallbackWorld
