--!strict
--[[
	ObbyView (Roblox adapter, contract/obby.md)

	Builds the Goo Gauntlet in workspace.Obby: the portal (a goo ring on the ground, a see-through light column and a
	status sign) once, and the course (`build`, from ObbyCourse data) each rotation. Moving parts get their rest
	CFrame and motion as attributes (the OBBY_* names in Constants); visuals/client/ObbyFx plays them on every client. Belts get a
	surface velocity, ice no friction. `positions` reads every live character's root position for ObbyService.step
	and `apply` makes its teleports. Holds no rules.

	The portal sign is a SurfaceGui (landmark, guides/roblox-world-labels.md): a 1.6-stud title reads from about 30
	studs on a phone, the 1-stud status lines from about 20; the client fills the two lines per player (ui/ObbyHud).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local ObbyCourse = require(ReplicatedStorage.Shared.ObbyCourse)
local ObbyService = require(script.Parent.ObbyService)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)
local WorldView = require(script.Parent.WorldView)

local ObbyView = {}

-- Look per part kind: colour (or three tones), material, transparency.
type Look = { colors: { Color3 }, material: Enum.Material, transparency: number? }
local LOOKS: { [string]: Look } = {
	start = { colors = { Color3.fromRGB(120, 226, 170) }, material = Enum.Material.SmoothPlastic },
	pad = { colors = { Color3.fromRGB(236, 246, 240) }, material = Enum.Material.SmoothPlastic },
	finish = { colors = { Color3.fromRGB(255, 206, 64) }, material = Enum.Material.SmoothPlastic },
	jelly = {
		colors = { Color3.fromRGB(255, 120, 190), Color3.fromRGB(120, 220, 120), Color3.fromRGB(110, 170, 255) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.15,
	},
	goo = {
		colors = { Color3.fromRGB(150, 230, 70), Color3.fromRGB(120, 205, 60) },
		material = Enum.Material.SmoothPlastic,
	},
	bubble = {
		colors = { Color3.fromRGB(170, 235, 255), Color3.fromRGB(200, 225, 255), Color3.fromRGB(190, 255, 240) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.3,
	},
	ice = { colors = { Color3.fromRGB(190, 230, 255) }, material = Enum.Material.Ice },
	rope = {
		colors = { Color3.fromRGB(230, 180, 90), Color3.fromRGB(210, 160, 80), Color3.fromRGB(240, 200, 110) },
		material = Enum.Material.Wood,
	},
	tile = {
		colors = { Color3.fromRGB(160, 110, 240), Color3.fromRGB(255, 160, 60), Color3.fromRGB(110, 200, 230) },
		material = Enum.Material.SmoothPlastic,
	},
	post = { colors = { Color3.fromRGB(70, 60, 90) }, material = Enum.Material.SmoothPlastic },
	bar = { colors = { Color3.fromRGB(235, 70, 120) }, material = Enum.Material.Neon },
	trampoline = {
		colors = { Color3.fromRGB(80, 170, 255), Color3.fromRGB(255, 110, 200) },
		material = Enum.Material.Neon,
	},
	cannon = { colors = { Color3.fromRGB(255, 140, 40) }, material = Enum.Material.Neon },
	blob = {
		colors = { Color3.fromRGB(130, 230, 90) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.1,
	},
	pipe = {
		colors = { Color3.fromRGB(150, 230, 70) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.7,
	},
	truss = { colors = { Color3.fromRGB(255, 120, 190) }, material = Enum.Material.SmoothPlastic },
	fan = { colors = { Color3.fromRGB(90, 96, 120) }, material = Enum.Material.DiamondPlate },
	wind = {
		colors = { Color3.fromRGB(235, 250, 255) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.85,
	},
	plank = {
		colors = { Color3.fromRGB(200, 150, 90), Color3.fromRGB(180, 130, 75) },
		material = Enum.Material.Wood,
	},
	gate = { colors = { Color3.fromRGB(235, 70, 120) }, material = Enum.Material.SmoothPlastic, transparency = 0.2 },
}

local PORTAL = table.freeze({
	ring = Color3.fromRGB(150, 230, 70),
	column = Color3.fromRGB(170, 255, 140),
	columnHeight = 60, -- studs: a light you spot from the plaza
	columnTransparency = 0.82,
	sign = Color3.fromRGB(46, 38, 70),
	ink = Color3.fromRGB(255, 255, 255),
	stroke = Color3.fromRGB(30, 22, 48),
	signSize = Vector3.new(10, 5, 0.4), -- studs
	signLift = 2, -- studs from the ground to the sign's bottom edge
	pixelsPerStud = 50, -- 500 x 250 canvas
	maxDistance = 200, -- landmark sign; past ~60 studs it reads only as a shape
	font = Enum.Font.FredokaOne,
})

local ICE = PhysicalProperties.new(0.9, 0, 0.5, 100, 1)

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
	local portal, yaw = WorldLayout.obbyPortal()
	local y = groundAt(portal[1], portal[3])
	local a = math.rad(yaw)
	local step = WorldLayout.OBBY.exitStep
	local p: ObbyService.Place = {
		frame = { origin = { portal[1], y + WorldLayout.OBBY.skyHeight, portal[3] }, yaw = yaw },
		portal = { portal[1], y, portal[3] },
		portalRadius = WorldLayout.OBBY.portalRadius,
		exit = { portal[1] + math.sin(a) * step, y + 3, portal[3] + math.cos(a) * step },
	}
	place = p
	return p
end

-- The course frame as a CFrame: X forward, Y up, Z right (ObbyCourse's course-local axes).
local function frameCFrame(frame: ObbyCourse.Frame): CFrame
	local a = math.rad(frame.yaw)
	local forward = Vector3.new(math.sin(a), 0, math.cos(a))
	local right = Vector3.new(-math.cos(a), 0, math.sin(a))
	local o = frame.origin
	return CFrame.fromMatrix(Vector3.new(o[1], o[2], o[3]), forward, Vector3.yAxis, right)
end

local function localVec(cf: CFrame, axis: string?): Vector3
	if axis == "x" then
		return cf.XVector
	elseif axis == "y" then
		return cf.YVector
	end
	return cf.ZVector
end

local function makePart(spec: ObbyCourse.Part, frameCf: CFrame, parent: Instance)
	local look = LOOKS[spec.look] or LOOKS.pad
	local part: BasePart = if spec.shape == "truss" then Instance.new("TrussPart") else Instance.new("Part")
	part.Name = spec.look
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = look.material
	part.Color = look.colors[math.clamp(spec.tone or 1, 1, #look.colors)]
	part.Transparency = look.transparency or 0
	part.CastShadow = false
	local center = frameCf * CFrame.new(spec.pos[1], spec.pos[2], spec.pos[3])
	local disc = spec.shape == "disc"
	if disc then
		-- A cylinder's axis is its X: lay it on its side so a flat face points up.
		(part :: Part).Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(spec.size[2], spec.size[1], spec.size[3])
		part.CFrame = center * CFrame.Angles(0, 0, math.rad(90))
	else
		if spec.shape == "ball" then
			(part :: Part).Shape = Enum.PartType.Ball
		end
		part.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
		part.CFrame = center
	end
	if spec.ghost then
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	if spec.ice then
		part.CustomPhysicalProperties = ICE
	end
	if spec.conveyor then
		local v = spec.conveyor
		part.AssemblyLinearVelocity = frameCf.XVector * v[1] + frameCf.YVector * v[2] + frameCf.ZVector * v[3]
	end
	local motion = spec.motion
	if motion then
		part:SetAttribute(Constants.OBBY_MOTION, motion.kind)
		part:SetAttribute(Constants.OBBY_BASE, part.CFrame)
		part:SetAttribute(Constants.OBBY_PHASE, motion.phase or 0)
		if motion.period then
			part:SetAttribute(Constants.OBBY_PERIOD, motion.period)
		end
		if motion.kind == "slide" then
			part:SetAttribute(Constants.OBBY_AXIS, localVec(frameCf, motion.axis))
			part:SetAttribute(Constants.OBBY_AMP, motion.amp or 0)
		elseif motion.kind == "melt" then
			part:SetAttribute(Constants.OBBY_DELAY, motion.delay or 0.7)
			part:SetAttribute(Constants.OBBY_AWAY, motion.away or 2.5)
		elseif motion.kind == "flip" then
			part:SetAttribute(Constants.OBBY_DUTY, motion.duty or 0.65)
		elseif motion.kind == "shrink" then
			part:SetAttribute(Constants.OBBY_MIN, motion.min or 0.3)
			part:SetAttribute(Constants.OBBY_SHRINK_AXES, if disc then "yz" else "xz")
		elseif motion.kind == "bounce" or motion.kind == "lift" then
			part:SetAttribute(Constants.OBBY_POWER, motion.power or 50)
		elseif motion.kind == "swing" or motion.kind == "rock" then
			part:SetAttribute(Constants.OBBY_AMP, motion.amp or 0)
			part:SetAttribute(Constants.OBBY_ARM, motion.arm or 0)
		end
	end
	part.Parent = parent
end

-- Replaces workspace.Obby.Course with `course`.
function ObbyView.build(course: ObbyCourse.Course)
	local root = getFolder()
	local old = root:FindFirstChild(Constants.OBBY_COURSE)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = Constants.OBBY_COURSE
	model:SetAttribute("Slot", course.slot)
	local frameCf = frameCFrame(ObbyView.place().frame)
	for _, spec in course.parts do
		makePart(spec, frameCf, model)
	end
	model.Parent = root
end

local function signLabel(parent: Instance, name: string, text: string, y: number, h: number, maxSize: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.05, y)
	label.Size = UDim2.fromScale(0.9, h)
	label.Font = PORTAL.font
	label.Text = text
	label.TextColor3 = PORTAL.ink
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = PORTAL.stroke
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = parent
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
	cylinder("Floor", 0.5, r, 0.3, PORTAL.column, 0.4).Material = Enum.Material.SmoothPlastic
	local column = cylinder(
		"Column",
		PORTAL.columnHeight,
		r - 0.5,
		PORTAL.columnHeight / 2,
		PORTAL.column,
		PORTAL.columnTransparency
	)
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	local light = Instance.new("PointLight")
	light.Color = PORTAL.column
	light.Range = 16
	light.Brightness = 2
	light.Parent = column

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
	for _, side in { -1, 1 } do
		local post = Instance.new("Part")
		post.Name = "Post"
		post.Anchored = true
		post.Size = Vector3.new(0.6, PORTAL.signLift + PORTAL.signSize.Y, 0.6)
		post.CFrame = sign.CFrame * CFrame.new(side * (PORTAL.signSize.X / 2 - 0.6), -PORTAL.signLift / 2, 0.4)
		post.Color = PORTAL.sign
		post.Parent = model
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PORTAL.pixelsPerStud
	gui.MaxDistance = PORTAL.maxDistance
	gui.LightInfluence = 0
	gui.Adornee = sign
	signLabel(gui, "Title", "GOO GAUNTLET", 0.06, 0.32, 80)
	signLabel(gui, Constants.OBBY_SIGN_STATUS, "Step in: x1.5 income!", 0.42, 0.24, 50)
	signLabel(gui, Constants.OBBY_SIGN_COURSE, "A new course every 10 min", 0.7, 0.2, 40)
	gui.Parent = sign
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
