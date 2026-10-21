--!strict
--[[
	HomePlotMarker (VisualsClient module)

	Marks the local player's own plot (the Plot whose OwnerUserId is the local
	UserId) so it is easy to find from anywhere, for this player only:
	  * Beacon: a tall green light pillar from the plot centre with sparkles
	    rising along it; seen from the hub and across the map.
	  * Rim: glowing green strips along the plot floor's edge, pulsing.
	  * Tag: an always-on-top "YOUR PLOT" billboard with the avatar headshot.
	  * Arrow: a 🏠 badge on the screen edge pointing home while the plot is
	    off screen.
	Beacon, tag and arrow fade out while your character stands on the plot. Numbers and math
	live in Visuals.HomePlotMarker; this file only builds Instances.
	Reads attributes only; never fires remotes. Local changes only.

	HomePlotMarker.start() -> cleanup
	HomePlotMarker.step(now, camera)   -- from VisualsClient's RenderStepped loop
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local EdgeArrow = require(Shared:WaitForChild("EdgeArrow"))
local Look = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("HomePlotMarker"))

local HomePlotMarker = {}

HomePlotMarker.FOLDER = "HomePlotMarker"
HomePlotMarker.GUI = "HomePlotArrow"
HomePlotMarker.POLL = 1 -- seconds between own-plot checks

local GREEN = Color3.fromRGB(Look.COLOR[1], Look.COLOR[2], Look.COLOR[3])
local INK = Color3.fromRGB(30, 18, 51) -- Widgets.Theme.Ink
local WHITE = Color3.fromRGB(255, 255, 255)
local CORE_ALPHA = 0.35 -- beacon core transparency at full fade
local HALO_ALPHA = 0.82

type Built = {
	plot: Model,
	folder: Folder,
	centre: Vector3, -- plot floor centre
	floor: CFrame, -- plot floor centre and facing
	half: Vector2, -- half the floor size (X, Z), studs
	core: BasePart,
	halo: BasePart,
	sparkles: ParticleEmitter,
	rim: { BasePart },
	tag: BillboardGui,
}

local built: Built? = nil
local arrowGui: ScreenGui? = nil
local badge: Frame? = nil
local pointer: TextLabel? = nil

local function neon(name: string, size: Vector3, cframe: CFrame, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = GREEN
	part.Size = size
	part.CFrame = cframe
	if shape then
		part.Shape = shape
	end
	return part
end

local function ownPlot(): Model?
	local player = Players.LocalPlayer
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	if not (player and plots) then
		return nil
	end
	local list = {}
	local byIndex: { [number]: Model } = {}
	for _, plot in plots:GetChildren() do
		local index = plot:GetAttribute(Constants.PLOT_INDEX_ATTRIBUTE)
		if plot:IsA("Model") and type(index) == "number" then
			table.insert(list, { index = index, owner = plot:GetAttribute("OwnerUserId") })
			byIndex[index] = plot
		end
	end
	local index = Look.ownPlot(list, player.UserId)
	return if index then byIndex[index] else nil
end

-- Parented to its anchor part: a BillboardGui under a Folder does not draw.
local function buildTag(adornee: BasePart): BillboardGui
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Adornee = adornee
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.MaxDistance = 2000
	tag.Size = UDim2.fromOffset(250, 64)
	tag.StudsOffsetWorldSpace = Vector3.new(0, Look.TAG_HEIGHT, 0)
	tag.ResetOnSpawn = false

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = GREEN
	pill.Parent = tag
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 4
	stroke.Parent = pill

	local face = Instance.new("ImageLabel")
	face.Name = "Avatar"
	face.Size = UDim2.fromOffset(52, 52)
	face.Position = UDim2.fromOffset(6, 6)
	face.BackgroundColor3 = WHITE
	face.Parent = pill
	local faceCorner = Instance.new("UICorner")
	faceCorner.CornerRadius = UDim.new(0.5, 0)
	faceCorner.Parent = face
	local faceStroke = Instance.new("UIStroke")
	faceStroke.Color = INK
	faceStroke.Thickness = 3
	faceStroke.Parent = face

	local text = Instance.new("TextLabel")
	text.Name = "Title"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(64, 0)
	text.Size = UDim2.new(1, -72, 1, 0)
	text.Font = Enum.Font.FredokaOne
	text.Text = "YOUR PLOT"
	text.TextScaled = true
	text.TextColor3 = WHITE
	text.Parent = pill
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = INK
	textStroke.Thickness = 2.5
	textStroke.Parent = text
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.Parent = text

	local player = Players.LocalPlayer
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if ok and face.Parent then
			face.Image = image
		end
	end)

	tag.Parent = adornee
	return tag
end

-- Four floor strips along the plot edge, on top of `base`.
local function buildRim(parent: Instance, base: BasePart): { BasePart }
	local size = base.Size
	local w = Look.RIM_WIDTH
	local top = size.Y / 2 + 0.06
	local hx, hz = size.X / 2 - w / 2, size.Z / 2 - w / 2
	local strips = {
		{ "RimFront", Vector3.new(size.X, 0.1, w), Vector3.new(0, top, -hz) },
		{ "RimBack", Vector3.new(size.X, 0.1, w), Vector3.new(0, top, hz) },
		{ "RimLeft", Vector3.new(w, 0.1, size.Z - 2 * w), Vector3.new(-hx, top, 0) },
		{ "RimRight", Vector3.new(w, 0.1, size.Z - 2 * w), Vector3.new(hx, top, 0) },
	}
	local parts = {}
	for _, s in strips do
		local part = neon(s[1], s[2], base.CFrame * CFrame.new(s[3]))
		part.Parent = parent
		table.insert(parts, part)
	end
	return parts
end

local function build(plot: Model): Built?
	local base = plot:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = HomePlotMarker.FOLDER
	folder:SetAttribute("PlotIndex", plot:GetAttribute(Constants.PLOT_INDEX_ATTRIBUTE))

	local floor = base.Position + Vector3.new(0, base.Size.Y / 2, 0)
	local h = Look.BEACON_HEIGHT
	local upright = CFrame.new(floor + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local core =
		neon("BeaconCore", Vector3.new(h, Look.BEACON_WIDTH, Look.BEACON_WIDTH), upright, Enum.PartType.Cylinder)
	core.Transparency = CORE_ALPHA
	core.Parent = folder
	local halo = neon("BeaconHalo", Vector3.new(h, Look.HALO_WIDTH, Look.HALO_WIDTH), upright, Enum.PartType.Cylinder)
	halo.Material = Enum.Material.ForceField
	halo.Transparency = HALO_ALPHA
	halo.Parent = folder

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(GREEN, WHITE)
	sparkles.LightEmission = 1
	sparkles.Rate = 14
	sparkles.Lifetime = NumberRange.new(4, 6)
	sparkles.Speed = NumberRange.new(14, 22)
	sparkles.SpreadAngle = Vector2.new(6, 6)
	sparkles.EmissionDirection = Enum.NormalId.Right -- the cylinder's X axis points up
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.2),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	sparkles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkles.Parent = halo

	local rim = buildRim(folder, base)
	local anchor = neon("TagAnchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(floor))
	anchor.Transparency = 1
	anchor.Parent = folder
	local tag = buildTag(anchor)

	folder.Parent = workspace
	return {
		plot = plot,
		folder = folder,
		centre = floor,
		floor = base.CFrame,
		half = Vector2.new(base.Size.X / 2, base.Size.Z / 2),
		core = core,
		halo = halo,
		sparkles = sparkles,
		rim = rim,
		tag = tag,
	}
end

local function buildArrow(): ScreenGui?
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = HomePlotMarker.GUI
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false

	local frame = Instance.new("Frame")
	frame.Name = "Badge"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(58, 58)
	frame.BackgroundColor3 = GREEN
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 4
	stroke.Parent = frame
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Font = Enum.Font.FredokaOne
	icon.Text = "🏠"
	icon.TextSize = 30
	icon.Parent = frame
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, 4)
	label.Size = UDim2.fromOffset(110, 20)
	label.Font = Enum.Font.FredokaOne
	label.Text = "Your plot"
	label.TextSize = 18
	label.TextColor3 = WHITE
	label.Parent = frame
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = INK
	labelStroke.Thickness = 2.5
	labelStroke.Parent = label

	local tip = Instance.new("TextLabel")
	tip.Name = "Pointer"
	tip.BackgroundTransparency = 1
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Size = UDim2.fromOffset(30, 30)
	tip.Font = Enum.Font.FredokaOne
	tip.Text = "▶"
	tip.TextSize = 30
	tip.TextColor3 = GREEN
	tip.Parent = gui
	local tipStroke = Instance.new("UIStroke")
	tipStroke.Color = INK
	tipStroke.Thickness = 3
	tipStroke.Parent = tip

	gui.Parent = playerGui
	badge, pointer = frame, tip
	return gui
end

local function clear()
	if built then
		built.folder:Destroy()
		built = nil
	end
end

local function refresh()
	local plot = ownPlot()
	if built and built.plot == plot and built.folder.Parent then
		return
	end
	clear()
	if plot then
		built = build(plot)
	end
	if not arrowGui or not arrowGui.Parent then
		arrowGui = buildArrow()
	end
end

local function stepArrow(b: Built, camera: Camera, fade: number)
	local gui, frame, tip = arrowGui, badge, pointer
	if not (gui and frame and tip) then
		return
	end
	if fade <= 0 then
		gui.Enabled = false
		return
	end
	-- Viewport px (IgnoreGuiInset): the camera looks at the viewport centre.
	local view = camera.ViewportSize
	local inset = Look.EDGE_INSETS
	local rect = { left = inset.left, top = inset.top, right = view.X - inset.right, bottom = view.Y - inset.bottom }
	local target = b.centre + Vector3.new(0, Look.TAG_HEIGHT * 0.5, 0)
	local rel = camera.CFrame:PointToObjectSpace(target)
	local screen = camera:WorldToViewportPoint(target)
	if rel.Z < 0 and EdgeArrow.inside({ x = screen.X, y = screen.Y }, rect) then
		gui.Enabled = false -- on screen: the beacon and tag show the way
		return
	end
	local dx, dy = EdgeArrow.direction({ x = rel.X, y = rel.Y, z = rel.Z })
	local arrow = EdgeArrow.place({ x = view.X / 2, y = view.Y / 2 }, dx, dy, rect)
	gui.Enabled = true
	frame.Position = UDim2.fromOffset(arrow.x, arrow.y)
	tip.Position = UDim2.fromOffset(arrow.x + dx * 44, arrow.y + dy * 44)
	tip.Rotation = arrow.angle
end

function HomePlotMarker.step(now: number, camera: Camera)
	local b = built
	if not b then
		if arrowGui then
			arrowGui.Enabled = false
		end
		return
	end
	-- Where the character stands, not the camera: the camera trails behind and
	-- would count as off the plot near its edge.
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local here = if root and root:IsA("BasePart") then root.Position else camera.CFrame.Position
	local rel = b.floor:PointToObjectSpace(here)
	local fade = Look.fade(Look.pastEdge(rel.X, rel.Z, b.half.X, b.half.Y))
	local pulse = Look.pulse(now)

	b.core.Transparency = 1 - (1 - CORE_ALPHA) * fade
	b.halo.Transparency = 1 - (1 - HALO_ALPHA) * fade
	b.sparkles.Enabled = fade > 0
	for _, strip in b.rim do
		strip.Transparency = 0.15 + 0.45 * pulse
	end
	b.tag.Enabled = fade > 0
	b.tag.StudsOffsetWorldSpace = Vector3.new(0, Look.TAG_HEIGHT + math.sin(now * 2) * 0.8, 0)
	stepArrow(b, camera, fade)
end

function HomePlotMarker.start(): () -> ()
	local running = true
	task.spawn(function()
		while running do
			local ok, err = pcall(refresh)
			if not ok then
				warn(`[VisualsClient] home plot marker: {err}`)
			end
			task.wait(HomePlotMarker.POLL)
		end
	end)
	return function()
		running = false
		clear()
		if arrowGui then
			arrowGui:Destroy()
			arrowGui = nil
		end
	end
end

return HomePlotMarker
