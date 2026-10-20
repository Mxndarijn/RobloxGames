--!strict
--[[
	SlimePadSign (contract/slime-labels.md)

	The label of a slime resting on a pad: a wooden plank nailed to the front
	of the pad crate (the side facing the plot entrance). The name and income
	are painted on the wood and the growth fills a goo tube; no rarity band
	or rarity word (the slime itself shows its rarity). Built and filled by
	SlimeInfoCard, which owns the lifecycle; this module only makes the part
	and draws a SlimeLabel.View on it.

	Client only, nothing replicates. The plank never collides, is never
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

-- Plank size and where it sits on the pad crate (studs, pad-local: -Z is the plot entrance side).
SlimePadSign.SIZE = table.freeze({
	width = 4.6,
	height = 1.5,
	thickness = 0.14,
	front = 3.8, -- studs from the pad centre to the plank's back face (the crate side)
	centreY = 1.25, -- studs above the pad's bottom
	pixelsPerStud = 80,
	maxDistance = 45, -- studs: the plank is too small to read beyond this
	corner = 6,
	edge = 4, -- px dark rim round the plank
	paintStroke = 2, -- px outline round painted text
})

-- The plank is real wood (the part's WoodPlanks shows through); paint and goo go on top.
SlimePadSign.COLORS = table.freeze({
	wood = Color3.fromRGB(161, 108, 66),
	edge = Color3.fromRGB(74, 46, 24),
	paint = Color3.fromRGB(255, 240, 205),
	paintStroke = Color3.fromRGB(58, 34, 16),
	income = Theme.Gold,
	tube = Color3.fromRGB(70, 44, 24),
})

-- Layout as fractions of the plank (x across, y down).
SlimePadSign.LAYOUT = table.freeze({
	inset = 0.08, -- text and tube start this far in from each end
	main = { y = 0.14, h = 0.38 }, -- name on the left, income on the right
	nameWidth = 0.52,
	growth = { y = 0.64, h = 0.2 }, -- goo tube, the percent to its right
	tubeWidth = 0.64,
})

-- { r, g, b } (Config.RARITIES, SlimeLabel.RAINBOW) as a Color3.
function SlimePadSign.rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end
local rgb = SlimePadSign.rgb

-- SlimeLabel.RAINBOW as an evenly spaced gradient (the tag and the sign share it).
function SlimePadSign.rainbow(): ColorSequence
	local stops = SlimeLabel.RAINBOW
	local points = {}
	for i, c in stops do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#stops - 1), rgb(c)))
	end
	return ColorSequence.new(points)
end

-- The growth tube's goo: a glossy light top over the rarity colour; a rainbow for Secret.
function SlimePadSign.gooGradient(view: SlimeLabel.View): ColorSequence
	if SlimeLabel.isRainbow(view) then
		return SlimePadSign.rainbow()
	end
	local base = rgb(view.rarityColor)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, base:Lerp(Color3.new(1, 1, 1), 0.35)),
		ColorSequenceKeypoint.new(0.4, base),
		ColorSequenceKeypoint.new(1, base:Lerp(Color3.new(0, 0, 0), 0.12)),
	})
end

local function paint(name: string, props: { [string]: any }, parent: Instance): TextLabel
	local label = create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextScaled = true,
		TextColor3 = SlimePadSign.COLORS.paint,
		Parent = parent,
	}, {
		create("UIStroke", {
			Name = "Stroke",
			Thickness = SlimePadSign.SIZE.paintStroke,
			Color = SlimePadSign.COLORS.paintStroke,
			LineJoinMode = Enum.LineJoinMode.Round,
		}),
	})
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

-- A goo piece: a white frame tinted by its gradient, so the rarity shading lands on every piece the same way.
local function goo(name: string, props: { [string]: any }, parent: Instance, corner: number): Frame
	local frame = create("Frame", {
		Name = name,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		Widgets.corner(corner),
		create("UIGradient", { Name = "Goo", Rotation = 90 }),
	})
	for k, v in props do
		(frame :: any)[k] = v
	end
	return frame
end

-- The pad part `pad` among `plot`'s children: PadIndex `pad`, Pad_<pad> as a fallback; nil when it has none.
local function padIn(plot: Instance, pad: number): BasePart?
	for _, child in plot:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute(Constants.PAD_INDEX_ATTRIBUTE) == pad then
			return child
		end
	end
	local named = plot:FindFirstChild(`Pad_{pad}`)
	return if named and named:IsA("BasePart") then named else nil
end

-- The pad part a slime rests on, or nil. The model normally sits in its plot's Slimes folder; one parented to the
-- plot itself is found too.
function SlimePadSign.findPad(model: Instance, pad: number): BasePart?
	local parent = model.Parent
	if not parent then
		return nil
	end
	local grand = parent.Parent
	return (if grand then padIn(grand, pad) else nil) or padIn(parent, pad)
end

-- Where the plank sits for a pad part: on the crate's entrance side, facing out.
function SlimePadSign.cframe(pad: BasePart): CFrame
	local s = SlimePadSign.SIZE
	return pad.CFrame * CFrame.new(0, s.centreY - pad.Size.Y / 2, -(s.front + s.thickness / 2))
end

-- An empty plank (call `render` to fill it, `place` to put it on a pad).
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
		BackgroundTransparency = 1, -- the wood itself
		Parent = gui,
	}, {
		Widgets.corner(s.corner),
		create("UIStroke", {
			Name = "Stroke",
			Thickness = s.edge,
			Color = c.edge,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	paint("Title", {
		Position = UDim2.fromScale(l.inset, l.main.y),
		Size = UDim2.fromScale(l.nameWidth, l.main.h),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, board)
	paint("Income", {
		Position = UDim2.fromScale(l.inset + l.nameWidth, l.main.y),
		Size = UDim2.fromScale(1 - 2 * l.inset - l.nameWidth, l.main.h),
		TextColor3 = c.income,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, board)
	local tube = create("Frame", {
		Name = "Track",
		Position = UDim2.fromScale(l.inset, l.growth.y),
		Size = UDim2.fromScale(l.tubeWidth, l.growth.h),
		BackgroundColor3 = c.tube,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = board,
	}, {
		Widgets.corner(100),
		create("UIStroke", { Thickness = 1.5, Color = c.paintStroke }),
	})
	goo("Fill", { Size = UDim2.fromScale(0, 1) }, tube, 100)
	paint("Growth", {
		Position = UDim2.fromScale(l.inset + l.tubeWidth, l.growth.y - 0.04),
		Size = UDim2.fromScale(1 - 2 * l.inset - l.tubeWidth, l.growth.h + 0.08),
		TextXAlignment = Enum.TextXAlignment.Right,
	}, board)
	return part
end

-- Draws `view` on a built plank.
function SlimePadSign.render(part: Part, view: SlimeLabel.View)
	local board = (part:FindFirstChild("Face") :: SurfaceGui):FindFirstChild("Board") :: Frame
	local title = board:FindFirstChild("Title") :: TextLabel
	local income = board:FindFirstChild("Income") :: TextLabel
	local growth = board:FindFirstChild("Growth") :: TextLabel
	local fill = (board:FindFirstChild("Track") :: Frame):FindFirstChild("Fill") :: Frame
	-- A rainbow runs along the tube; the rarity shading runs top to bottom.
	local shade = fill:FindFirstChild("Goo") :: UIGradient
	shade.Color = SlimePadSign.gooGradient(view)
	shade.Rotation = if SlimeLabel.isRainbow(view) then 0 else 90
	title.Text = view.name
	income.Text = view.income
	fill.Size = UDim2.fromScale(math.clamp(view.growth, 0, 100) / 100, 1)
	fill.Visible = view.growth > 0
	growth.Text = `{view.growth}%`
end

-- Puts the plank on `pad` (in `parent`, a client-only folder).
function SlimePadSign.place(part: Part, pad: BasePart, parent: Instance)
	part.CFrame = SlimePadSign.cframe(pad)
	part.Parent = parent
end

return SlimePadSign
