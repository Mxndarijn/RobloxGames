--!strict
--[[
	PetCloud (follow pet mount, Roblox types at call time only)

	Builds the wrapper a FollowPets pet glides in: Model "Pet_<id>" = PrimaryPart + "Slime" standing on it. With a
	cloud template (the MeshPart the server publishes under ReplicatedStorage.PetCloudMeshes, native size) the
	PrimaryPart is a clone of it at CLOUD_SCALE and the slime's foot sinks CLOUD_SINK into its top. Without one a
	small invisible Mount is the PrimaryPart and the slime stands level with the owner's feet. attach() swaps a
	Mount for a cloud later, so a pet never waits for the template. The wrapper's pivot is the PrimaryPart centre:
	PetFollow's goal. Every part made here is decor (no collision, query, touch or shadow).
]]

local PetFollow = if script then require(script.Parent.PetFollow) else require("./PetFollow")

local PetCloud = {}

PetCloud.MESH = "pet_cloud" -- MeshAssets name, and the template's name in the folder
PetCloud.FOLDER = "PetCloudMeshes" -- ReplicatedStorage folder the server publishes the template into
PetCloud.CLOUD_SCALE = 0.9 -- of the native 3.3 x 1.2 x 2.4 mesh
PetCloud.CLOUD_SINK = 0.12 -- the slime's foot sinks this far into the cloud's top (studs)
PetCloud.CLOUD_NAME = "Cloud"
PetCloud.MOUNT_NAME = "Mount"
PetCloud.SLIME_NAME = "Slime"

-- Anchored, no collision, no query, no touch, no shadow.
function PetCloud.decor(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function makeCloud(template: BasePart): BasePart
	local cloud = template:Clone()
	cloud.Name = PetCloud.CLOUD_NAME
	cloud.Size = template.Size * PetCloud.CLOUD_SCALE
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

-- Slime centred over `anchor` (at the origin), its foot sunk CLOUD_SINK into the cloud's top; on a Mount the
-- foot is at the owner's feet (PetFollow.OFFSET_Y is the root-to-anchor drop, the root sits 3 studs above them).
local function seat(slime: Model, anchor: BasePart, cloud: boolean)
	local top = if cloud then anchor.Size.Y / 2 else -PetFollow.OFFSET_Y - 3
	slime:PivotTo(CFrame.new())
	local box, size = slime:GetBoundingBox()
	local foot = box.Position.Y - size.Y / 2
	local sink = if cloud then PetCloud.CLOUD_SINK else 0
	slime:PivotTo(CFrame.new(-box.Position.X, top - sink - foot, -box.Position.Z))
end

-- The wrapper for `slime` (renamed "Slime"): on a clone of `template` or, without one, on a Mount.
function PetCloud.mount(slime: Model, userId: number, template: BasePart?): Model
	local wrapper = Instance.new("Model")
	wrapper.Name = `Pet_{userId}`
	slime.Name = PetCloud.SLIME_NAME
	local anchor = if template then makeCloud(template) else makeMount()
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
	local cloud = makeCloud(template)
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
