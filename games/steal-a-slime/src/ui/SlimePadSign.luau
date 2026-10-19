--!strict
--[[
	SlimePadSign (contract/slime-labels.md)

	The label of a slime resting on a pad: a small cream plaque on the front
	of the pad crate (the side facing the plot entrance), with a band in the
	rarity colour, the species name, its income and a growth bar. Built and
	filled by SlimeInfoCard, which owns the lifecycle; this module only makes
	the part and draws a SlimeLabel.View on it.

	Client only, nothing replicates. The plaque never collides, is never
	queried or touched and casts no shadow, so it can't block a prompt or a
	walk-in.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local SlimeLabel = require(Shared:WaitForChild("SlimeLabel"))
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local SlimePadSign = {}

SlimePadSign.NAME = "SlimePadSign"

-- Plaque size and where it sits on the pad crate (studs, pad-local: -Z is the plot entrance side).
SlimePadSign.SIZE = table.freeze({
	width = 4.6,
	height = 1.5,
	thickness = 0.14,
	front = 3.8, -- studs from the pad centre to the plaque's back face (the crate side)
	centreY = 1.25, -- studs above the pad's bottom
	pixelsPerStud = 80,
	maxDistance = 90,
	corner = 14,
	stroke = 5,
	pad = 8, -- px inner padding
})

-- Plaque colours: a cream board with a wood edge, dark ink for text.
SlimePadSign.COLORS = table.freeze({
	board = Color3.fromRGB(255, 243, 214),
	edge = Color3.fromRGB(92, 58, 30),
	wood = Color3.fromRGB(150, 100, 60),
	ink = Color3.fromRGB(59, 36, 20),
	income = Color3.fromRGB(38, 128, 44),
	track = Color3.fromRGB(232, 214, 176),
	fill = Theme.Accent,
	bandInk = Color3.fromRGB(255, 255, 255),
	bandStroke = Color3.fromRGB(40, 24, 12),
})

-- Rarity colours at or above this brightness (0..255) get dark band text.
SlimePadSign.LIGHT_BAND = 150

-- Rows of the board, as fractions of its inner height.
SlimePadSign.LAYOUT = table.freeze({
	band = { y = 0, h = 0.34 },
	main = { y = 0.38, h = 0.32 },
	growth = { y = 0.76, h = 0.22 },
	nameWidth = 0.58, -- name on the left, income on the right of the main row
	barWidth = 0.76, -- growth bar, the percent to its right
})

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- Band text on a rarity colour: dark ink (the colour, deepened) on light bands, white edged in dark on deep ones.
function SlimePadSign.bandInk(color: { number }): (Color3, number)
	local luma = 0.299 * color[1] + 0.587 * color[2] + 0.114 * color[3]
	if luma >= SlimePadSign.LIGHT_BAND then
		return rgb(color):Lerp(Color3.new(0, 0, 0), 0.72), 1
	end
	return SlimePadSign.COLORS.bandInk, 0
end

local function text(name: string, props: { [string]: any }, parent: Instance): TextLabel
	local label = create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextScaled = true,
		Parent = parent,
	})
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

-- The pad part a slime rests on: the child of its plot with PadIndex `pad` (Pad_<pad> as a fallback), or nil.
function SlimePadSign.findPad(model: Instance, pad: number): BasePart?
	local folder = model.Parent
	local plot = folder and folder.Parent
	if not plot then
		return nil
	end
	for _, child in plot:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute(Constants.PAD_INDEX_ATTRIBUTE) == pad then
			return child
		end
	end
	local named = plot:FindFirstChild(`Pad_{pad}`)
	return if named and named:IsA("BasePart") then named else nil
end

-- Where the plaque sits for a pad part: on the crate's entrance side, facing out.
function SlimePadSign.cframe(pad: BasePart): CFrame
	local s = SlimePadSign.SIZE
	return pad.CFrame * CFrame.new(0, s.centreY - pad.Size.Y / 2, -(s.front + s.thickness / 2))
end

-- An empty plaque (call `render` to fill it, `place` to put it on a pad).
function SlimePadSign.build(): Part
	local s, c, l = SlimePadSign.SIZE, SlimePadSign.COLORS, SlimePadSign.LAYOUT
	local part = create("Part", {
		Name = SlimePadSign.NAME,
		Archivable = false,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.WoodPlanks,
		Color = c.wood,
		Size = Vector3.new(s.width, s.height, s.thickness),
	}) :: Part
	local gui = create("SurfaceGui", {
		Name = "Face",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = s.pixelsPerStud,
		LightInfluence = 0,
		MaxDistance = s.maxDistance,
		Parent = part,
	})
	local board = create("Frame", {
		Name = "Board",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = c.board,
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		Widgets.corner(s.corner),
		create("UIStroke", {
			Name = "Stroke",
			Thickness = s.stroke,
			Color = c.edge,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Widgets.padding(s.pad),
	})
	local band = create("Frame", {
		Name = "Band",
		Position = UDim2.fromScale(0, l.band.y),
		Size = UDim2.fromScale(1, l.band.h),
		BorderSizePixel = 0,
		Parent = board,
	}, { Widgets.corner(s.corner - s.pad) })
	local rarity = text("Rarity", {
		Position = UDim2.fromOffset(s.pad, 0),
		Size = UDim2.new(1, -2 * s.pad, 1, 0),
		TextColor3 = c.bandInk,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, band)
	create("UIStroke", {
		Name = "Stroke",
		Thickness = 2.5,
		Color = c.bandStroke,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = rarity,
	})
	text("Title", {
		Position = UDim2.fromScale(0, l.main.y),
		Size = UDim2.fromScale(l.nameWidth, l.main.h),
		TextColor3 = c.ink,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, board)
	text("Income", {
		Position = UDim2.fromScale(l.nameWidth, l.main.y),
		Size = UDim2.fromScale(1 - l.nameWidth, l.main.h),
		Font = Enum.Font.GothamBold,
		TextColor3 = c.income,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, board)
	local track = create("Frame", {
		Name = "Track",
		Position = UDim2.fromScale(0, l.growth.y),
		Size = UDim2.fromScale(l.barWidth, l.growth.h),
		BackgroundColor3 = c.track,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = board,
	}, { Widgets.corner(100) })
	create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = c.fill,
		BorderSizePixel = 0,
		Parent = track,
	}, { Widgets.corner(100) })
	text("Growth", {
		Position = UDim2.fromScale(l.barWidth, l.growth.y - 0.03),
		Size = UDim2.fromScale(1 - l.barWidth, l.growth.h + 0.06),
		Font = Enum.Font.GothamBold,
		TextColor3 = c.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, board)
	return part
end

-- Draws `view` on a built plaque.
function SlimePadSign.render(part: Part, view: SlimeLabel.View)
	local board = (part:FindFirstChild("Face") :: SurfaceGui):FindFirstChild("Board") :: Frame
	local band = board:FindFirstChild("Band") :: Frame
	local rarity = band:FindFirstChild("Rarity") :: TextLabel
	local title = board:FindFirstChild("Title") :: TextLabel
	local income = board:FindFirstChild("Income") :: TextLabel
	local growth = board:FindFirstChild("Growth") :: TextLabel
	local fill = (board:FindFirstChild("Track") :: Frame):FindFirstChild("Fill") :: Frame
	band.BackgroundColor3 = rgb(view.rarityColor)
	local ink, strokeHidden = SlimePadSign.bandInk(view.rarityColor)
	local bandStroke = rarity:FindFirstChild("Stroke") :: UIStroke
	rarity.TextColor3 = ink
	bandStroke.Transparency = strokeHidden
	rarity.Text = view.rarity
	title.Text = view.name
	income.Text = view.income
	fill.Size = UDim2.fromScale(math.clamp(view.growth, 0, 100) / 100, 1)
	fill.Visible = view.growth > 0
	growth.Text = `{view.growth}%`
end

-- Puts the plaque on `pad` (in `parent`, a client-only folder).
function SlimePadSign.place(part: Part, pad: BasePart, parent: Instance)
	part.CFrame = SlimePadSign.cframe(pad)
	part.Parent = parent
end

return SlimePadSign
