--!strict
--[[
	PetCloud (follow pet mount, Roblox types at call time only)

	Builds the wrapper a FollowPets pet glides in: Model "Pet_<id>" = PrimaryPart + "Slime" standing on it. With a
	cloud template (the MeshPart the server publishes under ReplicatedStorage.PetCloudMeshes, native size) the
	PrimaryPart is a clone of it, grown to CLOUD_FIT x the slime's visible footprint (CLOUD_SCALE to CLOUD_MAX_SCALE),
	and the slime's foot sinks CLOUD_SINK into its top. A grown cloud keeps its bottom where a CLOUD_SCALE one would
	hover (its pivot sits below its centre). Without a template a small invisible Mount is the PrimaryPart and the
	slime stands level with the owner's feet. attach() swaps a Mount for a cloud later, so a pet never waits for the
	template. The wrapper's pivot is the PrimaryPart pivot: PetFollow's goal. Every part made here is decor (no
	collision, query, touch or shadow).

	Ground decor of the slime (SlimeLayout's goo "Puddle") is removed: on a cloud it reads as a flat disc under the
	pet. The slime is measured by its visible parts only, glow shells (UNMEASURED) left out
	(visibleBox): a species slime keeps an invisible Body ball and hidden procedural parts that do not line up with
	its mesh.
]]

local PetFollow = if script then require(script.Parent.PetFollow) else require("./PetFollow")

local PetCloud = {}

PetCloud.PET_SIZE = 1.5 -- studs: a pet's longest visible side, whatever the slime's size (a hand-sized pet)
PetCloud.PET_MAX_SCALE = 0.55 -- a pet is never more than this x the slime as built
PetCloud.MESH = "pet_cloud" -- MeshAssets name, and the template's name in the folder
PetCloud.FOLDER = "PetCloudMeshes" -- ReplicatedStorage folder the server publishes the template into
PetCloud.CLOUD_SCALE = 0.55 -- smallest scale, of the native 3.3 x 1.2 x 2.4 mesh
PetCloud.CLOUD_FIT = 1.15 -- the cloud is at least this x the slime's visible width and depth
PetCloud.CLOUD_MAX_SCALE = 0.8 -- a wide pet overhangs its cloud rather than riding a giant one
PetCloud.CLOUD_SINK = 0.08 -- the slime's foot sinks this far into the cloud's top (studs)
PetCloud.CLOUD_NAME = "Cloud"
PetCloud.MOUNT_NAME = "Mount"
PetCloud.SLIME_NAME = "Slime"
PetCloud.GROUND_PARTS = table.freeze({ "Puddle" }) -- removed from the slime: they belong on the ground
PetCloud.UNMEASURED = table.freeze({ "Aura" }) -- see-through glow shells: not part of the slime's footprint

-- Anchored, no collision, no query, no touch, no shadow.
function PetCloud.decor(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- Box (centre, size) around the parts of `model` that can be seen, in world space. Falls back to the whole
-- bounding box when every part is invisible.
function PetCloud.visibleBox(model: Model): (Vector3, Vector3)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 and not table.find(PetCloud.UNMEASURED, part.Name) then
			local cf, half = part.CFrame, part.Size / 2
			-- Axis-aligned half extents of the turned part.
			local ext = Vector3.new(
				math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z,
				math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z,
				math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
			)
			lo = lo:Min(cf.Position - ext)
			hi = hi:Max(cf.Position + ext)
		end
	end
	if lo.X > hi.X then
		local box, size = model:GetBoundingBox()
		return box.Position, size
	end
	return (lo + hi) / 2, hi - lo
end

-- Factor that shrinks a slime whose visible box is `slime` big to a pet: its longest side becomes PET_SIZE, at most
-- PET_MAX_SCALE. Multiply the model's current scale by it.
function PetCloud.petScale(slime: Vector3): number
	local longest = math.max(slime.X, slime.Y, slime.Z)
	if not (longest > 0) then
		return PetCloud.PET_MAX_SCALE
	end
	return math.min(PetCloud.PET_SIZE / longest, PetCloud.PET_MAX_SCALE)
end

-- Scale of the cloud under a slime whose visible box is `slime` big: CLOUD_SCALE, more for a wide slime, at most
-- CLOUD_MAX_SCALE.
function PetCloud.cloudScale(native: Vector3, slime: Vector3): number
	local fit = PetCloud.CLOUD_FIT
	local scale = math.max(PetCloud.CLOUD_SCALE, slime.X * fit / native.X, slime.Z * fit / native.Z)
	return math.min(scale, PetCloud.CLOUD_MAX_SCALE)
end

local function makeCloud(template: BasePart, slime: Model): BasePart
	local cloud = template:Clone()
	cloud.Name = PetCloud.CLOUD_NAME
	slime:PivotTo(CFrame.new())
	local _, size = PetCloud.visibleBox(slime)
	local scale = PetCloud.cloudScale(template.Size, size)
	cloud.Size = template.Size * scale
	-- Pivot below the centre, so a grown cloud rises instead of sinking towards the ground.
	cloud.PivotOffset = CFrame.new(0, -template.Size.Y * (scale - PetCloud.CLOUD_SCALE) / 2, 0)
	PetCloud.decor(cloud)
	return cloud
end

local function makeMount(): BasePart
	local part = Instance.new("Part")
	part.Name = PetCloud.MOUNT_NAME
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	PetCloud.decor(part)
	return part
end

-- Slime's visible parts centred over `anchor` (centre at the origin), its foot sunk CLOUD_SINK into the cloud's
-- top; on a Mount the foot is at the owner's feet (PetFollow.OFFSET_Y is the root-to-anchor drop, the root sits 3
-- studs above them).
local function seat(slime: Model, anchor: BasePart, cloud: boolean)
	local top = if cloud then anchor.Size.Y / 2 else -PetFollow.OFFSET_Y - 3
	slime:PivotTo(CFrame.new())
	local centre, size = PetCloud.visibleBox(slime)
	local foot = centre.Y - size.Y / 2
	local sink = if cloud then PetCloud.CLOUD_SINK else 0
	slime:PivotTo(CFrame.new(-centre.X, top - sink - foot, -centre.Z))
end

-- The wrapper for `slime` (renamed "Slime"): on a clone of `template` or, without one, on a Mount.
function PetCloud.mount(slime: Model, userId: number, template: BasePart?): Model
	local wrapper = Instance.new("Model")
	wrapper.Name = `Pet_{userId}`
	slime.Name = PetCloud.SLIME_NAME
	for _, part in slime:GetDescendants() do
		if table.find(PetCloud.GROUND_PARTS, part.Name) and part:IsA("BasePart") then
			part:Destroy()
		end
	end
	local anchor = if template then makeCloud(template, slime) else makeMount()
	anchor.CFrame = CFrame.new()
	anchor.Parent = wrapper
	wrapper.PrimaryPart = anchor
	seat(slime, anchor, template ~= nil)
	slime.Parent = wrapper
	return wrapper
end

function PetCloud.hasCloud(wrapper: Model): boolean
	local primary = wrapper.PrimaryPart
	return primary ~= nil and primary.Name == PetCloud.CLOUD_NAME
end

-- Swap a wrapper's Mount for a cloud clone and re-seat the slime, keeping the wrapper where it is. False if it
-- already has a cloud or is not a wrapper made by mount().
function PetCloud.attach(wrapper: Model, template: BasePart): boolean
	local slime = wrapper:FindFirstChild(PetCloud.SLIME_NAME)
	local old = wrapper.PrimaryPart
	if not (slime and slime:IsA("Model") and old) or PetCloud.hasCloud(wrapper) then
		return false
	end
	local pivot = wrapper:GetPivot()
	wrapper:PivotTo(CFrame.new())
	local cloud = makeCloud(template, slime)
	cloud.CFrame = CFrame.new()
	cloud.Parent = wrapper
	wrapper.PrimaryPart = cloud
	old:Destroy()
	seat(slime, cloud, true)
	wrapper:PivotTo(pivot)
	return true
end

-- The published template under `storage` (ReplicatedStorage), or nil while it is not there.
function PetCloud.find(storage: Instance): BasePart?
	local folder = storage:FindFirstChild(PetCloud.FOLDER)
	local template = folder and folder:FindFirstChild(PetCloud.MESH)
	if template and template:IsA("BasePart") then
		return template
	end
	return nil
end

return PetCloud
