--!strict
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local SlimeMesh = require("../src/server/SlimeMesh")
local TestRunner = require("./TestRunner")

local MeshAssets = require("../src/shared/MeshAssets")
local SlimeLooks = require("../src/shared/SlimeLooks")
local SlimeRoster = require("../src/shared/SlimeRoster")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Stand-in for Archer's ModelFactory: counts builds and returns a fake Model.
local function fakeFactory()
	local factory = { built = {} :: { any } }
	function factory.build(slime: any): any
		local model = { Name = `Slime_{slime.id}`, destroyed = false }
		function model.Destroy(self: any)
			self.destroyed = true
		end
		table.insert(factory.built, model)
		return model
	end
	return factory
end

local function setup(loadAsset: (number) -> any)
	local factory = fakeFactory()
	local warnings: { string } = {}
	local requested: { number } = {}
	local mesh = SlimeMesh.new({
		factory = factory :: any,
		loadAsset = function(assetId: number): any
			table.insert(requested, assetId)
			return loadAsset(assetId)
		end,
		warn = function(message: string)
			table.insert(warnings, message)
		end,
	})
	return mesh, factory, warnings, requested
end

describe("SlimeMesh fallback", function()
	it("uses the procedural factory when LoadAsset errors", function()
		local mesh, factory, warnings, requested = setup(function(): any
			error("HTTP 403 (Forbidden)")
		end)
		expect(SlimeMesh.load(mesh)).toBe("Procedural")
		expect(mesh.look).toBe("Procedural")
		expect(mesh.template).toBeNil()
		expect(requested[1]).toBe(Config.SLIME_MESH_ASSET_ID)
		expect(#warnings).toBe(2) -- shared package + one line for the kit meshes
		expect(string.find(warnings[1], "403", 1, true) ~= nil).toBeTruthy()
		expect(string.find(warnings[2], "slime_gummy", 1, true) ~= nil).toBeTruthy()
		expect(next(mesh.kits)).toBeNil()

		local model = SlimeMesh.build(mesh, Fixtures.slime("a", 3)) :: any
		expect(model).toBe(factory.built[1])
		expect(model.Name).toBe("Slime_a")
		expect(#factory.built).toBe(1)
		expect(model.destroyed).toBe(false)
	end)

	it("falls back when the asset has no MeshPart", function()
		local destroyed = false
		local mesh, factory, warnings = setup(function(): any
			return {
				FindFirstChildWhichIsA = function(_self: any, _className: string, _recursive: boolean): any
					return nil
				end,
				Destroy = function()
					destroyed = true
				end,
			}
		end)
		expect(SlimeMesh.load(mesh)).toBe("Procedural")
		expect(destroyed).toBe(true)
		expect(string.find(warnings[1], "no MeshPart", 1, true) ~= nil).toBeTruthy()
		local model = SlimeMesh.build(mesh, Fixtures.slime("b")) :: any
		expect(model).toBe(factory.built[1])
	end)

	it("rebuilds procedurally when dressing the mesh fails", function()
		local mesh, factory, warnings = setup(function(): any
			error("unused")
		end)
		-- A template that can't be cloned makes dress() error.
		mesh.template = {} :: any
		mesh.look = "Mesh"
		local model = SlimeMesh.build(mesh, Fixtures.slime("c")) :: any
		expect(#factory.built).toBe(2)
		expect(factory.built[1].destroyed).toBe(true)
		expect(model).toBe(factory.built[2])
		expect(model.destroyed).toBe(false)
		expect(string.find(warnings[1], "dress failed for c", 1, true) ~= nil).toBeTruthy()
	end)
end)

-- A fake LoadAsset result holding one MeshPart that clones to itself.
local function meshAsset(): any
	local part = {
		Clone = function(self: any): any
			return self
		end,
	}
	return {
		FindFirstChildWhichIsA = function(): any
			return part
		end,
		Destroy = function() end,
	}
end

describe("SlimeMesh kits", function()
	it("loads every uploaded kit by its assetId, after the shared package", function()
		local mesh, _, warnings, requested = setup(function(): any
			return meshAsset()
		end)
		expect(SlimeMesh.load(mesh)).toBe("Mesh")
		expect(requested[1]).toBe(Config.SLIME_MESH_ASSET_ID)
		local uploaded = {}
		for _, kit in SlimeLooks.KITS do
			if (MeshAssets.get(kit) :: MeshAssets.Entry).assetId then
				table.insert(uploaded, kit)
			end
		end
		expect(#requested).toBe(1 + #uploaded)
		for i, kit in uploaded do
			expect(requested[i + 1]).toBe((MeshAssets.get(kit) :: any).assetId)
			expect(mesh.kits[kit] ~= nil).toBe(true)
		end
		expect(#warnings).toBe(0)
	end)

	it("never fetches a kit without an assetId: its slimes wear the shared mesh, nothing waits on it", function()
		local entry = MeshAssets.entries.slime_gummy
		local assetId = entry.assetId
		entry.assetId = nil
		local mesh, factory, warnings, requested = setup(function(): any
			return meshAsset()
		end)
		SlimeMesh.load(mesh)
		entry.assetId = assetId
		expect(table.find(requested, assetId :: number)).toBeNil()
		expect(mesh.kits.slime_gummy).toBeNil()
		expect(#warnings).toBe(0)
		local gummy = Fixtures.slime("g", 1, { species = "gummy" })
		expect(SlimeMesh.pendingKit(mesh, gummy)).toBeNil()
		mesh.template = {} :: any -- dressing the fake model fails; the attempt shows which template was tried
		SlimeMesh.build(mesh, gummy)
		expect(#factory.built).toBe(2) -- the shared mesh only, then the procedural model
	end)

	it("keeps the shared mesh when only the kits fail to load", function()
		local mesh, _, warnings = setup(function(assetId: number): any
			if assetId == Config.SLIME_MESH_ASSET_ID then
				return meshAsset()
			end
			error("HTTP 404")
		end)
		expect(SlimeMesh.load(mesh)).toBe("Mesh")
		expect(mesh.template ~= nil).toBe(true)
		expect(next(mesh.kits)).toBeNil()
		expect(#warnings).toBe(1)
	end)

	it("falls back kit -> shared -> procedural when dressing fails", function()
		local mesh, factory, warnings = setup(function(): any
			error("unused")
		end)
		mesh.kits.slime_lop = {} :: any
		mesh.template = {} :: any
		local slime = Fixtures.slime("d")
		slime.species = "lop"
		local model = SlimeMesh.build(mesh, slime) :: any
		expect(#factory.built).toBe(3)
		expect(factory.built[1].destroyed).toBe(true)
		expect(factory.built[2].destroyed).toBe(true)
		expect(model).toBe(factory.built[3])
		expect(#warnings).toBe(3) -- two dress failures + the fake model's type look
	end)

	it("names a slime's kit as pending until it loads, and never for a kit that failed", function()
		local fetches: { () -> () } = {}
		local mesh = SlimeMesh.new({
			factory = fakeFactory() :: any,
			loadAsset = function(assetId: number): any
				if assetId == (MeshAssets.get("slime_lop") :: any).assetId then
					error("HTTP 404")
				end
				return meshAsset()
			end,
			spawn = function(fetch: () -> ())
				table.insert(fetches, fetch) -- kits arrive only when the test runs these
			end,
			warn = function() end,
		})
		SlimeMesh.load(mesh)
		local gummy = Fixtures.slime("g", 1, { species = "gummy" })
		local lop = Fixtures.slime("l", 1, { species = "lop" })
		expect(SlimeMesh.pendingKit(mesh, gummy)).toBe("slime_gummy")
		expect(SlimeMesh.hasKit(mesh, "slime_gummy")).toBe(false)
		expect(SlimeMesh.pendingKit(mesh, lop)).toBe("slime_lop")

		for _, fetch in fetches do
			fetch()
		end
		expect(SlimeMesh.hasKit(mesh, "slime_gummy")).toBe(true)
		expect(SlimeMesh.pendingKit(mesh, gummy)).toBeNil()
		expect(SlimeMesh.hasKit(mesh, "slime_lop")).toBe(false)
		expect(SlimeMesh.pendingKit(mesh, lop)).toBeNil() -- failed: it never arrives, so nothing waits on it
	end)

	it("has no pending kit for a slime without a species", function()
		local mesh = setup(function(): any
			return meshAsset()
		end)
		expect(SlimeMesh.pendingKit(mesh, Fixtures.slime("p", 1))).toBeNil()
	end)
end)

-- Roblox globals SlimeMesh uses at call time; swapped in only while dressing a real Model.
local GLOBALS = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

local function withRobloxGlobals<T>(fn: () -> T): T
	local env = getfenv(SlimeMesh.build)
	local saved = {}
	for name, value in GLOBALS do
		saved[name] = env[name]
		env[name] = value
	end
	local ok, result = pcall(fn)
	for name in GLOBALS do
		env[name] = saved[name]
	end
	if not ok then
		error(result, 0)
	end
	return result
end

-- A procedural slime Model: Body (PrimaryPart) plus a face and the goo puddle.
local function slimeModel(): any
	local model = roblox.Instance.new("Model")
	local body = roblox.Instance.new("Part")
	body.Name = "Body"
	body.Size = roblox.Vector3.new(6, 6, 6)
	body.Color = roblox.Color3.fromRGB(120, 200, 90)
	body.Parent = model
	model.PrimaryPart = body
	for _, name in { "EyeL", "MouthMid", "Puddle" } do
		local part = roblox.Instance.new("Part")
		part.Name = name
		part.Parent = model
	end
	return model
end

describe("SlimeMesh species kits", function()
	it("wears a kit with an offset at size-1 scale, Color white, and hides the procedural face", function()
		local kit = "slime_gummy"
		local entry = MeshAssets.get(kit) :: any
		assert(entry and entry.offset and entry.size, "species kit entry with offset + size")
		expect((SlimeLooks.get("gummy") :: any).kit).toBe(kit)
		local model = slimeModel()
		local mesh = SlimeMesh.new({
			factory = {
				build = function(): any
					return model
				end,
			} :: any,
			loadAsset = function(): any
				error("unused")
			end,
			warn = function(message: string)
				error(message)
			end,
		})
		local template = roblox.Instance.new("MeshPart")
		local bone = roblox.Instance.new("Bone")
		bone.Parent = template
		roblox.Instance.new("Weld").Parent = template
		mesh.kits[kit] = template :: any
		local built = withRobloxGlobals(function()
			return SlimeMesh.build(mesh, Fixtures.slime("e", 1, { species = "gummy" }))
		end) :: any
		expect(built).toBe(model)
		local worn = model:FindFirstChild(SlimeMesh.MESH_NAME)
		assert(worn, "species mesh")
		expect(worn.Color == roblox.Color3.new(1, 1, 1)).toBe(true)
		local scale = 6 / Config.SLIME_BASE_DIAMETER
		expect(worn.Size.X).toBeCloseTo(entry.size[1] * scale, 1e-3)
		expect(worn.Size.Y).toBeCloseTo(entry.size[2] * scale, 1e-3)
		expect(worn:FindFirstChildWhichIsA("Bone") ~= nil).toBe(true)
		expect(worn:FindFirstChildWhichIsA("Weld")).toBeNil()
		expect(model.Body.Transparency).toBe(1)
		expect(model.EyeL.Transparency).toBe(1)
		expect(model.MouthMid.Transparency).toBe(1)
		expect(model.Puddle.Transparency).toBe(1)
		expect(SlimeMesh.isReplacedPart("EyeL") and SlimeMesh.isReplacedPart("MouthMid")).toBe(true)
	end)
end)

-- A slime Model from the real SlimeLayout parts, built the way ModelFactory does (Body PrimaryPart at its
-- bottom-centre pivot, every other part welded to Body), with no rig: Lune has no CollectionService.
local SlimeLayout = require("../src/visuals/shared/SlimeLayout")

local function layoutModel(slime: any): any
	local model = roblox.Instance.new("Model")
	local body
	for i, spec in SlimeLayout.build(slime) do
		local part = roblox.Instance.new("Part")
		part.Name = spec.name
		part.Shape = (roblox.Enum.PartType :: any)[spec.shape]
		part.Size = roblox.Vector3.new(spec.size[1], spec.size[2], spec.size[3])
		part.CFrame = roblox.CFrame.new(spec.pos[1], spec.pos[2], spec.pos[3])
			* roblox.CFrame.fromOrientation(math.rad(spec.rot[1]), math.rad(spec.rot[2]), math.rad(spec.rot[3]))
		part.Material = (roblox.Enum.Material :: any)[spec.material]
		part.Transparency = spec.transparency
		if i == 1 then
			body = part
			model.PrimaryPart = part
		else
			local weld = roblox.Instance.new("WeldConstraint")
			weld.Enabled = true -- Lune has no default for it
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = part
		end
		part.Parent = model
	end
	return model
end

-- World-space box of a part: (min, max) corners.
local function bounds(part: any): (any, any)
	local cf, half = part.CFrame, part.Size / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local extent = roblox.Vector3.new(
		math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z,
		math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z,
		math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z
	)
	return cf.Position - extent, cf.Position + extent
end

-- A species slime dressed in its own kit (a bare MeshPart template at the kit's native size).
local function dressedSpecies(species: string, tier: number): any
	local look = SlimeLooks.get(species) :: any
	local entry = MeshAssets.get(look.kit) :: any
	local slime = Fixtures.slime(`{species}{tier}`, tier, { species = species, size = 1.4 })
	local model = layoutModel(slime)
	local mesh = SlimeMesh.new({
		factory = {
			build = function(): any
				return model
			end,
		} :: any,
		loadAsset = function(): any
			error("unused")
		end,
		warn = function(message: string)
			error(message)
		end,
	})
	local template = roblox.Instance.new("MeshPart")
	template.Size = roblox.Vector3.new(entry.size[1], entry.size[2], entry.size[3])
	mesh.kits[look.kit] = template :: any
	withRobloxGlobals(function()
		return SlimeMesh.build(mesh, slime)
	end)
	return model
end

local FOOT_MARGIN = 0.05 -- studs

describe("SlimeMesh species foot", function()
	it("leaves nothing sticking out below or around the foot of any tier", function()
		for tier = 1, Config.SECRET_TIER do
			local model = dressedSpecies("lop", tier)
			local body, worn = model.Body, model[SlimeMesh.MESH_NAME]
			local d = body.Size.X
			local ground = body.CFrame.Position.Y - body.Size.Y / 2
			local footHalf = math.min(worn.Size.X, worn.Size.Z) / 2
			expect(model.Puddle.Transparency).toBe(1)
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.Transparency < 1 and part ~= worn then
					local low, high = bounds(part)
					local label = `{part.Name} (tier {tier})`
					assert(low.Y >= ground - FOOT_MARGIN, `{label} sinks below the ground`)
					if SlimeMesh.SHELLS[part.Name] then
						assert(high.Y >= ground + worn.Size.Y, `{label} does not wrap the mesh`)
					elseif low.Y < ground + 0.1 * d then
						local reach = math.max(high.X - body.CFrame.Position.X, body.CFrame.Position.X - low.X)
						assert(reach <= footHalf + FOOT_MARGIN, `{label} sticks out around the foot`)
					end
				end
			end
		end
	end)

	it("puts no flat disc under any species slime, whatever its rarity", function()
		local checked = 0
		for _, entry in SlimeRoster.ROSTER do
			local look = SlimeLooks.get(entry.id)
			if look and (MeshAssets.get(look.kit) :: any).offset then
				local model = dressedSpecies(entry.id, entry.tier)
				local body, worn = model.Body, model[SlimeMesh.MESH_NAME]
				local d = body.Size.X
				local ground = body.CFrame.Position.Y - body.Size.Y / 2
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and part.Transparency < 1 and part ~= worn then
						local low, high = bounds(part)
						local flat = high.Y - low.Y < 0.1 * d and high.X - low.X > 0.5 * d
						assert(
							not (flat and low.Y < ground + 0.1 * d),
							`{entry.id}: {part.Name} is a disc on the ground`
						)
					end
				end
				checked += 1
			end
		end
		expect(checked > 10).toBe(true)
	end)
end)
