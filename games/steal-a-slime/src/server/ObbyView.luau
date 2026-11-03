--!strict
--[[
	ObbyView (Roblox adapter, contract/obby.md)

	Builds workspace.Obby: the portal (the Goo Ring at the end of the obby path, ObbyParts.gooRing; kit meshes swapped
	in by server/MeshSwap; no light column, the path and the OBBY arch lead players there) once. The course itself is client-only:
	`build` publishes the slot standing now (Constants.OBBY_SLOT on workspace.Obby) and every client builds the
	course from it in the obby's own world (visuals/client/ObbyCourseView with visuals/shared/ObbyParts; the backdrop
	is visuals/client/ObbyBackdrop), so the server's part budget never carries it. `positions` reads every live
	character's root position for ObbyService.step and `apply` makes its teleports. Holds no rules.

	The OBBY sign board and the course board on either side of the ring are server/ObbyBoardView.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local ObbyCourse = require(ReplicatedStorage.Shared.ObbyCourse)
local ObbyParts = require(ReplicatedStorage.Visuals.ObbyParts)
local ObbyService = require(script.Parent.ObbyService)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)
local WorldView = require(script.Parent.WorldView)

local ObbyView = {}

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
		-- a standard root's height over the ground; `apply` adds what a bigger avatar needs (ObbyService.landing)
		exit = { portal[1] + math.sin(a) * step, y + Config.OBBY.RESPAWN_LIFT, portal[3] + math.cos(a) * step },
		exitYaw = toCentre, -- facing the plaza, back to the portal: the camera lands behind them looking where they go
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

-- The sign's course line before the client fills it: "A new course every 30 min".
function ObbyView.everyText(): string
	return `A new course every {math.floor(Config.OBBY.ROTATION_SECONDS / 60 + 0.5)} min`
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
	-- The Goo Ring faces the plaza: you walk through it along the obby path. Its meshes are swapped in
	-- by server/MeshSwap (init.server calls MeshSwap.applyUnder on the portal).
	local _, yaw = WorldLayout.obbyPortal()
	local a = math.rad(yaw)
	local towards = Vector3.new(math.sin(a), 0, math.cos(a)) -- towards the map centre
	local ground = CFrame.lookAt(base, base + towards)
	ObbyParts.gooRing(ground, 1, model, "")
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
			-- after server/ObbyAvatar's scale swap, which sets HipHeight and the root's size at once
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local at = if humanoid
				then ObbyService.landing(move.pos, humanoid.HipHeight + root.Size.Y / 2)
				else move.pos
			local pos = Vector3.new(at[1], at[2], at[3])
			moved(move.userId)
			character:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(math.sin(a), 0, math.cos(a))))
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

return ObbyView
