--!strict
--[[
	ObbyParts (shared visuals, contract/obby.md §5)

	Builds the obby course as Instances from ObbyCourse data: one Part per ObbyCourse.Part (a TrussPart for
	ladders) and the Goo Ring's decor behind the start pad. The client builds it (visuals/client/ObbyCourseView)
	from the slot the server publishes, like the backdrop, so the server's world and its part budget never carry the
	course. Moving parts get their rest CFrame and motion as attributes (the OBBY_* names in Constants);
	visuals/client/ObbyFx plays them. Belts get a surface velocity, ice no friction. Also holds the obby's sign
	colours and label helper, which server/ObbyView's portal shares.

	The Goo Ring sign is a SurfaceGui (guides/roblox-world-labels.md): its 1-stud line reads from about 20 studs on a
	phone; the runner appears about 7 studs from it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ObbyCourse = require(Shared:WaitForChild("ObbyCourse"))

local ObbyParts = {}

-- Sign and ring colours, shared with the portal (server/ObbyView).
ObbyParts.COLORS = table.freeze({
	ring = Color3.fromRGB(150, 230, 70),
	floor = Color3.fromRGB(170, 255, 140),
	sign = Color3.fromRGB(46, 38, 70),
	ink = Color3.fromRGB(255, 255, 255),
	stroke = Color3.fromRGB(30, 22, 48),
})
ObbyParts.FONT = Enum.Font.FredokaOne
ObbyParts.PIXELS_PER_STUD = 50

-- Look per part kind: colour (or three tones), material, transparency. No Neon: it blooms into blobs against the
-- obby sky, so even the "glow" tiles are saturated SmoothPlastic.
type Look = { colors: { Color3 }, material: Enum.Material, transparency: number? }
local LOOKS: { [string]: Look } = {
	start = { colors = { Color3.fromRGB(120, 226, 170) }, material = Enum.Material.SmoothPlastic },
	pad = { colors = { Color3.fromRGB(214, 226, 238) }, material = Enum.Material.SmoothPlastic },
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
	bar = { colors = { Color3.fromRGB(235, 70, 120) }, material = Enum.Material.SmoothPlastic },
	trampoline = {
		colors = { Color3.fromRGB(80, 170, 255), Color3.fromRGB(255, 110, 200) },
		material = Enum.Material.SmoothPlastic,
	},
	cannon = { colors = { Color3.fromRGB(255, 140, 40) }, material = Enum.Material.SmoothPlastic },
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
		colors = { Color3.fromRGB(205, 230, 250) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.85,
	},
	plank = {
		colors = { Color3.fromRGB(200, 150, 90), Color3.fromRGB(180, 130, 75) },
		material = Enum.Material.Wood,
	},
	gate = { colors = { Color3.fromRGB(235, 70, 120) }, material = Enum.Material.SmoothPlastic, transparency = 0.2 },
	-- Belts: orange pushes right, blue pushes left.
	belt = {
		colors = { Color3.fromRGB(255, 150, 50), Color3.fromRGB(70, 170, 255) },
		material = Enum.Material.SmoothPlastic,
	},
	glow = {
		colors = { Color3.fromRGB(255, 200, 50), Color3.fromRGB(80, 215, 120), Color3.fromRGB(70, 170, 240) },
		material = Enum.Material.SmoothPlastic,
	},
	log = {
		colors = { Color3.fromRGB(160, 105, 60), Color3.fromRGB(140, 90, 50) },
		material = Enum.Material.Wood,
	},
	wave = {
		colors = { Color3.fromRGB(110, 220, 90) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.15,
	},
	puncher = { colors = { Color3.fromRGB(255, 90, 140) }, material = Enum.Material.SmoothPlastic },
	gust = {
		colors = { Color3.fromRGB(235, 250, 255) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.96,
	},
}

-- The Goo Ring behind the start pad (`Course.home`): a ring like the portal's and a sign facing the start pad.
-- Its 1-stud text line reads from about 20 studs on a phone; the runner appears about 7 studs from it.
local HOME = table.freeze({
	ringWidth = 0.6, -- studs the ring sticks out past the ring radius
	signSize = Vector3.new(6, 2.2, 0.3), -- studs
	signLift = 2.6, -- studs from the pad's top to the sign's bottom edge
	signInset = 0.6, -- studs in from the pad's back edge
	postWidth = 0.4,
	maxDistance = 60,
	text = "Back to base",
})

local ICE = PhysicalProperties.new(0.9, 0, 0.5, 100, 1)

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
		elseif spec.shape == "log" then
			-- A cylinder's axis is its X, which already runs along the course.
			(part :: Part).Shape = Enum.PartType.Cylinder
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
		if motion.kind == "slide" or motion.kind == "punch" then
			part:SetAttribute(Constants.OBBY_AXIS, localVec(frameCf, motion.axis))
			part:SetAttribute(Constants.OBBY_AMP, motion.amp or 0)
		elseif motion.kind == "gust" then
			-- The axis points the way it blows; the power is the speed.
			local power = motion.power or 0
			local sign = if power < 0 then -1 else 1
			part:SetAttribute(Constants.OBBY_AXIS, localVec(frameCf, motion.axis) * sign)
			part:SetAttribute(Constants.OBBY_POWER, math.abs(power))
			part:SetAttribute(Constants.OBBY_DUTY, motion.duty or 0.5)
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

function ObbyParts.signLabel(parent: Instance, name: string, text: string, y: number, h: number, maxSize: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.05, y)
	label.Size = UDim2.fromScale(0.9, h)
	label.Font = ObbyParts.FONT
	label.Text = text
	label.TextColor3 = ObbyParts.COLORS.ink
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = ObbyParts.COLORS.stroke
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = parent
end

local function decor(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- The Goo Ring back to the yard and its sign, on the pad behind the start pad.
local function buildHome(course: ObbyCourse.Course, frameCf: CFrame, parent: Instance)
	local ring = course.home
	local centre = frameCf * CFrame.new(ring.pos[1], ring.pos[2], ring.pos[3])
	local function disc(name: string, height: number, radius: number, color: Color3, transparency: number): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(height, radius * 2, radius * 2)
		part.CFrame = centre * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		part.Color = color
		part.Transparency = transparency
		part.Material = Enum.Material.Neon
		decor(part)
		part.Parent = parent
		return part
	end
	disc("HomeRing", 0.2, ring.radius + HOME.ringWidth, ObbyParts.COLORS.ring, 0)
	disc("HomeFloor", 0.3, ring.radius, ObbyParts.COLORS.floor, 0.4).Material = Enum.Material.SmoothPlastic

	-- The sign stands at the pad's back edge and faces along the course, towards the start pad.
	local back = ring.pos[1] - ObbyCourse.HOME_LENGTH / 2 + HOME.signInset
	local size = HOME.signSize
	local signCf = frameCf * CFrame.new(back, ring.pos[2] + HOME.signLift + size.Y / 2, ring.pos[3])
	local signPos = signCf.Position
	local sign = Instance.new("Part")
	sign.Name = "HomeSign"
	sign.Size = size
	sign.CFrame = CFrame.lookAt(signPos, signPos + frameCf.XVector)
	sign.Color = ObbyParts.COLORS.sign
	sign.Material = Enum.Material.SmoothPlastic
	decor(sign)
	sign.Parent = parent
	local post = Instance.new("Part")
	post.Name = "HomePost"
	post.Size = Vector3.new(HOME.postWidth, HOME.signLift, HOME.postWidth)
	post.CFrame = sign.CFrame * CFrame.new(0, -(size.Y + HOME.signLift) / 2, 0)
	post.Color = ObbyParts.COLORS.sign
	post.Material = Enum.Material.SmoothPlastic
	decor(post)
	post.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Name = "HomeSignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ObbyParts.PIXELS_PER_STUD
	gui.MaxDistance = HOME.maxDistance
	gui.LightInfluence = 0
	gui.Adornee = sign
	ObbyParts.signLabel(gui, "Title", HOME.text, 0.22, 0.56, ObbyParts.PIXELS_PER_STUD)
	gui.Parent = sign
end

-- The course as a Model named Constants.OBBY_COURSE (attribute Slot), in the frame given; not parented.
function ObbyParts.build(course: ObbyCourse.Course, frame: ObbyCourse.Frame): Model
	local model = Instance.new("Model")
	model.Name = Constants.OBBY_COURSE
	model:SetAttribute("Slot", course.slot)
	local frameCf = frameCFrame(frame)
	for _, spec in course.parts do
		makePart(spec, frameCf, model)
	end
	buildHome(course, frameCf, model)
	return model
end

return ObbyParts
