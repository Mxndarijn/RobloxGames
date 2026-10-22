--!strict
--[[
	WorldBuilder (owner: Archer)

	WorldBuilder.build(parent: Instance?): { map: Folder, plots: Folder }

	Builds CONTRACT.md §5.3 from WorldLayout under `parent` (default
	workspace): workspace.Map (Volcano with Crater, Chute) and
	workspace.Plots.Plot_1..PLOT_COUNT (Base, Pad_1..PADS_MAX, HomeZone,
	MergeVat, LockButton, Sign, Slimes folder). Phoenix calls it once from
	the server.

	Idempotent: an existing child with the same name is adopted and left
	untouched (no property resets, no deletes), so a second call creates
	nothing and never clobbers slimes or plot attributes set by the server.
	This is also how the static Map / Plots (src/visuals/static/*.rbxm, built
	by src/visuals/tools/build-map.luau and mapped into Workspace by Rojo)
	are adopted: build() then only fills in anything missing. The one thing
	forced on adopted parts is Anchored = true (the static map never falls).
	Plot attributes OwnerUserId / LockUntil get a 0 default only
	while missing.

	WorldBuilder.buildFloor(plot, plotIndex, floor) adds one upper jar of the
	goo jar tower (WorldLayout.floor); the server's BaseFloors calls it.
]]

local Effects = if script then require(script.Parent.Effects) else require("./Effects")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

local WorldBuilder = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function applyPart(part: Part, node: WorldLayout.WorldNode)
	local size, pos, rot = node.size or { 4, 1, 2 }, node.pos or { 0, 0, 0 }, node.rot or { 0, 0, 0 }
	part.Shape = (Enum.PartType :: any)[node.shape or "Block"]
	part.Size = Vector3.new(size[1], size[2], size[3])
	part.CFrame = CFrame.new(pos[1], pos[2], pos[3])
		* CFrame.fromOrientation(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
	if node.color then
		part.Color = rgb(node.color)
	end
	part.Material = (Enum.Material :: any)[node.material or "SmoothPlastic"]
	part.Transparency = node.transparency or 0
	part.CanCollide = node.canCollide ~= false
	part.CanQuery = node.canQuery ~= false
	part.CanTouch = node.canTouch ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
end

local function create(node: WorldLayout.WorldNode): Instance
	local instance: Instance
	if node.class == "PointLight" then
		instance = Effects.light(node.preset :: string)
	else
		instance = Instance.new(node.class)
		if node.class == "Part" then
			applyPart(instance :: Part, node)
		end
	end
	instance.Name = node.name
	return instance
end

local function ensure(parent: Instance, node: WorldLayout.WorldNode): Instance
	-- Adopt whatever already holds the name (even another class) rather than
	-- add a same-named twin next to it.
	local existing = parent:FindFirstChild(node.name)
	local instance = existing or create(node)
	if not existing then
		instance.Parent = parent
	elseif instance:IsA("BasePart") then
		instance.Anchored = true
	end
	for key, value in node.attributes or {} do
		if instance:GetAttribute(key) == nil then
			instance:SetAttribute(key, value)
		end
	end
	for _, child in node.children or {} do
		ensure(instance, child)
	end
	if node.primaryPart and instance:IsA("Model") and not instance.PrimaryPart then
		instance.PrimaryPart = instance:FindFirstChild(node.primaryPart) :: BasePart?
	end
	return instance
end

function WorldBuilder.build(parent: Instance?): { map: Folder, plots: Folder }
	local root = parent or workspace
	local built = {}
	for _, node in WorldLayout.build() do
		table.insert(built, ensure(root, node))
	end
	return { map = built[1] :: Folder, plots = built[2] :: Folder }
end

-- Adds upper jar `floor` (WorldLayout.floor) under `plot` (Plot_<plotIndex>); returns the top-level instances
-- (Floor_<floor> and its pads). Idempotent like build().
function WorldBuilder.buildFloor(plot: Instance, plotIndex: number, floor: number): { Instance }
	local built = {}
	for _, node in WorldLayout.floor(plotIndex, floor) do
		table.insert(built, ensure(plot, node))
	end
	return built
end

-- Puts plot `plotIndex`'s roof colliders on jar `floor` (WorldLayout.topColliders), replacing the ones on another jar.
function WorldBuilder.buildTop(plot: Instance, plotIndex: number, floor: number): Instance
	local old = plot:FindFirstChild("TopColliders")
	if old then
		old:Destroy()
	end
	return ensure(plot, WorldLayout.topColliders(plotIndex, floor))
end

return WorldBuilder
