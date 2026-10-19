--!strict
--[[
	EggModel (contract/mystery-egg.md)

	EggModel.build(id, kindId, mesh?): Model

	A Mystery Egg as an unparented Model, the egg twin of ModelFactory.build:
	  * Name "Slime_<id>", PrimaryPart "Body" (an egg-shaped Part, anchored,
	    CanQuery for the ProximityPrompts), every other part welded to Body,
	    massless and non-colliding; WorldPivot at the bottom centre.
	  * Attributes SlimeId, Tier (the kind's tier), EggKind; tag
	    Constants.SLIME_TAG, so labels and the despawn telegraph treat it like
	    any slime.
	  * A "Shell" folder with the kind's decoration (speckles, crystals, a gold
	    band, stars) and a "Nest" folder of straw that WorldView shows only on a
	    pad (EggModel.showNest).
	  * `mesh` (optional): an uploaded egg MeshPart (MeshAssets mystery_egg_<kind>)
	    that replaces the primitive shell; the nest mesh likewise.
	Pure function of its arguments: no yields, no services beyond CollectionService.
]]

local CollectionService = game:GetService("CollectionService")

local Constants = if script then require(script.Parent.Parent.Shared.Constants) else require("../../shared/Constants")
local EggKind = if script then require(script.Parent.Parent.Shared.EggKind) else require("../../shared/EggKind")

export type Meshes = { shell: MeshPart?, nest: MeshPart? }

local EggModel = {}

EggModel.WIDTH = 2.35 -- studs (about a 4-stud slime's height next to it)
EggModel.HEIGHT = 3
EggModel.NEST_WIDTH = 4.6
EggModel.NEST_HEIGHT = 1.2

-- Look per kind id: shell colour, accent colour, accent material and the decoration style.
local LOOKS: { [string]: { shell: Color3, accent: Color3, glow: Color3, material: Enum.Material, style: string } } = {
	speckled = {
		shell = Color3.fromRGB(255, 240, 205),
		accent = Color3.fromRGB(196, 110, 52),
		glow = Color3.fromRGB(255, 220, 160),
		material = Enum.Material.SmoothPlastic,
		style = "spots",
	},
	shiny = {
		shell = Color3.fromRGB(150, 225, 255),
		accent = Color3.fromRGB(235, 252, 255),
		glow = Color3.fromRGB(120, 220, 255),
		material = Enum.Material.Glass,
		style = "crystals",
	},
	golden = {
		shell = Color3.fromRGB(255, 196, 46),
		accent = Color3.fromRGB(255, 244, 170),
		glow = Color3.fromRGB(255, 210, 80),
		material = Enum.Material.Foil,
		style = "band",
	},
	cosmic = {
		shell = Color3.fromRGB(58, 30, 110),
		accent = Color3.fromRGB(255, 150, 240),
		glow = Color3.fromRGB(200, 120, 255),
		material = Enum.Material.SmoothPlastic, -- a Neon shell washes the purple out to flat blue; only the stars glow
		style = "stars",
	},
}

local STRAW = { Color3.fromRGB(222, 178, 88), Color3.fromRGB(196, 146, 66), Color3.fromRGB(240, 206, 120) }

-- The glow colour of a kind (ready-to-hatch light, client FX).
function EggModel.glowColor(kindId: string): Color3
	local look = LOOKS[kindId]
	return if look then look.glow else Color3.new(1, 1, 1)
end

local function part(name: string, shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Anchored = false
	return p
end

local function attach(body: BasePart, p: BasePart, offset: CFrame, parent: Instance)
	p.CFrame = body.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = p
	weld.Parent = p
	p.Parent = parent
end

-- A point on the egg surface (an ellipsoid of WIDTH x HEIGHT) at polar angle `v` (0 = top) and yaw `u`, pushed
-- out by `out`, facing outwards.
local function onShell(u: number, v: number, out: number): CFrame
	local rx, ry = EggModel.WIDTH / 2, EggModel.HEIGHT / 2
	local pos = Vector3.new(math.sin(v) * math.cos(u) * rx, math.cos(v) * ry, math.sin(v) * math.sin(u) * rx)
	local normal = Vector3.new(pos.X / (rx * rx), pos.Y / (ry * ry), pos.Z / (rx * rx)).Unit
	local at = pos + normal * out
	return CFrame.lookAt(at, at + normal)
end

local function decorate(body: BasePart, look: any, folder: Instance)
	if look.style == "spots" then
		local spots = {
			{ 0.4, 0.7 },
			{ 1.6, 1.1 },
			{ 2.7, 0.55 },
			{ 3.9, 1.35 },
			{ 5.1, 0.9 },
			{ 0.9, 1.9 },
			{ 2.2, 2.3 },
			{ 3.4, 1.8 },
			{ 4.6, 2.2 },
			{ 5.8, 1.6 },
		}
		for i, s in spots do
			local d = if i % 3 == 0 then 0.42 else 0.3
			local spot = part(
				`Spot{i}`,
				Enum.PartType.Cylinder,
				Vector3.new(0.08, d, d),
				look.accent,
				Enum.Material.SmoothPlastic
			)
			attach(body, spot, onShell(s[1], s[2], 0) * CFrame.Angles(0, math.rad(90), 0), folder)
		end
	elseif look.style == "crystals" then
		for i = 1, 7 do
			local u = (i - 1) / 7 * math.pi * 2
			local v = if i % 2 == 0 then 1.1 else 1.75
			local gem =
				part(`Gem{i}`, Enum.PartType.Block, Vector3.new(0.28, 0.28, 0.5), look.accent, Enum.Material.Glass)
			gem.Transparency = 0.15
			attach(body, gem, onShell(u, v, 0.08) * CFrame.Angles(0, 0, math.rad(45)), folder)
		end
	elseif look.style == "band" then
		local band = part(
			"Band",
			Enum.PartType.Cylinder,
			Vector3.new(0.22, EggModel.WIDTH * 1.03, EggModel.WIDTH * 1.03),
			look.accent,
			Enum.Material.Foil
		)
		attach(body, band, CFrame.new(0, -0.15, 0) * CFrame.Angles(0, 0, math.rad(90)), folder)
		for i = 1, 6 do
			local u = (i - 1) / 6 * math.pi * 2
			local stud = part(
				`Stud{i}`,
				Enum.PartType.Ball,
				Vector3.new(0.26, 0.26, 0.26),
				Color3.fromRGB(255, 255, 255),
				Enum.Material.Neon
			)
			attach(body, stud, onShell(u, math.pi / 2 + 0.12, 0.08), folder)
		end
	elseif look.style == "stars" then
		for i = 1, 14 do
			local u = i * 2.4
			local v = 0.35 + (i % 7) / 7 * 2.4
			local star = part(
				`Star{i}`,
				Enum.PartType.Ball,
				Vector3.new(0.16, 0.16, 0.16),
				if i % 3 == 0 then Color3.new(1, 1, 1) else look.accent,
				Enum.Material.Neon
			)
			attach(body, star, onShell(u, v, 0.02), folder)
		end
		local swirl = part(
			"Swirl",
			Enum.PartType.Cylinder,
			Vector3.new(0.12, EggModel.WIDTH * 1.02, EggModel.WIDTH * 1.02),
			look.accent,
			Enum.Material.Neon
		)
		attach(body, swirl, CFrame.new(0, 0.2, 0) * CFrame.Angles(math.rad(18), 0, math.rad(90)), folder)
	end
end

local function buildNest(body: BasePart, folder: Instance, bottom: number)
	-- A ring of chunky straw twists round the egg's foot, plus a few twigs sticking out.
	local ring = 12
	local radius = EggModel.NEST_WIDTH / 2 - 0.45
	for i = 1, ring do
		local a = (i - 1) / ring * math.pi * 2
		local straw =
			part(`Straw{i}`, Enum.PartType.Cylinder, Vector3.new(1.2, 0.5, 0.5), STRAW[i % 3 + 1], Enum.Material.Grass)
		local offset = CFrame.new(math.cos(a) * radius, bottom + 0.3, math.sin(a) * radius)
			* CFrame.Angles(0, -a + math.rad(90), math.rad(if i % 2 == 0 then 12 else -10))
		attach(body, straw, offset, folder)
	end
	local base = part(
		"NestBase",
		Enum.PartType.Cylinder,
		Vector3.new(0.3, EggModel.NEST_WIDTH - 0.6, EggModel.NEST_WIDTH - 0.6),
		STRAW[2],
		Enum.Material.Grass
	)
	attach(body, base, CFrame.new(0, bottom + 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), folder)
	for i = 1, 4 do
		local a = i * 1.7
		local twig = part(
			`Twig{i}`,
			Enum.PartType.Block,
			Vector3.new(0.12, 0.12, 1.1),
			Color3.fromRGB(120, 78, 40),
			Enum.Material.Wood
		)
		local offset = CFrame.new(math.cos(a) * (radius + 0.3), bottom + 0.55, math.sin(a) * (radius + 0.3))
			* CFrame.Angles(math.rad(-30), -a, 0)
		attach(body, twig, offset, folder)
	end
end

-- An uploaded mesh at one uniform scale that makes it `height` tall (its native proportions kept).
local function meshInto(body: BasePart, template: MeshPart, height: number, offset: CFrame, folder: Instance)
	local mesh = template:Clone()
	mesh.Size = template.Size * (height / math.max(template.Size.Y, 1e-3))
	mesh.Massless = true
	mesh.CanCollide = false
	mesh.CanTouch = false
	mesh.CanQuery = false
	mesh.Anchored = false
	attach(body, mesh, offset, folder)
end

function EggModel.build(id: string, kindId: string, meshes: Meshes?): Model
	local kind = EggKind.get(kindId)
	local look = LOOKS[kindId] or LOOKS.speckled
	local model = Instance.new("Model")
	model.Name = `Slime_{id}`

	local body = part(
		"Body",
		Enum.PartType.Block,
		Vector3.new(EggModel.WIDTH, EggModel.HEIGHT, EggModel.WIDTH),
		look.shell,
		look.material
	)
	body.Anchored = true
	body.CanQuery = true
	body.CanTouch = true
	body.CFrame = CFrame.new(0, EggModel.HEIGHT / 2, 0)
	body.PivotOffset = CFrame.new(0, -EggModel.HEIGHT / 2, 0)
	local shape = Instance.new("SpecialMesh")
	shape.MeshType = Enum.MeshType.Sphere
	shape.Parent = body
	body.Parent = model

	local shell = Instance.new("Folder")
	shell.Name = "Shell"
	shell.Parent = model
	local nest = Instance.new("Folder")
	nest.Name = "Nest"
	nest.Parent = model

	local shellMesh = meshes and meshes.shell
	if shellMesh then
		body.Transparency = 1
		meshInto(body, shellMesh, EggModel.HEIGHT, CFrame.new(), shell)
	else
		decorate(body, look, shell)
	end
	local bottom = -EggModel.HEIGHT / 2
	local nestMesh = meshes and meshes.nest
	if nestMesh then
		meshInto(body, nestMesh, EggModel.NEST_HEIGHT, CFrame.new(0, bottom + EggModel.NEST_HEIGHT / 2 - 0.3, 0), nest)
	else
		buildNest(body, nest, bottom)
	end
	EggModel.showNest(model, false)

	model.PrimaryPart = body
	model.WorldPivot = CFrame.new()
	model:SetAttribute("SlimeId", id)
	model:SetAttribute("Tier", if kind then kind.tier else 1)
	model:SetAttribute(Constants.EGG_KIND_ATTRIBUTE, kindId)
	CollectionService:AddTag(model, Constants.SLIME_TAG)
	return model
end

-- Shows or hides the straw nest (on a pad only).
function EggModel.showNest(model: Model, visible: boolean)
	local nest = model:FindFirstChild("Nest")
	if not nest or nest:GetAttribute("Visible") == visible then
		return
	end
	nest:SetAttribute("Visible", visible)
	for _, p in nest:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = if visible then 0 else 1
			p.CastShadow = visible
		end
	end
end

return table.freeze(EggModel)
