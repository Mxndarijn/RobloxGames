--!strict
--[[
	CarouselFx (VisualsClient module, FEATURES.ExclusiveShop, contract/exclusive-shop.md §7)

	Turns the Exclusive Shop carousel on workspace.Map.ExclusiveShopStand (built by server/WorldProps, absent when
	the flag is off) and seats its riders. Everything it moves or adds is local; it never fires remotes.
	  * the stand's ExclusiveCarouselSpin part and every part under it (the deck, drum and poles, the kit mesh once
	    MeshSwap places it) turn about the spin axis at Config.EXCLUSIVE_SHOP.spinRpm, on the server clock
	  * 8 riders, one over each pole: clones of the week's featured seats' templates (ReplicatedStorage.PetCloudMeshes,
	    ExclusiveRotation.featured, each seat twice), scaled to WorldLayout's riderWidth, bobbing out of phase and
	    facing along the turn (Visuals.CarouselRide); a seat without a template rides as a small lilac cloud until
	    its template shows up
	Past Config.EXCLUSIVE_SHOP.drawDistance from the camera it skips the per-frame work. Call `tick` once a frame
	from the client's frame loop; `stop` puts the spin parts back and removes the riders.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local ExclusiveRotation = require(Shared:WaitForChild("ExclusiveRotation"))
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local CarouselRide = require(Visuals:WaitForChild("CarouselRide"))
local PetCloud = require(Visuals:WaitForChild("PetCloud"))

local CarouselFx = {}

CarouselFx.FOLDER_NAME = "ClientCarouselRiders"
CarouselFx.FIND_EVERY = 1 -- seconds between looks for the stand, and for a new week or a template that showed up
CarouselFx.PLACEHOLDER_COLOR = Color3.fromRGB(205, 180, 250)
CarouselFx.PLACEHOLDER_SIZE = Vector3.new(2.4, 1, 1.8)

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

type Rider = { part: BasePart, seat: string?, placeholder: boolean }

type Rig = {
	stand: Model,
	spin: BasePart,
	bottom: CFrame, -- the spin slot's bottom centre, unturned (CarouselRide's spin frame)
	centre: Vector3,
	offsets: { [BasePart]: CFrame }, -- each turning part in the spin frame
	riders: { Rider },
	folder: Folder,
	conns: { RBXScriptConnection },
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
	local folder = ReplicatedStorage:FindFirstChild(PetCloud.FOLDER)
	local mesh = seat and meshOf[seat]
	local template = folder and mesh and folder:FindFirstChild(mesh)
	return if template and template:IsA("BasePart") then template else nil
end

local function makeRider(seat: string?, parent: Instance): Rider
	local template = templateOf(seat)
	local part: BasePart
	if template then
		part = template:Clone()
		local size = part.Size
		part.Size = size * CarouselRide.riderScale({ size.X, size.Y, size.Z })
	else
		local cloud = Instance.new("Part")
		cloud.Size = CarouselFx.PLACEHOLDER_SIZE
		cloud.Color = CarouselFx.PLACEHOLDER_COLOR
		cloud.Material = Enum.Material.SmoothPlastic
		local puff = Instance.new("SpecialMesh")
		puff.MeshType = Enum.MeshType.Sphere
		puff.Parent = cloud
		part = cloud
	end
	part.Name = `Rider_{seat or "none"}`
	PetCloud.decor(part)
	part.Parent = parent
	return { part = part, seat = seat, placeholder = template == nil }
end

-- Rebuilds the riders whose seat changed (a new week) or that wait on a template that has shown up.
local function refreshRiders(rig: Rig)
	local seats =
		CarouselRide.riderSeats(ExclusiveRotation.featured(ExclusiveRotation.week(workspace:GetServerTimeNow())))
	for i = 1, CarouselRide.RIDERS do
		local seat = seats[i]
		local rider = rig.riders[i]
		if rider and rider.seat == seat and not (rider.placeholder and templateOf(seat)) then
			continue
		end
		if rider then
			rider.part:Destroy()
		end
		rig.riders[i] = makeRider(seat, rig.folder)
	end
end

local function track(rig: Rig, inst: Instance)
	if inst:IsA("BasePart") and rig.offsets[inst] == nil then
		-- The server placed it unturned; keep where it sits in the spin frame.
		rig.offsets[inst] = rig.bottom:ToObjectSpace(inst.CFrame)
	end
end

local function build(stand: Model): Rig?
	local spin = stand:FindFirstChild(Constants.EXCLUSIVE_CAROUSEL_SPIN)
	if not (spin and spin:IsA("BasePart")) then
		return nil
	end
	local old = workspace:FindFirstChild(CarouselFx.FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = CarouselFx.FOLDER_NAME
	folder.Parent = workspace
	local bottom = spin.CFrame * CFrame.new(0, -spin.Size.Y / 2, 0)
	local rig: Rig = {
		stand = stand,
		spin = spin,
		bottom = bottom,
		centre = spin.Position,
		offsets = {},
		riders = {},
		folder = folder,
		conns = {},
		lastLook = os.clock(),
	}
	track(rig, spin)
	for _, d in spin:GetDescendants() do
		track(rig, d)
	end
	table.insert(
		rig.conns,
		spin.DescendantAdded:Connect(function(d: Instance)
			track(rig, d)
		end)
	)
	table.insert(
		rig.conns,
		spin.DescendantRemoving:Connect(function(d: Instance)
			if d:IsA("BasePart") then
				rig.offsets[d] = nil
			end
		end)
	)
	refreshRiders(rig)
	return rig
end

local function teardown(rig: Rig)
	for _, c in rig.conns do
		c:Disconnect()
	end
	local parts, frames = {}, {}
	for part, offset in rig.offsets do
		if part.Parent then
			table.insert(parts, part)
			table.insert(frames, rig.bottom * offset)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	rig.folder:Destroy()
end

local function apply(rig: Rig, t: number)
	local turn = rig.bottom * CFrame.Angles(0, CarouselRide.angle(t), 0)
	local parts, frames = {}, {}
	for part, offset in rig.offsets do
		table.insert(parts, part)
		table.insert(frames, turn * offset)
	end
	for i, rider in rig.riders do
		local pose = CarouselRide.pose(i, t)
		table.insert(parts, rider.part)
		table.insert(
			frames,
			rig.bottom * CFrame.new(pose.x, pose.y + rider.part.Size.Y / 2, pose.z) * CFrame.Angles(0, pose.yaw, 0)
		)
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Starts watching for the stand. Call `tick` once a frame from the client's frame loop.
function CarouselFx.start(): Controller
	local rig: Rig? = nil
	local lastFind = -math.huge

	local function tick(camera: Camera?)
		local now = os.clock()
		local current = rig
		if current and current.stand.Parent == nil then
			teardown(current)
			current = nil
			rig = nil
		end
		if not current then
			if now - lastFind < CarouselFx.FIND_EVERY then
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
		if now - current.lastLook >= CarouselFx.FIND_EVERY then
			current.lastLook = now
			refreshRiders(current)
		end
		apply(current, workspace:GetServerTimeNow())
	end

	return {
		tick = tick,
		stop = function()
			if rig then
				teardown(rig)
				rig = nil
			end
		end,
	}
end

return CarouselFx
