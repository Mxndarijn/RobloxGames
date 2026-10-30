--!strict
--[[
	SlimePadSign (contract/slime-labels.md)

	The label of a slime resting on a pad (canvas GooWorldLabels "Pad sign"): a
	little wooden sign with an Ink edge on a stake in front of the pad's cork
	stand (the side facing the jar's centre, where players walk), dipped in goo
	of the slime's rarity colour. The goo runs along the top edge with the
	rarity written in it and drips down both ends; the name and income are written in outlined Fredoka on the wood, and
	the growth fills an Ink tube with mint goo. Built and filled by
	SlimeInfoCard, which owns the lifecycle; this module only makes the part
	and draws a SlimeLabel.View on it.

	Client only, nothing replicates. The plank (and its stake) never collides,
	is never queried or touched and casts no shadow, so it can't block a
	prompt or a walk-in.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GooPalette = require(Shared:WaitForChild("GooPalette"))
local SlimeLabel = require(Shared:WaitForChild("SlimeLabel"))
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local SlimePadSign = {}

SlimePadSign.NAME = "SlimePadSign"

-- Plank size and where it stands in front of the cork stand (studs, pad-local: -Z faces the jar's centre).
SlimePadSign.SIZE = table.freeze({
	width = 4.6,
	height = 1.5,
	thickness = 0.14,
	front = 4.15, -- studs from the pad centre to the plank's back face (stake and all clear of the stand's foot, r 3.9)
	centreY = 1.45, -- studs above the pad's bottom (the plank's top stays under the dish rim and the slime)
	stake = 0.22, -- the square stake under the plank, from the floor to its middle
	pixelsPerStud = 80,
	maxDistance = 80, -- studs: far enough to spot the rarity goo across a plot; the text reads from about 40
	corner = 6,
	edge = 4, -- px dark rim round the plank
	paintStroke = 2, -- px outline round painted text
})

-- The plank is real wood (the part's WoodPlanks shows through); the Goo look's Ink and text go on top.
SlimePadSign.COLORS = table.freeze({
	wood = Color3.fromRGB(GooPalette.Wood[1], GooPalette.Wood[2], GooPalette.Wood[3]),
	edge = Theme.Ink,
	paint = Color3.new(1, 1, 1),
	paintStroke = Theme.Ink,
	income = Theme.Good,
	tube = Theme.Ink,
})

-- Layout as fractions of the plank (x across, y down). Text sits between the end drips.
SlimePadSign.LAYOUT = table.freeze({
	band = 0.3, -- goo along the top edge
	inset = 0.11, -- text and tube start this far in from each end, clear of the long drips
	main = { y = 0.42, h = 0.27 }, -- name on the left, income on the right
	nameWidth = 0.5,
	growth = { y = 0.74, h = 0.15 }, -- goo tube, the percent to its right
	tubeWidth = 0.62,
})

-- Goo drips running down both ends of the plank: centre x, width (px) and how far below the band they reach
-- (fraction of the plank). The text keeps LAYOUT.inset clear of them.
SlimePadSign.DRIPS = table.freeze({
	{ x = 0.05, w = 18, len = 0.32 },
	{ x = 0.95, w = 16, len = 0.24 },
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

-- Text in the goo: Ink on bright goo, white edged in Ink on deep goo; a rainbow is bright enough for Ink.
function SlimePadSign.bandInk(view: SlimeLabel.View): (Color3, number)
	if SlimeLabel.isRainbow(view) or Widgets.isBright(rgb(view.rarityColor)) then
		return Theme.Ink, 1
	end
	return SlimePadSign.COLORS.paint, 0
end

-- The goo's shading: a glossy light top over the rarity colour, flat from the middle down so the drips
-- hanging from it match; a rainbow for Secret.
function SlimePadSign.gooGradient(view: SlimeLabel.View): ColorSequence
	if SlimeLabel.isRainbow(view) then
		return SlimePadSign.rainbow()
	end
	local base = rgb(view.rarityColor)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, base:Lerp(Color3.new(1, 1, 1), 0.35)),
		ColorSequenceKeypoint.new(0.45, base),
		ColorSequenceKeypoint.new(1, base),
	})
end

-- The goo hanging under the band at across-fraction `x` continues it: the band's bottom colour, or for a
-- rainbow the colour at x along it.
function SlimePadSign.gooAt(view: SlimeLabel.View, x: number): Color3
	local shading = SlimePadSign.gooGradient(view)
	local at = if SlimeLabel.isRainbow(view) then x else 1
	local points = shading.Keypoints
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		if at >= a.Time and at <= b.Time then
			return a.Value:Lerp(b.Value, (at - a.Time) / math.max(b.Time - a.Time, 1e-6))
		end
	end
	return points[#points].Value
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

-- A goo piece: a white frame, rounded by `corner` px (nil = square) and, when `shaded`, tinted by its gradient
-- so the shading lands on every piece the same way; unshaded pieces (the drips) are coloured on render.
local function goo(name: string, props: { [string]: any }, parent: Instance, corner: number?, shaded: boolean): Frame
	local frame = create("Frame", {
		Name = name,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = parent,
	})
	if corner then
		Widgets.corner(corner).Parent = frame
	end
	if shaded then
		create("UIGradient", { Name = "Goo", Rotation = 90, Parent = frame })
	end
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

-- Where the plank sits for a pad part: in front of the stand, facing the jar's centre.
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
	create("Part", {
		Name = "Stake",
		Archivable = false,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Wood,
		Color = c.edge,
		Size = Vector3.new(s.stake, s.centreY, s.stake),
		Parent = part,
	})
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
	local band = goo("Band", { Size = UDim2.fromScale(1, l.band) }, board, s.corner, true)
	-- The band's lower corners are square: a foot covers them. The drips hang from its bottom edge; all are
	-- children of the band (same goo, so the overlap is invisible).
	goo("Foot", { Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5) }, band, nil, true)
	for i, d in SlimePadSign.DRIPS do
		goo(`Drip{i}`, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(d.x, 0.5),
			Size = UDim2.new(0, d.w, 0.5 + d.len / l.band, 0),
		}, band, 100, false)
	end
	local rarity = create("TextLabel", {
		Name = "Rarity",
		Position = UDim2.fromScale(l.inset, 0.16),
		Size = UDim2.fromScale(1 - 2 * l.inset, 0.72),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextScaled = true,
		TextColor3 = Theme.Ink,
		ZIndex = 3,
		Parent = band,
	})
	create("UIStroke", {
		Name = "Stroke",
		Thickness = 2.5,
		Color = Theme.Ink,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = rarity,
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
	})
	local fill = goo("Fill", { Size = UDim2.fromScale(0, 1) }, tube, 100, true);
	(fill:FindFirstChild("Goo") :: UIGradient).Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(GooPalette.MintHi)),
		ColorSequenceKeypoint.new(0.45, rgb(GooPalette.Mint)),
		ColorSequenceKeypoint.new(1, rgb(GooPalette.MintLo)),
	})
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
	local band = board:FindFirstChild("Band") :: Frame
	local rarity = band:FindFirstChild("Rarity") :: TextLabel
	local bandStroke = rarity:FindFirstChild("Stroke") :: UIStroke
	local title = board:FindFirstChild("Title") :: TextLabel
	local income = board:FindFirstChild("Income") :: TextLabel
	local growth = board:FindFirstChild("Growth") :: TextLabel
	local fill = (board:FindFirstChild("Track") :: Frame):FindFirstChild("Fill") :: Frame
	-- A rainbow runs along the band; the rarity shading runs top to bottom.
	local rotation = if SlimeLabel.isRainbow(view) then 0 else 90
	for _, piece in { band, band:FindFirstChild("Foot") :: Frame } do
		local shade = piece:FindFirstChild("Goo") :: UIGradient
		shade.Color = SlimePadSign.gooGradient(view)
		shade.Rotation = rotation
	end
	for i, d in SlimePadSign.DRIPS do
		(band:FindFirstChild(`Drip{i}`) :: Frame).BackgroundColor3 = SlimePadSign.gooAt(view, d.x)
	end
	local ink, strokeHidden = SlimePadSign.bandInk(view)
	rarity.TextColor3 = ink
	bandStroke.Transparency = strokeHidden
	rarity.Text = view.rarity
	-- The plank has no pill row: a shine the tag shows as a pill leads the name here, "Gold Mochi".
	title.Text = if view.shine then `{view.shine.id} {view.name}` else view.name
	income.Text = view.income or ""
	fill.Size = UDim2.fromScale(math.clamp(view.growth, 0, 100) / 100, 1)
	fill.Visible = view.growth > 0
	growth.Text = `{view.growth}%`
end

-- Puts the plank on `pad` (in `parent`, a client-only folder).
function SlimePadSign.place(part: Part, pad: BasePart, parent: Instance)
	local s = SlimePadSign.SIZE
	part.CFrame = SlimePadSign.cframe(pad)
	local stake = part:FindFirstChild("Stake")
	if stake and stake:IsA("BasePart") then
		-- behind the plank, from the floor up to its middle
		stake.CFrame = part.CFrame * CFrame.new(0, -s.centreY / 2, (s.thickness + s.stake) / 2)
	end
	part.Parent = parent
end

return SlimePadSign
