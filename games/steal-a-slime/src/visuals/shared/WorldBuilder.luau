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

	WorldBuilder.buildFloor(plot, plotIndex, floor, base?) adds one upper floor of
	the plot's base (BaseShapes, the goo jar tower by default); the server's
	BaseFloors calls it. WorldBuilder.conform fits a kept part to another base's
	node of the same name (server/BaseShapeSwap).
]]

local BaseShapes = if script then require(script.Parent.BaseShapes) else require("./BaseShapes")
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

-- Adds upper floor `floor` of base `base` (BaseShapes; nil = the jar) under `plot` (Plot_<plotIndex>); returns the
-- top-level instances (Floor_<floor> and its pads). Idempotent like build().
function WorldBuilder.buildFloor(plot: Instance, plotIndex: number, floor: number, base: string?): { Instance }
	local built = {}
	for _, node in BaseShapes.get(base).floor(plotIndex, floor) do
		table.insert(built, ensure(plot, node))
	end
	return built
end

-- Puts plot `plotIndex`'s roof colliders on floor `floor` (the base's `top`), replacing the ones on another floor.
-- A base whose roof is part of its floors gets an empty TopColliders folder (TopFloor set), so BaseFloors sees the
-- roof as placed.
function WorldBuilder.buildTop(plot: Instance, plotIndex: number, floor: number, base: string?): Instance
	local old = plot:FindFirstChild("TopColliders")
	if old then
		old:Destroy()
	end
	local top = BaseShapes.get(base).top
	if top then
		return ensure(plot, top(plotIndex, floor))
	end
	return ensure(plot, { name = "TopColliders", class = "Folder", attributes = { TopFloor = floor } })
end

-- Adds `node` (and its children) under `parent` the way build() does: an existing child of that name is adopted.
WorldBuilder.ensure = ensure

-- Fits an existing instance to `node` (the same part in another base): a Part gets the node's size and frame, its
-- children that have a node of their own are fitted the same way, and the rest (the swapped Mesh, the vat's mesh,
-- prompts' parts) move rigidly with it. Models and folders fit their children.
function WorldBuilder.conform(instance: Instance, node: WorldLayout.WorldNode)
	if instance:IsA("BasePart") and node.class == "Part" then
		local size, pos, rot = node.size or { 4, 1, 2 }, node.pos or { 0, 0, 0 }, node.rot or { 0, 0, 0 }
		local target = CFrame.new(pos[1], pos[2], pos[3])
			* CFrame.fromOrientation(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		local move = target * instance.CFrame:Inverse()
		instance.Size = Vector3.new(size[1], size[2], size[3])
		instance.CFrame = target
		-- children without a node of their own (and everything under them) ride along rigidly
		local own: { [string]: boolean } = {}
		for _, child in node.children or {} do
			own[child.name] = true
		end
		for _, child in instance:GetChildren() do
			if not own[child.Name] then
				for _, d in { child, table.unpack(child:GetDescendants()) } do
					if d:IsA("BasePart") then
						d.CFrame = move * d.CFrame
					end
				end
			end
		end
	end
	for _, child in node.children or {} do
		local existing = instance:FindFirstChild(child.name)
		if existing then
			WorldBuilder.conform(existing, child)
		else
			ensure(instance, child)
		end
	end
end

-- Rebuilds plot `plotIndex`'s floor 1 from base `from` into base `to` (BaseShapes ids, nil = the jar): the old base's
-- own pieces (its floor1 nodes no base keeps) are destroyed, the kept parts are fitted to the new base's nodes and the
-- new base's own pieces are created. Returns the created instances (they still need their kit meshes). The upper
-- floors must be gone first (BaseFloors.clear).
function WorldBuilder.rebase(plot: Instance, plotIndex: number, from: string?, to: string?): { Instance }
	for _, node in BaseShapes.get(from).floor1(plotIndex) do
		if not BaseShapes.kept(node.name) then
			local gone = plot:FindFirstChild(node.name)
			if gone then
				gone:Destroy()
			end
		end
	end
	local created: { Instance } = {}
	for _, node in BaseShapes.get(to).floor1(plotIndex) do
		local existing = plot:FindFirstChild(node.name)
		if existing and BaseShapes.kept(node.name) then
			WorldBuilder.conform(existing, node)
		elseif not existing then
			table.insert(created, ensure(plot, node))
		end
	end
	return created
end

return WorldBuilder
