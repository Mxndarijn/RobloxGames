--!strict
--[[
	HomePlotMarker (VisualsClient module)

	Marks the local player's own plot (the Plot whose OwnerUserId is the local
	UserId) so it is easy to find from anywhere, for this player only:
	  * Beacon: a tall green light pillar from the plot centre with sparkles
	    rising along it; seen from the hub and across the map.
	  * Rim: a glowing green ring along the round plot floor's edge, pulsing.
	  * Tag: an always-on-top "Your plot" label (canvas GooWorldSigns): a mint
	    jelly badge with your avatar's headshot (a house drawn in Ink until it
	    loads, or if it can't), the words in outlined Fredoka.
	  * Arrow: the badge with the house on the screen edge pointing home while
	    the plot is off screen.
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
local GooPalette = require(Shared:WaitForChild("GooPalette"))
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Look = require(Visuals:WaitForChild("HomePlotMarker"))
local WorldLayout = require(Visuals:WaitForChild("WorldLayout"))

local HomePlotMarker = {}

HomePlotMarker.FOLDER = "HomePlotMarker"
HomePlotMarker.GUI = "HomePlotArrow"
HomePlotMarker.POLL = 1 -- seconds between own-plot checks

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local GREEN = rgb(Look.COLOR)
local INK = rgb(GooPalette.Ink)
local WHITE = rgb(GooPalette.White)

-- The "Your plot" label in px: the badge, the words under it, and the Ink outlines.
HomePlotMarker.TAG = table.freeze({
	w = 170,
	badge = 62,
	gap = 4,
	text = 32,
	textSize = 26,
	stroke = 3,
	textStroke = 2.5,
	avatarInset = 0.04,
})
-- The edge arrow: the badge and the "Your plot" words under it, in px.
HomePlotMarker.ARROW = table.freeze({ badge = 58, gap = 6, textW = 110, textH = 20, textSize = 18 })
local CORE_ALPHA = 0.35 -- beacon core transparency at full fade
local HALO_ALPHA = 0.82

type Built = {
	plot: Model,
	folder: Folder,
	centre: Vector3, -- plot floor centre
	floor: CFrame, -- plot floor centre and facing
	radius: number, -- the round plot floor's radius, studs
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

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- The roof bars: side and centre x.
local ROOF = table.freeze({ table.freeze({ "L", 0.335 }), table.freeze({ "R", 0.665 }) }) :: { { any } }

-- A house in Ink lines (the canvas's home icon): a roof of two bars, the walls as an outline and a door. Fills
-- `parent`, so it scales with the badge.
local function drawHouse(parent: Instance, line: number)
	for _, roof in ROOF do
		local side, x = roof[1] :: string, roof[2] :: number
		make("Frame", {
			Name = `Roof{side}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = INK,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(x, 0.37),
			Size = UDim2.new(0.44, 0, 0, line),
			Rotation = if side == "L" then -38 else 38,
		}, parent)
	end
	local walls = make("Frame", {
		Name = "Walls",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.29, 0.45),
		Size = UDim2.fromScale(0.42, 0.33),
	}, parent)
	make("UIStroke", { Color = INK, Thickness = line, LineJoinMode = Enum.LineJoinMode.Round }, walls)
	make("Frame", {
		Name = "Door",
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.44, 0.6),
		Size = UDim2.fromScale(0.12, 0.18),
	}, parent)
end

-- The mint jelly badge with the house: a circle with an Ink ring, a top-light gradient and a glint.
local function homeBadge(parent: Instance, size: number): Frame
	local circle = make("Frame", {
		Name = "Badge",
		BackgroundColor3 = WHITE,
		Size = UDim2.fromOffset(size, size),
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, circle)
	make("UIStroke", { Color = INK, Thickness = HomePlotMarker.TAG.stroke }, circle)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(GooPalette.MintHi)),
			ColorSequenceKeypoint.new(0.45, rgb(GooPalette.Mint)),
			ColorSequenceKeypoint.new(1, rgb(GooPalette.MintLo)),
		}),
	}, circle)
	local shine = make("Frame", {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.16, 0.14),
		Size = UDim2.fromScale(0.24, 0.1),
		Rotation = -24,
	}, circle)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, shine)
	local house = make("Frame", { Name = "House", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, circle)
	drawHouse(house, math.max(2, math.round(size / 20)))
	return circle
end

-- Outlined white Fredoka (every world label's text).
local function outlined(parent: Instance, name: string, text: string, size: number): TextLabel
	local label = make("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = text,
		TextSize = size,
		TextColor3 = WHITE,
	}, parent)
	make(
		"UIStroke",
		{ Color = INK, Thickness = HomePlotMarker.TAG.textStroke, LineJoinMode = Enum.LineJoinMode.Round },
		label
	)
	return label
end

-- Parented to its anchor part: a BillboardGui under a Folder does not draw.
local function buildTag(adornee: BasePart): BillboardGui
	local T = HomePlotMarker.TAG
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Adornee = adornee
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.MaxDistance = 2000
	tag.Size = UDim2.fromOffset(T.w, T.badge + T.gap + T.text)
	tag.StudsOffsetWorldSpace = Vector3.new(0, Look.TAG_HEIGHT, 0)
	tag.ResetOnSpawn = false

	local icon = homeBadge(tag, T.badge)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, T.stroke)
	local title = outlined(tag, "Title", "Your plot", T.textSize)
	title.Position = UDim2.fromOffset(0, T.badge + T.gap)
	title.Size = UDim2.new(1, 0, 0, T.text)

	-- Your avatar's headshot inside the mint ring, in place of the house once it loads (the house stays if it
	-- cannot load).
	local face = make("ImageLabel", {
		Name = "Avatar",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(T.avatarInset, T.avatarInset),
		Size = UDim2.fromScale(1 - T.avatarInset * 2, 1 - T.avatarInset * 2),
		Visible = false,
		ZIndex = 2,
	}, icon)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, face)
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
			face.Visible = true
			local house = icon:FindFirstChild("House") :: Frame?
			if house then
				house.Visible = false
			end
		end
	end)

	tag.Parent = adornee
	return tag
end

-- The ring of floor strips along the round plot floor's edge, on top of `base`.
local function buildRim(parent: Instance, base: BasePart): { BasePart }
	local top = base.Size.Y / 2 + 0.06
	local parts: { BasePart } = {}
	for k, seg in Look.rim(WorldLayout.PLOT_FLOOR_RADIUS) do
		local at = base.CFrame * CFrame.Angles(0, seg.angle, 0) * CFrame.new(0, top, -seg.mid)
		local part = neon(`Rim_{k}`, Vector3.new(seg.length, 0.1, Look.RIM_WIDTH), at)
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
		radius = WorldLayout.PLOT_FLOOR_RADIUS,
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

	local A = HomePlotMarker.ARROW
	local frame = homeBadge(gui, A.badge)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	local label = outlined(frame, "Label", "Your plot", A.textSize)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, A.gap)
	label.Size = UDim2.fromOffset(A.textW, A.textH)

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
	tipStroke.Thickness = HomePlotMarker.TAG.stroke
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
	local fade = Look.fade(Look.pastEdge(rel.X, rel.Z, b.radius))
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
