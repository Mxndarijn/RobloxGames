--!strict
-- PetCloud (src/visuals/shared/PetCloud): what FollowPets mounts a pet on. Fallback Mount without a template, the
-- decor flags on the cloud clone, the cloud's size against the slime, where the slime's foot sits (visible parts
-- only), attaching a cloud later, and cleanup.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PetCloud = UiHarness.ui("../visuals/shared/PetCloud")
local PetFollow = UiHarness.ui("../visuals/shared/PetFollow")
local new = UiHarness.Instance.new
local roblox = require("@lune/roblox") :: any

local NATIVE = roblox.Vector3.new(3.261, 1.225, 2.393)
local SLIME_HEIGHT = 1.5

-- A slime clone with a body 2 x 1.5 x 2 and an eye.
local function slime(): any
	local model = new("Model")
	model.Name = "Whatever"
	local body = new("Part")
	body.Name = "Body"
	body.Size = roblox.Vector3.new(2, SLIME_HEIGHT, 2)
	body.Parent = model
	local eye = new("Part")
	eye.Name = "Eye"
	eye.Size = roblox.Vector3.new(0.3, 0.3, 0.3)
	eye.Parent = model
	return model
end

-- A published template as a careless upload could leave it: every decor flag on.
local function template(): any
	local mesh = new("MeshPart")
	mesh.Name = PetCloud.MESH
	mesh.Size = NATIVE
	mesh.Anchored = false
	mesh.CanCollide = true
	mesh.CanQuery = true
	mesh.CanTouch = true
	mesh.CastShadow = true
	return mesh
end

local function expectDecor(part: any)
	expect(part.Anchored).toBe(true)
	expect(part.CanCollide).toBe(false)
	expect(part.CanQuery).toBe(false)
	expect(part.CanTouch).toBe(false)
	expect(part.CastShadow).toBe(false)
end

-- The slime's foot (bottom of its box, which the harness centres on the pivot) in the wrapper's space.
local function footOf(wrapper: any): number
	local s = UiHarness.find(wrapper, PetCloud.SLIME_NAME)
	local _, size = s:GetBoundingBox()
	return s:GetPivot().Position.Y - size.Y / 2
end

local function centreOf(wrapper: any): any
	return UiHarness.find(wrapper, PetCloud.SLIME_NAME):GetPivot().Position
end

local function count(root: any): number
	return #UiHarness.descendants(root)
end

describe("PetCloud.mount without a template", function()
	local wrapper = PetCloud.mount(slime(), 42, nil)
	it("names the wrapper after the owner and the slime 'Slime'", function()
		expect(wrapper.Name).toBe("Pet_42")
		expect(UiHarness.find(wrapper, "Slime") ~= nil).toBe(true)
		expect(UiHarness.find(wrapper, "Slime").Parent).toBe(wrapper)
	end)
	it("uses an invisible decor Mount as the PrimaryPart", function()
		local mount = wrapper.PrimaryPart
		expect(mount.Name).toBe(PetCloud.MOUNT_NAME)
		expect(mount.ClassName).toBe("Part")
		expect(mount.Transparency).toBe(1)
		expect(mount.Parent).toBe(wrapper)
		expectDecor(mount)
		expect(PetCloud.hasCloud(wrapper)).toBe(false)
		expect(UiHarness.find(wrapper, PetCloud.CLOUD_NAME)).toBeNil()
	end)
	it("stands the slime's foot at the owner's feet, centred over the mount", function()
		expect(footOf(wrapper)).toBeCloseTo(-PetFollow.OFFSET_Y - 3, 1e-6)
		expect(centreOf(wrapper).X).toBeCloseTo(0, 1e-6)
		expect(centreOf(wrapper).Z).toBeCloseTo(0, 1e-6)
	end)
end)

describe("PetCloud.mount with a template", function()
	local source = template()
	local wrapper = PetCloud.mount(slime(), 7, source)
	local cloud = wrapper.PrimaryPart
	it("uses a scaled clone of the template as the PrimaryPart", function()
		expect(cloud.Name).toBe(PetCloud.CLOUD_NAME)
		expect(cloud.ClassName).toBe("MeshPart")
		expect(cloud.Parent).toBe(wrapper)
		expect(cloud ~= source).toBe(true)
		local scale = PetCloud.cloudScale(NATIVE, roblox.Vector3.new(2, SLIME_HEIGHT, 2))
		expect(cloud.Size.Y).toBeCloseTo(NATIVE.Y * scale, 1e-5)
		expect(cloud.Size.X).toBeCloseTo(NATIVE.X * scale, 1e-5)
		expect(PetCloud.hasCloud(wrapper)).toBe(true)
		expect(UiHarness.find(wrapper, PetCloud.MOUNT_NAME)).toBeNil()
	end)
	it("makes the clone decor whatever the template says: no collision, query, touch or shadow", function()
		expectDecor(cloud)
	end)
	it("leaves the shared template alone", function()
		expect(source.Parent).toBeNil()
		expect(source.CanCollide).toBe(true)
		expect(source.Size.Y).toBe(NATIVE.Y)
	end)
	it("sinks the slime's foot CLOUD_SINK into the cloud's top", function()
		local top = cloud.Size.Y / 2
		expect(footOf(wrapper)).toBeCloseTo(top - PetCloud.CLOUD_SINK, 1e-6)
		expect(footOf(wrapper) < top).toBe(true)
		expect(footOf(wrapper) > -top).toBe(true)
		expect(centreOf(wrapper).X).toBeCloseTo(0, 1e-6)
		expect(centreOf(wrapper).Z).toBeCloseTo(0, 1e-6)
	end)
end)

describe("PetCloud.attach (the template arrives after the pet)", function()
	it("swaps the Mount for a decor cloud and re-seats the slime on it", function()
		local wrapper = PetCloud.mount(slime(), 1, nil)
		local mount = wrapper.PrimaryPart
		expect(PetCloud.attach(wrapper, template())).toBe(true)
		expect(PetCloud.hasCloud(wrapper)).toBe(true)
		expect(wrapper.PrimaryPart.Name).toBe(PetCloud.CLOUD_NAME)
		expectDecor(wrapper.PrimaryPart)
		expect(mount.Parent).toBeNil() -- the Mount is gone, not left beside the cloud
		expect(UiHarness.find(wrapper, PetCloud.MOUNT_NAME)).toBeNil()
		expect(footOf(wrapper)).toBeCloseTo(wrapper.PrimaryPart.Size.Y / 2 - PetCloud.CLOUD_SINK, 1e-6)
	end)
	it("matches a pet that was mounted with the cloud from the start", function()
		local late = PetCloud.mount(slime(), 1, nil)
		PetCloud.attach(late, template())
		local early = PetCloud.mount(slime(), 1, template())
		expect(footOf(late)).toBeCloseTo(footOf(early), 1e-9)
		expect(count(late)).toBe(count(early))
	end)
	it("keeps the pet where it is gliding", function()
		local wrapper = PetCloud.mount(slime(), 1, nil)
		local pose = roblox.CFrame.new(40, 6, -12)
		wrapper:PivotTo(pose)
		PetCloud.attach(wrapper, template())
		expect(wrapper:GetPivot().Position.X).toBe(40)
		expect(wrapper:GetPivot().Position.Y).toBe(6)
		expect(wrapper:GetPivot().Position.Z).toBe(-12)
	end)
	it("does nothing when the pet already has a cloud", function()
		local wrapper = PetCloud.mount(slime(), 1, template())
		local cloud = wrapper.PrimaryPart
		expect(PetCloud.attach(wrapper, template())).toBe(false)
		expect(wrapper.PrimaryPart).toBe(cloud)
		expect(count(wrapper)).toBe(count(PetCloud.mount(slime(), 1, template())))
	end)
end)

describe("PetCloud cleanup", function()
	it("destroying the pet removes the cloud, the slime and everything under them", function()
		local folder = new("Folder")
		local wrapper = PetCloud.mount(slime(), 3, template())
		wrapper.Parent = folder
		local cloud, inner = wrapper.PrimaryPart, UiHarness.find(wrapper, PetCloud.SLIME_NAME)
		expect(count(folder) > 3).toBe(true)
		wrapper:Destroy()
		expect(count(folder)).toBe(0)
		expect(wrapper.Parent).toBeNil()
		expect(cloud.Parent).toBeNil()
		expect(inner.Parent).toBeNil()
	end)
	it("a late attach and a destroy leave nothing behind", function()
		local folder = new("Folder")
		local wrapper = PetCloud.mount(slime(), 3, nil)
		wrapper.Parent = folder
		PetCloud.attach(wrapper, template())
		wrapper:Destroy()
		expect(count(folder)).toBe(0)
	end)
	it("mounting, attaching and destroying open no connection", function()
		local before = UiHarness.stats.connects.RenderStepped + UiHarness.stats.connects.Heartbeat
		local wrapper = PetCloud.mount(slime(), 3, nil)
		PetCloud.attach(wrapper, template())
		wrapper:Destroy()
		local after = UiHarness.stats.connects.RenderStepped + UiHarness.stats.connects.Heartbeat
		expect(after).toBe(before)
	end)
end)

describe("PetCloud.cloudScale", function()
	it("keeps CLOUD_SCALE under a small slime", function()
		expect(PetCloud.cloudScale(NATIVE, roblox.Vector3.new(1, 1, 1))).toBe(PetCloud.CLOUD_SCALE)
	end)
	it("grows the cloud to CLOUD_FIT x a wide slime's width", function()
		local scale = PetCloud.cloudScale(NATIVE, roblox.Vector3.new(6, 3, 1))
		expect(NATIVE.X * scale).toBeCloseTo(6 * PetCloud.CLOUD_FIT, 1e-6)
		expect(NATIVE.Z * scale >= 1 * PetCloud.CLOUD_FIT).toBe(true)
	end)
	it("grows the cloud to CLOUD_FIT x a deep slime's depth", function()
		local scale = PetCloud.cloudScale(NATIVE, roblox.Vector3.new(1, 3, 4))
		expect(NATIVE.Z * scale).toBeCloseTo(4 * PetCloud.CLOUD_FIT, 1e-6)
		expect(NATIVE.X * scale >= 1 * PetCloud.CLOUD_FIT).toBe(true)
	end)
end)

-- A species slime as SlimeMesh leaves it: an invisible Body ball lower and wider than the visible mesh on top of a
-- thin ring, plus a hidden procedural crown floating above.
local function species(width: number): any
	local model = new("Model")
	local body = new("Part")
	body.Name = "Body"
	body.Size = roblox.Vector3.new(width * 1.5, width * 1.5, width * 1.5)
	body.CFrame = roblox.CFrame.new(0, -1, 0)
	body.Transparency = 1
	body.Parent = model
	local mesh = new("MeshPart")
	mesh.Name = "Mesh"
	mesh.Size = roblox.Vector3.new(width, 2, width * 0.8)
	mesh.CFrame = roblox.CFrame.new(0.5, 1, 0)
	mesh.Parent = model
	local ring = new("Part")
	ring.Name = "TierRim"
	ring.Size = roblox.Vector3.new(0.05, width, width) -- a cylinder turned upright
	ring.CFrame = roblox.CFrame.new(0.5, 0.025, 0) * roblox.CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = model
	local crown = new("Part")
	crown.Name = "Crown"
	crown.Size = roblox.Vector3.new(1, 1, 1)
	crown.CFrame = roblox.CFrame.new(0, 6, 0)
	crown.Transparency = 1
	crown.Parent = model
	return model
end

describe("PetCloud.visibleBox", function()
	it("boxes only the parts that can be seen, turned parts by their real extent", function()
		local centre, size = PetCloud.visibleBox(species(3))
		expect(size.X).toBeCloseTo(3, 1e-5)
		expect(size.Z).toBeCloseTo(3, 1e-5) -- the ring is as deep as it is wide
		expect(centre.X).toBeCloseTo(0.5, 1e-5)
		expect(centre.Y - size.Y / 2).toBeCloseTo(0, 1e-5) -- the ring's bottom, not Body's
		expect(centre.Y + size.Y / 2).toBeCloseTo(2, 1e-5) -- the mesh's top, not the hidden crown
	end)
	it("falls back to the whole box when nothing can be seen", function()
		local model = species(3)
		for _, part in UiHarness.descendants(model) do
			part.Transparency = 1
		end
		local _, size = PetCloud.visibleBox(model)
		expect(size.X).toBeCloseTo(4.5, 1e-5)
	end)
end)

describe("PetCloud.mount under a big species slime", function()
	local source = template()
	local wrapper = PetCloud.mount(species(5), 9, source)
	local cloud = wrapper.PrimaryPart
	local s = UiHarness.find(wrapper, PetCloud.SLIME_NAME)
	it("grows the cloud past the slime's visible footprint", function()
		expect(cloud.Size.Z).toBeCloseTo(5 * PetCloud.CLOUD_FIT, 1e-5) -- the narrow side of the cloud decides
		expect(cloud.Size.X >= 5 * PetCloud.CLOUD_FIT).toBe(true)
	end)
	it("keeps the grown cloud's bottom where a CLOUD_SCALE cloud's would be", function()
		local bottom = cloud.PivotOffset:Inverse().Position.Y - cloud.Size.Y / 2
		expect(bottom).toBeCloseTo(-NATIVE.Y * PetCloud.CLOUD_SCALE / 2, 1e-5)
	end)
	it("sinks the visible foot CLOUD_SINK into the cloud's top, centred on the visible parts", function()
		local pivot = s:GetPivot().Position
		expect(pivot.Y).toBeCloseTo(cloud.Size.Y / 2 - PetCloud.CLOUD_SINK, 1e-5) -- visible foot at y 0
		expect(pivot.X).toBeCloseTo(-0.5, 1e-5)
	end)
end)

describe("PetCloud.find", function()
	local function storage(withPart: boolean, className: string?): any
		local root = new("Folder")
		local folder = new("Folder")
		folder.Name = PetCloud.FOLDER
		folder.Parent = root
		if withPart then
			local part = new(className or "MeshPart")
			part.Name = PetCloud.MESH
			part.Parent = folder
		end
		return root
	end
	it("finds the published template", function()
		local root = storage(true)
		expect(PetCloud.find(root) ~= nil).toBe(true)
		expect(PetCloud.find(root).Name).toBe(PetCloud.MESH)
	end)
	it("is nil while the folder or the template is not there", function()
		expect(PetCloud.find(new("Folder"))).toBeNil()
		expect(PetCloud.find(storage(false))).toBeNil()
	end)
	it("ignores something that is not a part", function()
		expect(PetCloud.find(storage(true, "Folder"))).toBeNil()
	end)
end)

describe("PetCloud.decor", function()
	it("turns collision, query, touch and shadow off and anchors", function()
		local part = new("Part")
		part.Anchored = false
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = true
		part.CastShadow = true
		PetCloud.decor(part)
		expectDecor(part)
	end)
end)
