--!strict
--[[
	ObbyView (Roblox adapter, contract/obby.md)

	Builds workspace.Obby: the portal (the Goo Ring at the end of the obby path, ObbyParts.gooRing, and a goo-topped
	status signpost beside it; kit meshes swapped in by server/MeshSwap; no light column, the path and the OBBY arch
	lead players there) once. The course itself is client-only:
	`build` publishes the slot standing now (Constants.OBBY_SLOT on workspace.Obby) and every client builds the
	course from it in the obby's own world (visuals/client/ObbyCourseView with visuals/shared/ObbyParts; the backdrop
	is visuals/client/ObbyBackdrop), so the server's part budget never carries it. `positions` reads every live
	character's root position for ObbyService.step and `apply` makes its teleports. Holds no rules.

	The portal sign is a SurfaceGui (landmark, guides/roblox-world-labels.md): a 1.4-stud title reads from about 25
	studs on a phone, the 1-stud status lines from about 20; the client fills the two lines per player (ui/ObbyHud).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ObbyCourse = require(ReplicatedStorage.Shared.ObbyCourse)
local ObbyParts = require(ReplicatedStorage.Visuals.ObbyParts)
local ObbyService = require(script.Parent.ObbyService)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)
local WorldView = require(script.Parent.WorldView)

local ObbyView = {}

local PORTAL = table.freeze({
	sign = "obby_goo_sign", -- MeshAsset: the goo-topped signpost beside the ring (shared/modeling-kit)
	signSize = Vector3.new(10.516, 7.67, 3.066), -- its native size
	-- Where it stands from the ring's foot, in the ring's own axes (X right as you face the ring, Z towards you), and
	-- how far it turns towards the path.
	signAt = Vector3.new(11.5, 0, -1.5),
	signTurn = 22, -- degrees
	-- The board's face on the sign mesh, from the mesh box's bottom centre (the box's -Z is the sign's front): text
	-- goes on an invisible part over it, both faces.
	face = { size = Vector3.new(8, 3.6, 0.76), at = Vector3.new(0.45, 4.9, 0.91) },
	maxDistance = 200, -- landmark sign; past ~60 studs it reads only as a shape (400 x 180 canvas)
})

local folder: Folder? = nil
local place: ObbyService.Place? = nil

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local existing = workspace:FindFirstChild(Constants.OBBY_FOLDER)
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = Constants.OBBY_FOLDER
	f.Parent = workspace
	folder = f
	return f
end

-- Ground height under (x, z): a ray down onto the map, ignoring the obby itself; 0 if nothing is hit.
local function groundAt(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getFolder() }
	local hit = workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -240, 0), params)
	return if hit then hit.Position.Y else 0
end

-- Where the course and portal stand (computed once; the ground is read with a ray).
function ObbyView.place(): ObbyService.Place
	if place then
		return place
	end
	local portal, toCentre = WorldLayout.obbyPortal()
	local y = groundAt(portal[1], portal[3])
	local a = math.rad(toCentre)
	local step = WorldLayout.OBBY.exitStep
	local origin, yaw = WorldLayout.obbyFrame()
	local centre, radius = WorldLayout.obbyZone()
	local p: ObbyService.Place = {
		frame = { origin = origin, yaw = yaw },
		portal = { portal[1], y, portal[3] },
		portalRadius = WorldLayout.OBBY.portalRadius,
		exit = { portal[1] + math.sin(a) * step, y + 3, portal[3] + math.cos(a) * step },
		exitYaw = (toCentre + 180) % 360,
		zone = { centre = centre, radius = radius },
	}
	place = p
	return p
end

-- Publishes `course` as the one standing now: workspace.Obby's Constants.OBBY_SLOT attribute. Every client builds
-- the course from it (visuals/client/ObbyCourseView, ObbyParts), so the server holds no course parts.
function ObbyView.build(course: ObbyCourse.Course)
	getFolder():SetAttribute(Constants.OBBY_SLOT, course.slot)
end

-- Builds workspace.Obby.Portal (once).
function ObbyView.buildPortal()
	local root = getFolder()
	if root:FindFirstChild(Constants.OBBY_PORTAL) then
		return
	end
	local p = ObbyView.place()
	local model = Instance.new("Model")
	model.Name = Constants.OBBY_PORTAL
	local base = Vector3.new(p.portal[1], p.portal[2], p.portal[3])
	-- The Goo Ring faces the plaza: you walk through it along the obby path. Its meshes and the sign's are swapped in
	-- by server/MeshSwap (init.server calls MeshSwap.applyUnder on the portal).
	local _, yaw = WorldLayout.obbyPortal()
	local a = math.rad(yaw)
	local towards = Vector3.new(math.sin(a), 0, math.cos(a)) -- towards the map centre
	local ground = CFrame.lookAt(base, base + towards)
	ObbyParts.gooRing(ground, 1, model, "")
	-- The signpost beside the ring, a little in front of it and turned towards the path.
	local signCf = ground
		* CFrame.new(PORTAL.signAt.X, 0, -PORTAL.signAt.Z)
		* CFrame.Angles(0, math.rad(PORTAL.signTurn), 0)
	local post = Instance.new("Part")
	post.Name = "SignPost"
	post.Size = PORTAL.signSize
	post.CFrame = signCf * CFrame.new(0, PORTAL.signSize.Y / 2, 0)
	post.Transparency = 1
	post.Anchored = true
	post.CanCollide = false
	post.CanQuery = false
	post.CanTouch = false
	post:SetAttribute("MeshAsset", PORTAL.sign)
	post.Parent = model
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Size = PORTAL.face.size
	sign.CFrame = signCf * CFrame.new(PORTAL.face.at)
	sign.Transparency = 1
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.CanTouch = false
	sign.Parent = model
	-- The same sign on both faces: from the plaza and from the portal side. ObbyHud fills every Status and
	-- CourseInfo label it finds.
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = `SignGui{face.Name}`
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = ObbyParts.PIXELS_PER_STUD
		gui.MaxDistance = PORTAL.maxDistance
		gui.LightInfluence = 0
		gui.Adornee = sign
		ObbyParts.signLabel(gui, "Title", "OBBY", 0.04, 0.38, 80)
		ObbyParts.signLabel(gui, Constants.OBBY_SIGN_STATUS, "Step in: x1.5 income!", 0.46, 0.26, 50)
		ObbyParts.signLabel(gui, Constants.OBBY_SIGN_COURSE, "A new course every 10 min", 0.75, 0.2, 40)
		gui.Parent = sign
	end
	model.Parent = root
end

-- Root position of every player with a live character, for ObbyService.step.
function ObbyView.positions(): { [number]: ObbyCourse.Vec }
	local out: { [number]: ObbyCourse.Vec } = {}
	for _, player in Players:GetPlayers() do
		local root = WorldView.rootPart(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local p = root.Position
			out[player.UserId] = { p.X, p.Y, p.Z }
		end
	end
	return out
end

-- Makes ObbyService's teleports. Calls `moved(userId)` after each one (the anti-cheat's server-moved window).
function ObbyView.apply(moves: { ObbyService.Move }, moved: (userId: number) -> ())
	for _, move in moves do
		local player = Players:GetPlayerByUserId(move.userId)
		local character = player and player.Character
		local root = WorldView.rootPart(player)
		if character and root then
			local a = math.rad(move.yaw)
			local pos = Vector3.new(move.pos[1], move.pos[2], move.pos[3])
			moved(move.userId)
			character:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(math.sin(a), 0, math.cos(a))))
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

return ObbyView
