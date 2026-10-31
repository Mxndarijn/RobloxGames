--!strict
--[[
	ShopDisplayFx (VisualsClient module, contract/exclusive-shop.md §7, §7.2)

	Shows this week's featured seats in the Exclusive Shop's claw shop on workspace.Map.ExclusiveShopStand (built by
	server/WorldProps): one clone of each of the first featured seats' templates (ReplicatedStorage.PetCloudMeshes,
	ExclusiveRotation.featured) stands on each goo pedestal, scaled to WorldLayout's displayWidth, slowly turning and
	bobbing (Visuals.ShopDisplay, on the server clock). A seat without a template shows as a small lilac cloud until its
	template shows up.

	It also plays the claw show (Visuals.ClawShow) for every ClawShow event the server fires after a granted purchase:
	the stand's ClawPiece parts (Constants.CLAW_PIECE_ATTRIBUTE: the Hand and Arm mesh slots with their loaded meshes, and
	their primitive stand-ins) move with the show (the hand slides, the arm stretches from the ceiling hole to it), the
	bought seat leaves its pedestal in the hand (or a prize capsule does), drops into the funnel, pops out of the prize
	chute and flies off under the buyer's banner. Shows play one after the other from their server start times.

	Everything it adds or moves is local; it never fires remotes. Past Config.EXCLUSIVE_SHOP.drawDistance from the
	camera it skips the per-frame work (a show that ends meanwhile puts the claw back at once). Call `tick` once a frame
	from the client's frame loop; `stop` removes the seats and puts the claw back.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local ExclusiveRotation = require(Shared:WaitForChild("ExclusiveRotation"))
local GooPalette = require(Shared:WaitForChild("GooPalette"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local ClawShow = require(Visuals:WaitForChild("ClawShow"))
local PetCloud = require(Visuals:WaitForChild("PetCloud"))
local ShopDisplay = require(Visuals:WaitForChild("ShopDisplay"))
local WorldLayout = require(Visuals:WaitForChild("WorldLayout"))

local ShopDisplayFx = {}

ShopDisplayFx.FOLDER_NAME = "ClientShopDisplays"
ShopDisplayFx.FIND_EVERY = 1 -- seconds between looks for the stand, and for a new week or a template that showed up
ShopDisplayFx.PLACEHOLDER_COLOR = Color3.fromRGB(205, 180, 250)
ShopDisplayFx.PLACEHOLDER_SIZE = Vector3.new(2.2, 0.9, 1.6)
ShopDisplayFx.CAPSULE_SIZE = 1.3 -- studs across the prize capsule
ShopDisplayFx.CAPSULE_COLOR = Color3.fromRGB(196, 166, 232) -- the kit's lilac capsule top
ShopDisplayFx.SPIN_RPM = 40 -- turns per minute of the prize while it hangs over the chute
ShopDisplayFx.MAX_SHOWS = 8 -- shows kept waiting on this client; older ones drop
-- The buyer's banner over the chute (guides/roblox-world-labels.md: a short FX title, studs-sized like the egg hatch
-- title). 1.3 studs of text reads to ~26 studs on a phone, ~70 on a monitor; it hides past bannerDistance.
ShopDisplayFx.BANNER_STUDS = { 9, 1.3 }
ShopDisplayFx.BANNER_LIFT = 2.4 -- studs over the prize's highest point
ShopDisplayFx.BANNER_STROKE = 3

local CLAW = Config.EXCLUSIVE_SHOP.claw
local LAYOUT = WorldLayout.EXCLUSIVE_CLAW
local DOWN = Vector3.new(0, -1, 0)

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> (), play: (event: ClawShow.Event) -> () }

type Display = { part: BasePart, seat: string?, placeholder: boolean }
type Piece = { part: BasePart, kind: string, rest: CFrame, size: Vector3, axis: number }
type Prize = { part: BasePart, size: Vector3 }

type Rig = {
	stand: Model,
	pivot: CFrame, -- the stand's pivot: ShopDisplay's and ClawShow's stand frame
	centre: Vector3,
	displays: { Display },
	folder: Folder,
	lastLook: number,
	pieces: { Piece }?, -- nil = scan again (a mesh loaded)
	moved: boolean, -- the claw is out of its rest pose
	prize: Prize?,
	banner: BillboardGui?,
	bannerAnchor: BasePart?,
	conn: RBXScriptConnection,
}

local meshOf: { [string]: string } = {}
for _, seat in Config.PET_SEATS do
	meshOf[seat.id] = seat.mesh
end

local function color(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function v3(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
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

-- The claw's moving parts at rest: every ClawPiece part and the parts under it (a slot's loaded mesh). `axis` = the
-- part's own axis (1 X, 2 Y, 3 Z) that runs up and down, the one an arm piece stretches along.
local function scan(stand: Model): { Piece }
	local out = {}
	local function add(p: BasePart, kind: string)
		local cf = p.CFrame
		local ups = { math.abs(cf.XVector.Y), math.abs(cf.YVector.Y), math.abs(cf.ZVector.Y) }
		local axis = if ups[1] >= ups[2] and ups[1] >= ups[3] then 1 elseif ups[2] >= ups[3] then 2 else 3
		table.insert(out, { part = p, kind = kind, rest = cf, size = p.Size, axis = axis })
	end
	for _, d in stand:GetDescendants() do
		local kind = d:GetAttribute(Constants.CLAW_PIECE_ATTRIBUTE)
		if d:IsA("BasePart") and (kind == "Hand" or kind == "Arm") then
			add(d, kind)
			for _, inner in d:GetDescendants() do
				if inner:IsA("BasePart") and inner:GetAttribute(Constants.CLAW_PIECE_ATTRIBUTE) == nil then
					add(inner, kind)
				end
			end
		end
	end
	return out
end

local function restore(rig: Rig)
	local pieces = rig.pieces
	if pieces and rig.moved then
		for _, piece in pieces do
			piece.part.CFrame = piece.rest
			piece.part.Size = piece.size
		end
	end
	rig.moved = false
end

-- Puts the hand's top at `hand` (stand frame): hand pieces slide with it, arm pieces turn and stretch so the arm runs
-- from the ceiling hole to it.
local function poseClaw(rig: Rig, hand: { number })
	local pieces = rig.pieces
	if not pieces then
		return
	end
	local pivot = rig.pivot
	local idle = pivot * v3(WorldLayout.clawPoint(LAYOUT.handIdle))
	local root = pivot * v3(WorldLayout.clawPoint(LAYOUT.armRoot))
	local tip = pivot * v3(hand)
	local shift = tip - idle
	local span = tip - root
	local rest = (root - idle).Magnitude
	local stretch = if rest > 0 then span.Magnitude / rest else 1
	local turn = if span.Magnitude > 1e-3 then CFrame.fromRotationBetweenVectors(DOWN, span.Unit) else CFrame.new()
	for _, piece in pieces do
		if piece.kind == "Hand" then
			piece.part.CFrame = piece.rest + shift
		else
			local rel = piece.rest.Position - root
			local scaled = Vector3.new(rel.X, rel.Y * stretch, rel.Z)
			piece.part.CFrame = CFrame.new(root + turn:VectorToWorldSpace(scaled)) * turn * piece.rest.Rotation
			local s = piece.size
			piece.part.Size = Vector3.new(
				if piece.axis == 1 then s.X * stretch else s.X,
				if piece.axis == 2 then s.Y * stretch else s.Y,
				if piece.axis == 3 then s.Z * stretch else s.Z
			)
		end
	end
	rig.moved = true
end

local function makePrize(rig: Rig, display: number): Prize
	local shown = rig.displays[display]
	local part: BasePart
	if shown then
		part = shown.part:Clone()
	else
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * ShopDisplayFx.CAPSULE_SIZE
		ball.Color = ShopDisplayFx.CAPSULE_COLOR
		ball.Material = Enum.Material.SmoothPlastic
		PetCloud.decor(ball)
		part = ball
	end
	part.Name = "ClawPrize"
	part.Parent = rig.folder
	return { part = part, size = part.Size }
end

local function makeBanner(rig: Rig, text: string): (BasePart, BillboardGui)
	local anchor = Instance.new("Part")
	anchor.Name = "ClawBanner"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	local mouth = WorldLayout.clawPoint(LAYOUT.chuteMouth)
	local at = v3(mouth) + Vector3.new(0, CLAW.popRise + ShopDisplayFx.BANNER_LIFT, -CLAW.popOut)
	anchor.CFrame = CFrame.new(rig.pivot * at)
	anchor.Parent = rig.folder
	local gui = Instance.new("BillboardGui")
	gui.Name = "BannerGui"
	gui.Size = UDim2.fromScale(ShopDisplayFx.BANNER_STUDS[1], ShopDisplayFx.BANNER_STUDS[2])
	gui.AlwaysOnTop = false
	gui.MaxDistance = CLAW.bannerDistance
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color(GooPalette.GoldHi)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = ShopDisplayFx.BANNER_STROKE
	stroke.Color = color(GooPalette.Ink)
	stroke.Parent = label
	return anchor, gui
end

local function endShow(rig: Rig)
	if rig.prize then
		rig.prize.part:Destroy()
		rig.prize = nil
	end
	if rig.bannerAnchor then
		rig.bannerAnchor:Destroy()
		rig.bannerAnchor = nil
		rig.banner = nil
	end
	restore(rig)
end

local function apply(rig: Rig, t: number, show: ClawShow.Event?)
	local frame = if show then ClawShow.frame(show.display, t - show.startAt) else nil
	local parts, frames = {}, {}
	for i, display in rig.displays do
		local pose = ShopDisplay.pose(i, t)
		table.insert(parts, display.part)
		if frame and frame.holding and show and show.display == i then
			-- out of its spot while the claw has it: tucked under the box floor
			table.insert(frames, rig.pivot * CFrame.new(pose.x, -display.part.Size.Y, pose.z))
		else
			table.insert(
				frames,
				rig.pivot * CFrame.new(pose.x, pose.y + display.part.Size.Y / 2, pose.z) * CFrame.Angles(0, pose.yaw, 0)
			)
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	if not (frame and show) then
		return
	end
	if rig.pieces == nil then
		rig.pieces = scan(rig.stand)
	end
	poseClaw(rig, frame.hand)
	local p = frame.prize
	if p then
		local prize = rig.prize or makePrize(rig, show.display)
		rig.prize = prize
		local size = prize.size * p.scale
		prize.part.Size = size
		local spin = if frame.banner then 2 * math.pi * ShopDisplayFx.SPIN_RPM / 60 * t else 0
		prize.part.CFrame = rig.pivot
			* CFrame.new(v3(p.pos) + Vector3.new(0, size.Y / 2, 0))
			* CFrame.Angles(0, spin, 0)
	elseif rig.prize then
		rig.prize.part.Size = Vector3.zero
		rig.prize.part.CFrame = rig.pivot * CFrame.new(0, -10, 0)
	end
	if frame.banner and not rig.bannerAnchor then
		rig.bannerAnchor, rig.banner = makeBanner(rig, ClawShow.bannerText(show))
	end
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
	local rig: Rig
	rig = {
		stand = stand,
		pivot = pivot,
		centre = pivot.Position,
		displays = {},
		folder = folder,
		lastLook = os.clock(),
		pieces = nil,
		moved = false,
		prize = nil,
		banner = nil,
		bannerAnchor = nil,
		-- a mesh that loads into a slot (MeshSwap) joins the claw at the next rest
		conn = stand.DescendantAdded:Connect(function()
			if not rig.moved then
				rig.pieces = nil
			end
		end),
	}
	refresh(rig)
	apply(rig, workspace:GetServerTimeNow(), nil)
	return rig
end

local function teardown(rig: Rig)
	endShow(rig)
	rig.conn:Disconnect()
	rig.folder:Destroy()
end

-- Starts watching for the stand and listening for claw shows. Call `tick` once a frame from the client's frame loop.
function ShopDisplayFx.start(): Controller
	local rig: Rig? = nil
	local lastFind = -math.huge
	local shows: { ClawShow.Event } = {}
	local playing: ClawShow.Event? = nil

	local function play(event: ClawShow.Event)
		if type(event) ~= "table" or type(event.startAt) ~= "number" or type(event.display) ~= "number" then
			return
		end
		table.insert(shows, event)
		table.sort(shows, function(a, b)
			return a.startAt < b.startAt
		end)
		while #shows > ShopDisplayFx.MAX_SHOWS do
			table.remove(shows, 1)
		end
	end

	-- The show to play at server time t: the first one that has started and not ended; ended ones drop.
	local function current(t: number): ClawShow.Event?
		while shows[1] and t >= shows[1].startAt + ClawShow.DURATION do
			table.remove(shows, 1)
		end
		local first = shows[1]
		return if first and t >= first.startAt then first else nil
	end

	local function tick(camera: Camera?)
		local now = os.clock()
		local live = rig
		if live and live.stand.Parent == nil then
			teardown(live)
			live = nil
			rig = nil
		end
		if not live then
			if now - lastFind < ShopDisplayFx.FIND_EVERY then
				return
			end
			lastFind = now
			local stand = findStand()
			live = if stand then build(stand) else nil
			rig = live
			if not live then
				return
			end
		end
		local here = live :: Rig -- found or built above
		local t = workspace:GetServerTimeNow()
		local show = current(t)
		if show ~= playing then
			endShow(here)
			playing = show
		end
		if camera and (camera.CFrame.Position - here.centre).Magnitude > Config.EXCLUSIVE_SHOP.drawDistance then
			return
		end
		if now - here.lastLook >= ShopDisplayFx.FIND_EVERY then
			here.lastLook = now
			refresh(here)
		end
		apply(here, t, show)
	end

	local remote = Remotes.get(Constants.CLAW_SHOW) :: RemoteEvent
	local conn = remote.OnClientEvent:Connect(play)

	return {
		tick = tick,
		play = play,
		stop = function()
			conn:Disconnect()
			if rig then
				teardown(rig)
				rig = nil
			end
		end,
	}
end

return ShopDisplayFx
