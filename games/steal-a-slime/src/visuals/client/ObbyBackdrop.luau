--!strict
--[[
	ObbyBackdrop (VisualsClient module, contract/obby.md §5)

	Dresses the obby's own world on this client only (ObbyWorld builds it when the local player arrives and removes it
	when they leave, so the server's world and its part budget never carry it): a Folder named
	Constants.OBBY_BACKDROP, from WorldLayout.obbyBackdrop() (course-local pieces in the course frame,
	WorldLayout.obbyFrame):
	  island  a goo-green grass top on a lilac rock belly, a few goo blobs on top and a drip underneath
	  cloud   a puff of four overlapping white-pink balls
	  sea     the cloud sea, a wide flat pastel disc far below the course
	Decor only: nothing collides, takes queries or touches, and nothing casts a shadow. Holds no rules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local WorldLayout = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WorldLayout"))

local ObbyBackdrop = {}

-- Colours per piece kind (tone 1..3 picks within a row).
local LOOK = table.freeze({
	grass = table.freeze({
		Color3.fromRGB(120, 226, 120),
		Color3.fromRGB(150, 236, 110),
		Color3.fromRGB(100, 214, 150),
	}),
	rock = table.freeze({ Color3.fromRGB(176, 148, 214), Color3.fromRGB(196, 150, 200), Color3.fromRGB(150, 140, 210) }),
	goo = table.freeze({ Color3.fromRGB(255, 130, 200), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 210, 90) }),
	cloud = table.freeze({ Color3.fromRGB(255, 244, 252), Color3.fromRGB(246, 236, 255) }),
	sea = Color3.fromRGB(252, 226, 246),
})

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
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- A flat disc (a cylinder on its side) of `radius` and `height` centred at `cf`.
local function disc(parent: Instance, name: string, radius: number, height: number, cf: CFrame, color: Color3)
	return decor(
		parent,
		name,
		Enum.PartType.Cylinder,
		Vector3.new(height, radius * 2, radius * 2),
		cf * CFrame.Angles(0, 0, math.rad(90)),
		color
	)
end

local function island(parent: Instance, k: number, at: CFrame, r: number, tone: number)
	local model = Instance.new("Model")
	model.Name = `Island{k}`
	disc(model, "Grass", r, 2.4, at, LOOK.grass[tone])
	decor(
		model,
		"Belly",
		Enum.PartType.Ball,
		Vector3.new(r * 1.9, r * 1.9, r * 1.9),
		at * CFrame.new(0, -r * 0.62, 0),
		LOOK.rock[tone]
	)
	disc(model, "Rim", r * 0.98, 0.6, at * CFrame.new(0, -1.3, 0), LOOK.rock[tone]:Lerp(Color3.new(), 0.12))
	for b = 1, 3 do
		local a = math.rad(k * 47 + b * 120)
		local size = r * (0.16 + 0.05 * b)
		decor(
			model,
			`Blob{b}`,
			Enum.PartType.Ball,
			Vector3.new(size, size * 0.8, size),
			at * CFrame.new(math.cos(a) * r * 0.5, 1.2 + size * 0.3, math.sin(a) * r * 0.5),
			LOOK.goo[(tone + b) % 3 + 1]
		)
	end
	decor(
		model,
		"Drip",
		Enum.PartType.Ball,
		Vector3.new(r * 0.35, r * 0.9, r * 0.35),
		at * CFrame.new(0, -r * 1.45, 0),
		LOOK.goo[tone]
	)
	model.Parent = parent
end

local function cloud(parent: Instance, k: number, at: CFrame, r: number, tone: number)
	local model = Instance.new("Model")
	model.Name = `Cloud{k}`
	local puffs = { { 0, 0, 0, 1 }, { 0.8, -0.2, 0.2, 0.75 }, { -0.85, -0.25, -0.1, 0.7 }, { 0.1, 0.35, -0.5, 0.65 } }
	for i, p in puffs do
		local size = r * 2 * p[4]
		decor(
			model,
			`Puff{i}`,
			Enum.PartType.Ball,
			Vector3.new(size, size * 0.7, size),
			at * CFrame.new(p[1] * r, p[2] * r, p[3] * r),
			LOOK.cloud[tone]
		).Transparency =
			0.05
	end
	model.Parent = parent
end

-- Builds the backdrop under `parent` and returns its Folder.
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
		if piece.kind == "island" then
			island(folder, k, at, piece.radius, piece.tone)
		elseif piece.kind == "cloud" then
			cloud(folder, k, at, piece.radius, piece.tone)
		elseif piece.kind == "sea" then
			disc(folder, "CloudSea", piece.radius, 4, at, LOOK.sea)
		end
	end
	folder.Parent = parent
	return folder
end

return ObbyBackdrop
