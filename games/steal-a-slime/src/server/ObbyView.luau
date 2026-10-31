--!strict
--[[
	ObbyView (Roblox adapter, contract/obby.md)

	Builds workspace.Obby: the portal (a goo ring and floor on the ground at the end of the obby path, and a status
	sign; no light column, the path and the OBBY arch lead players there) once. The course itself is client-only:
	`build` publishes the slot standing now (Constants.OBBY_SLOT on workspace.Obby) and every client builds the
	course from it in the obby's own world (visuals/client/ObbyCourseView with visuals/shared/ObbyParts; the backdrop
	is visuals/client/ObbyBackdrop), so the server's part budget never carries it. `positions` reads every live
	character's root position for ObbyService.step and `apply` makes its teleports. Holds no rules.

	The portal sign is a SurfaceGui (landmark, guides/roblox-world-labels.md): a 1.6-stud title reads from about 30
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
	ring = ObbyParts.COLORS.ring,
	floor = ObbyParts.COLORS.floor,
	sign = ObbyParts.COLORS.sign,
	signSize = Vector3.new(10, 5, 0.4), -- studs
	signLift = 2, -- studs from the ground to the sign's bottom edge
	maxDistance = 200, -- landmark sign; past ~60 studs it reads only as a shape (500 x 250 canvas)
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
	local r = p.portalRadius
	local function cylinder(
		name: string,
		height: number,
		radius: number,
		y: number,
		color: Color3,
		transparency: number
	)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(height, radius * 2, radius * 2)
		part.CFrame = CFrame.new(base + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Color = color
		part.Transparency = transparency
		part.Material = Enum.Material.Neon
		part.CastShadow = false
		part.Parent = model
		return part
	end
	cylinder("Ring", 0.4, r + 0.6, 0.2, PORTAL.ring, 0)
	cylinder("Floor", 0.5, r, 0.3, PORTAL.floor, 0.4).Material = Enum.Material.SmoothPlastic

	-- The sign stands behind the portal (away from the plaza) and faces the plaza.
	local _, yaw = WorldLayout.obbyPortal()
	local a = math.rad(yaw)
	local towards = Vector3.new(math.sin(a), 0, math.cos(a)) -- towards the map centre
	local signPos = base
		- towards * WorldLayout.OBBY.signStep
		+ Vector3.new(0, PORTAL.signLift + PORTAL.signSize.Y / 2, 0)
	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Anchored = true
	sign.Size = PORTAL.signSize
	sign.CFrame = CFrame.lookAt(signPos, signPos + towards)
	sign.Color = PORTAL.sign
	sign.Material = Enum.Material.SmoothPlastic
	sign.Parent = model
	-- The posts run up inside the board (thinner than it, and stopping just under its top so no faces meet), so they
	-- show only under it and cover neither face.
	local postInset = 0.1
	for _, side in { -1, 1 } do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Anchored = true
		post.Size = Vector3.new(0.6, PORTAL.signLift + PORTAL.signSize.Y - postInset, PORTAL.signSize.Z * 0.9)
		post.CFrame = sign.CFrame
			* CFrame.new(side * (PORTAL.signSize.X / 2 - 0.6), -(PORTAL.signLift + postInset) / 2, 0)
		post.Color = PORTAL.sign
		post.Parent = model
	end
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
		ObbyParts.signLabel(gui, "Title", "OBBY", 0.06, 0.32, 80)
		ObbyParts.signLabel(gui, Constants.OBBY_SIGN_STATUS, "Step in: x1.5 income!", 0.42, 0.24, 50)
		ObbyParts.signLabel(gui, Constants.OBBY_SIGN_COURSE, "A new course every 10 min", 0.7, 0.2, 40)
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
