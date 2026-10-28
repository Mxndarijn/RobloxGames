--!strict
--[[
	ShopDisplayFx (VisualsClient module, FEATURES.ExclusiveShop, contract/exclusive-shop.md §7)

	Shows this week's featured seats in the Exclusive Shop's jar on workspace.Map.ExclusiveShopStand (built by
	server/WorldProps, absent when the flag is off): one clone of each of the first featured seats' templates
	(ReplicatedStorage.PetCloudMeshes, ExclusiveRotation.featured) floats over each pedestal, scaled to WorldLayout's
	displayWidth, slowly turning and bobbing (Visuals.ShopDisplay, on the server clock). A seat without a template
	shows as a small lilac cloud until its template shows up. Everything it adds is local; it never fires remotes.
	Past Config.EXCLUSIVE_SHOP.drawDistance from the camera it skips the per-frame work. Call `tick` once a frame from
	the client's frame loop; `stop` removes the seats.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local ExclusiveRotation = require(Shared:WaitForChild("ExclusiveRotation"))
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local PetCloud = require(Visuals:WaitForChild("PetCloud"))
local ShopDisplay = require(Visuals:WaitForChild("ShopDisplay"))

local ShopDisplayFx = {}

ShopDisplayFx.FOLDER_NAME = "ClientShopDisplays"
ShopDisplayFx.FIND_EVERY = 1 -- seconds between looks for the stand, and for a new week or a template that showed up
ShopDisplayFx.PLACEHOLDER_COLOR = Color3.fromRGB(205, 180, 250)
ShopDisplayFx.PLACEHOLDER_SIZE = Vector3.new(2.2, 0.9, 1.6)

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

type Display = { part: BasePart, seat: string?, placeholder: boolean }

type Rig = {
	stand: Model,
	pivot: CFrame, -- the stand's pivot: ShopDisplay's stand frame
	centre: Vector3,
	displays: { Display },
	folder: Folder,
	lastLook: number,
}

local meshOf: { [string]: string } = {}
for _, seat in Config.PET_SEATS do
	meshOf[seat.id] = seat.mesh
end

local function findStand(): Model?
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local model = map and map:FindFirstChild(Constants.SHOP_STAND_EXCLUSIVE)
	return if model and model:IsA("Model") then model else nil
end

local function templateOf(seat: string?): BasePart?
	local mesh = seat and meshOf[seat]
	return if mesh then PetCloud.find(ReplicatedStorage, mesh) else nil
end

local function makeDisplay(seat: string?, parent: Instance): Display
	local template = templateOf(seat)
	local part: BasePart
	if template then
		part = template:Clone()
		local size = part.Size
		part.Size = size * ShopDisplay.scale({ size.X, size.Y, size.Z })
	else
		local cloud = Instance.new("Part")
		cloud.Size = ShopDisplayFx.PLACEHOLDER_SIZE
		cloud.Color = ShopDisplayFx.PLACEHOLDER_COLOR
		cloud.Material = Enum.Material.SmoothPlastic
		local puff = Instance.new("SpecialMesh")
		puff.MeshType = Enum.MeshType.Sphere
		puff.Parent = cloud
		part = cloud
	end
	part.Name = `Display_{seat or "none"}`
	PetCloud.decor(part)
	part.Parent = parent
	return { part = part, seat = seat, placeholder = template == nil }
end

-- Rebuilds the displays whose seat changed (a new week) or that wait on a template that has shown up.
local function refresh(rig: Rig)
	local seats = ShopDisplay.seats(ExclusiveRotation.featured(ExclusiveRotation.week(workspace:GetServerTimeNow())))
	for i = 1, ShopDisplay.COUNT do
		local seat = seats[i]
		local display = rig.displays[i]
		if display and display.seat == seat and not (display.placeholder and templateOf(seat)) then
			continue
		end
		if display then
			display.part:Destroy()
		end
		rig.displays[i] = makeDisplay(seat, rig.folder)
	end
end

local function apply(rig: Rig, t: number)
	local parts, frames = {}, {}
	for i, display in rig.displays do
		local pose = ShopDisplay.pose(i, t)
		table.insert(parts, display.part)
		table.insert(
			frames,
			rig.pivot * CFrame.new(pose.x, pose.y + display.part.Size.Y / 2, pose.z) * CFrame.Angles(0, pose.yaw, 0)
		)
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Builds the displays and puts them on their pedestals at once (a far camera skips the frame updates).
local function build(stand: Model): Rig
	local old = workspace:FindFirstChild(ShopDisplayFx.FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = ShopDisplayFx.FOLDER_NAME
	folder.Parent = workspace
	local pivot = stand:GetPivot()
	local rig: Rig = {
		stand = stand,
		pivot = pivot,
		centre = pivot.Position,
		displays = {},
		folder = folder,
		lastLook = os.clock(),
	}
	refresh(rig)
	apply(rig, workspace:GetServerTimeNow())
	return rig
end

-- Starts watching for the stand. Call `tick` once a frame from the client's frame loop.
function ShopDisplayFx.start(): Controller
	local rig: Rig? = nil
	local lastFind = -math.huge

	local function tick(camera: Camera?)
		local now = os.clock()
		local current = rig
		if current and current.stand.Parent == nil then
			current.folder:Destroy()
			current = nil
			rig = nil
		end
		if not current then
			if now - lastFind < ShopDisplayFx.FIND_EVERY then
				return
			end
			lastFind = now
			local stand = findStand()
			current = if stand then build(stand) else nil
			rig = current
			if not current then
				return
			end
		end
		if camera and (camera.CFrame.Position - current.centre).Magnitude > Config.EXCLUSIVE_SHOP.drawDistance then
			return
		end
		if now - current.lastLook >= ShopDisplayFx.FIND_EVERY then
			current.lastLook = now
			refresh(current)
		end
		apply(current, workspace:GetServerTimeNow())
	end

	return {
		tick = tick,
		stop = function()
			if rig then
				rig.folder:Destroy()
				rig = nil
			end
		end,
	}
end

return ShopDisplayFx
