--!strict
--[[
	ObbyBackdrop (VisualsClient module, contract/obby.md §5)

	Dresses the obby's own world on this client only (ObbyWorld builds it when the local player arrives and removes it
	when they leave, so the server's world and its part budget never carry it): a Folder named
	Constants.OBBY_BACKDROP, from WorldLayout.obbyBackdrop() (course-local pieces in the course frame,
	WorldLayout.obbyFrame):
	  island    a floating goo island mesh (grove, village or crystal islet): dripping grass cap, rock belly, props
	  landmark  a big island mesh far out (giant blossom tree or giant mushroom)
	  cloud     a cumulus mesh (wide puff or tower)
	  bank      a piece of the cloud sea, laid in rings at staggered heights
	  sea       the flat base disc under the banks
	Meshes come from shared/modeling-kit (models/obby_*.py, uploaded.json) and load with
	AssetService:CreateMeshPartAsync once per client; each piece clones its template, scaled to its radius, turned by
	its yaw and lightly tinted (MeshPart.Color multiplies the vertex colours). A mesh that fails to load falls back to
	a few plain parts. The folder is returned at once and fills in as the templates arrive.
	Decor only: nothing collides, takes queries or touches, and nothing casts a shadow. Holds no rules.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local WorldLayout = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WorldLayout"))

local ObbyBackdrop = {}

-- Kit meshes (shared/modeling-kit/uploaded.json): MeshId and native size in studs (X, Y up, Z).
ObbyBackdrop.MESHES = table.freeze({
	obby_island_grove = { id = "rbxassetid://103641710213958", size = Vector3.new(46.487, 46.605, 42.091) },
	obby_island_village = { id = "rbxassetid://113762869673065", size = Vector3.new(48.885, 40.595, 51.732) },
	obby_island_crystal = { id = "rbxassetid://84982111222812", size = Vector3.new(27.037, 38.962, 30.647) },
	obby_island_tree = { id = "rbxassetid://120213025233838", size = Vector3.new(91.987, 116.463, 103.75) },
	obby_island_mushroom = { id = "rbxassetid://71072973768994", size = Vector3.new(82.312, 107.701, 85.498) },
	obby_cloud_puff = { id = "rbxassetid://73056391735954", size = Vector3.new(60.026, 23.345, 33.757) },
	obby_cloud_tower = { id = "rbxassetid://110652712541010", size = Vector3.new(49.649, 38.508, 30.953) },
	obby_cloudbank = { id = "rbxassetid://112169156426656", size = Vector3.new(169.39, 36.467, 179.62) },
})

-- MeshPart.Color per tone (multiplies the mesh's own colours, so these stay near white).
local TINT = table.freeze({
	island = table.freeze({
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(246, 236, 255),
		Color3.fromRGB(236, 248, 250),
	}),
	cloud = table.freeze({
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 242, 250),
		Color3.fromRGB(246, 242, 255),
	}),
})
local SEA = Color3.fromRGB(236, 214, 240) -- the base disc, a shade under the banks' bellies

-- Fallback look when a mesh fails to load.
local LOOK = table.freeze({
	grass = Color3.fromRGB(120, 206, 120),
	rock = Color3.fromRGB(160, 132, 206),
	cloud = Color3.fromRGB(250, 242, 252),
})

local templates: { [string]: MeshPart | false } = {} -- mesh name -> template (false = failed), kept between visits
local waiting: { [string]: { thread } } = {}

local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- The template for mesh `name`, loading it on first ask (yields); false if it can't load.
local function template(name: string): MeshPart | false
	local have = templates[name]
	if have ~= nil then
		return have
	end
	local queue = waiting[name]
	if queue then
		table.insert(queue, coroutine.running())
		return coroutine.yield()
	end
	queue = {}
	waiting[name] = queue
	local ok, part = pcall(function()
		return AssetService:CreateMeshPartAsync(ObbyBackdrop.MESHES[name].id, {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	local result: MeshPart | false = false
	if ok and part then
		quiet(part)
		result = part
	end
	templates[name] = result
	waiting[name] = nil
	for _, co in queue do
		task.spawn(co, result)
	end
	return result
end

local function decor(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	quiet(part)
	part.Parent = parent
	return part
end

-- Plain stand-ins for a piece whose mesh failed: a grass disc on a rock ball, or a puff of three balls.
local function fallback(parent: Instance, name: string, kind: string, at: CFrame, r: number)
	local model = Instance.new("Model")
	model.Name = name
	if kind == "island" or kind == "landmark" then
		decor(
			model,
			"Grass",
			Enum.PartType.Cylinder,
			Vector3.new(2.4, r * 2, r * 2),
			at * CFrame.Angles(0, 0, math.rad(90)),
			LOOK.grass
		)
		decor(model, "Belly", Enum.PartType.Ball, Vector3.one * r * 1.9, at * CFrame.new(0, -r * 0.62, 0), LOOK.rock)
	else
		for i, p in { { 0, 0, 1 }, { 0.8, -0.2, 0.75 }, { -0.85, -0.25, 0.7 } } do
			local size = r * p[3]
			decor(
				model,
				`Puff{i}`,
				Enum.PartType.Ball,
				Vector3.new(size, size * 0.7, size),
				at * CFrame.new(p[1] * r, p[2] * r, 0),
				LOOK.cloud
			)
		end
	end
	model.Parent = parent
end

-- One mesh piece: the template's clone scaled so its wider footprint side is 2 * radius, its base at `at`.
local function place(folder: Folder, name: string, piece: WorldLayout.ObbyBackdropPiece, at: CFrame)
	local model = piece.model :: string
	local mesh = ObbyBackdrop.MESHES[model]
	local t = template(model)
	if not folder.Parent then
		return -- left the world while it loaded
	end
	local r = piece.radius
	local turned = at * CFrame.Angles(0, math.rad(piece.yaw), 0)
	if not t then
		fallback(folder, name, piece.kind, turned, r)
		return
	end
	local k = r * 2 / math.max(mesh.size.X, mesh.size.Z)
	local size = mesh.size * k
	local part = t:Clone()
	part.Name = name
	part.Size = size
	part.CFrame = turned * CFrame.new(0, size.Y / 2, 0)
	local tints = if piece.kind == "cloud" or piece.kind == "bank" then TINT.cloud else TINT.island
	part.Color = tints[piece.tone] or tints[1]
	part.Parent = folder
end

-- Where an island's grass top sits relative to its mesh base (fraction of the mesh height): islands are placed by
-- their cap, so the layout height is where the grass is, not the rock tip.
local CAP = table.freeze({
	island = 0.62,
	landmark = 0.55,
})

-- Builds the backdrop under `parent` and returns its Folder (the meshes fill in as they load).
function ObbyBackdrop.build(parent: Instance): Folder
	local origin, yaw = WorldLayout.obbyFrame()
	local a = math.rad(yaw)
	-- course-local: X forward, Y up, Z right (ObbyCourse's axes)
	local forward = Vector3.new(math.sin(a), 0, math.cos(a))
	local right = Vector3.new(-math.cos(a), 0, math.sin(a))
	local frame = CFrame.fromMatrix(Vector3.new(origin[1], origin[2], origin[3]), forward, Vector3.yAxis, right)
	local folder = Instance.new("Folder")
	folder.Name = Constants.OBBY_BACKDROP
	for k, piece in WorldLayout.obbyBackdrop() do
		local at = CFrame.new(frame * Vector3.new(piece.pos[1], piece.pos[2], piece.pos[3]))
		if piece.kind == "sea" then
			decor(
				folder,
				"CloudSea",
				Enum.PartType.Cylinder,
				Vector3.new(4, piece.radius * 2, piece.radius * 2),
				at * CFrame.Angles(0, 0, math.rad(90)),
				SEA
			)
		elseif piece.model and ObbyBackdrop.MESHES[piece.model] then
			local mesh = ObbyBackdrop.MESHES[piece.model]
			local cap = CAP[piece.kind]
			if cap then -- drop the mesh so its grass cap lands on the layout height
				local h = mesh.size.Y * piece.radius * 2 / math.max(mesh.size.X, mesh.size.Z)
				at *= CFrame.new(0, -h * cap, 0)
			end
			task.spawn(place, folder, `{piece.kind}{k}`, piece, at)
		end
	end
	folder.Parent = parent
	return folder
end

return ObbyBackdrop
