--!strict
--[[
	Props (owner: Archer)

	Builders for world props. Each returns a new, unparented Model / Tool,
	built from primitives, no scripts, no yields, no services. Models pivot at
	their bottom centre and face local -Z (put them down with
	model:PivotTo(CFrame)). Suggested spots: WorldLayout.PROP_SPOTS.

	  Props.shopStand(style): Model      "ItemShopStand" | "UpgradeShopStand";
	      PrimaryPart "Counter" (ProximityPrompt parent), striped awning, a Goo
	      jelly sign with the shop's name. Anchored. `style` "ItemShop" |
	      "UpgradeShop" (Props.STAND_STYLES) picks the stand's kit skin
	      (WorldLayout.SHOP_STANDS) and its sign (mint or gold jelly); the
	      Model's box is the skin's box.
	  Props.speedCoil(): Tool            "SpeedCoil"; "Handle" Part with
	      welded coil rings, all Massless, CanCollide false, unanchored.
	  Props.tutorialNpc(): Model         "TutorialNpc"; R6-ish primitives laid
	      out like its ranch_guide skin (HumanoidRootPart (PrimaryPart), Torso,
	      Head, Left/Right Arm, Left/Right Leg), straw hat, slime hat, an
	      invisible "Bounds" part (the skin's box), "NameTag" BillboardGui on
	      Head, and an Attachment "ArrowStart" above the hat. Anchored, no Humanoid.
	  Props.leaderboardBoard(): Model    "LeaderboardBoard"; PrimaryPart
	      "Board" with SurfaceGui "BoardGui" (Front face) > Frame "Content"
	      > TextLabel "Title" + Frame "Rows" (UIListLayout). The UI fills Rows.
	  Props.fillLeaderboard(board, entries, format?)
	      Optional helper: replaces Rows with "Row_<k>" frames (Rank, Name,
	      Value labels), at most Props.LEADERBOARD_ROWS.
]]

local Goo = if script then require(script.Parent.Parent.Shared.GooPalette) else require("../../shared/GooPalette")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

local Props = {}

Props.LEADERBOARD_ROWS = 10
Props.LEADERBOARD_TITLE = "Top Earners"

-- Top Earners text colours (RGB), drawn straight on the board skin's warm cream face (no backing panel,
-- B2 2026-10-18). Dark ink on cream, every colour >= 4.5:1 on the face and on the tan zebra row
-- (tests/PropMesh.spec); ui/WorldLeaderboard.PALETTE must equal this (tests/ui/WorldLeaderboard.spec).
Props.BOARD_PALETTE = table.freeze({
	Face = table.freeze({ 248, 236, 212 }), -- the skin's cream panel (phoenix_top_earners_board)
	RowAlt = table.freeze({ 238, 218, 182 }), -- every second row, a tan stripe on the face
	Me = table.freeze({ 179, 231, 191 }), -- the viewer's own row (client only)
	Title = table.freeze({ 94, 58, 34 }),
	Text = table.freeze({ 62, 40, 26 }),
	Muted = table.freeze({ 138, 106, 74 }),
	Value = table.freeze({ 24, 104, 56 }),
	Rank = table.freeze({ table.freeze({ 138, 88, 0 }), table.freeze({ 96, 102, 112 }), table.freeze({ 150, 73, 30 }) }),
})

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function ink(c: { number }): Color3
	return rgb(c[1], c[2], c[3])
end

type PartOpts = {
	shape: string?,
	material: string?,
	transparency: number?,
	canCollide: boolean?,
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, opts: PartOpts?): Part
	local o: PartOpts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = (Enum.PartType :: any)[o.shape or "Block"]
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = (Enum.Material :: any)[o.material or "SmoothPlastic"]
	p.Transparency = o.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = o.canCollide ~= false
	p.Parent = parent
	return p
end

-- Upright cylinder: Roblox cylinders run along X, roll 90 degrees.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local function label(parent: Instance, name: string, text: string, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.Parent = parent
	return l
end

local function finish(model: Model, primary: BasePart): Model
	model.PrimaryPart = primary
	-- Pivot at the bottom centre (y = 0 in build space).
	primary.PivotOffset = primary.CFrame:Inverse()
	model.WorldPivot = CFrame.new()
	return model
end

-- Shop stand ---------------------------------------------------------------

local function tone(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type StandStyle = {
	stand: string, -- the WorldLayout.SHOP_STANDS entry: the kit mesh the stand skins, its sign face and counter
	title: string, -- the name on the sign
	icon: string, -- the emoji on the sign's white badge (the minimap pins use the same ones)
	jelly: { { number } }, -- the sign's jelly gradient, top, middle, bottom (GooPalette)
}

-- Per-shop look (CONTRACT.md §27.2). The two kit meshes carry the shops' own look (a pink market stall full of goods,
-- a blue and gold cabinet showing the six upgrades); the stands only add the sign (canvas GooWorldSigns): the item
-- shop on mint jelly, the upgrade shop on gold.
Props.STAND_STYLES = table.freeze({
	ItemShop = table.freeze({
		stand = "ItemShopStand",
		title = "Item shop",
		icon = "🛒",
		jelly = table.freeze({ Goo.MintHi, Goo.Mint, Goo.MintLo }),
	}),
	UpgradeShop = table.freeze({
		stand = "UpgradeShopStand",
		title = "Upgrade shop",
		icon = "⬆️",
		jelly = table.freeze({ Goo.GoldHi, Goo.Gold, Goo.GoldDeep }),
	}),
}) :: { [string]: StandStyle }

-- The jelly sign on the stand's sign face, as fractions of the face: the jelly across the top, the badge on its
-- left, short drips (x, drop width, neck length) falling from its bottom edge onto the empty face under it.
Props.STAND_SIGN = table.freeze({
	pixelsPerStud = 80,
	jelly = table.freeze({ x = 0.03, y = 0.04, w = 0.94, h = 0.7 }),
	radius = 0.28, -- of the jelly's height
	stroke = 4, -- px Ink outline
	badge = 0.78, -- of the jelly's height
	drips = table.freeze({
		table.freeze({ x = 0.16, w = 0.035, len = 0.06 }),
		table.freeze({ x = 0.55, w = 0.026, len = 0.02 }),
		table.freeze({ x = 0.84, w = 0.032, len = 0.04 }),
	}),
})

-- How far the Sign's front stands in front of the skin's sign face: closer, the text loses the depth test to the
-- face and vanishes (the kit meshes set their sign faces back from the box front to leave this room).
local SIGN_LIFT = 0.04
-- The Sign's thickness. At 0.05 the SurfaceGui text did not draw in Studio; 0.03 does. The engine still counts it 0.05 in
-- Model:GetBoundingBox, so the kit meshes keep their sign faces set back from the box front.
local SIGN_THICK = 0.03

-- An invisible 0.1 cube that only widens the Model's bounding box.
local MARKER = 0.1
local function marker(m: Model, name: string, at: Vector3)
	local p = part(m, name, Vector3.one * MARKER, CFrame.new(at), rgb(255, 255, 255), {
		transparency = 1,
		canCollide = false,
	})
	p.CanQuery = false
	p.CanTouch = false
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function frame(parent: Instance, name: string, color: Color3, pos: UDim2, size: UDim2): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.Parent = parent
	return f
end

local function inkStroke(parent: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = tone(Goo.Ink)
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

-- Draws the shop's jelly sign on `sign` (its Front face), for a face `aspect` = width / height: a jelly pill with
-- an Ink outline, a white badge with the shop's icon, the name in Ink, and a few drips under it.
function Props.standSign(sign: BasePart, look: StandStyle, aspect: number): SurfaceGui
	local S = Props.STAND_SIGN
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = S.pixelsPerStud
	gui.LightInfluence = 0 -- unlit: the sign stays readable at night
	gui.Parent = sign
	local j = S.jelly
	local hi, mid, lo = tone(look.jelly[1]), tone(look.jelly[2]), tone(look.jelly[3])
	local top = j.y + j.h
	for i, d in S.drips do
		local dropH = d.w * aspect -- round in px
		local neck = frame(
			gui,
			`Neck{i}`,
			lo,
			UDim2.fromScale(d.x - d.w * 0.32, top - 0.05),
			UDim2.fromScale(d.w * 0.64, d.len + 0.05 + dropH * 0.4)
		)
		corner(neck, UDim.new(1, 0))
		local drop = frame(gui, `Drop{i}`, lo, UDim2.fromScale(d.x - d.w / 2, top + d.len), UDim2.fromScale(d.w, dropH))
		corner(drop, UDim.new(1, 0))
	end
	local jelly = frame(gui, "Jelly", Color3.new(1, 1, 1), UDim2.fromScale(j.x, j.y), UDim2.fromScale(j.w, j.h))
	jelly.ZIndex = 2 -- over the drips' necks
	corner(jelly, UDim.new(S.radius, 0))
	inkStroke(jelly, S.stroke)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, hi),
		ColorSequenceKeypoint.new(0.45, mid),
		ColorSequenceKeypoint.new(1, lo),
	})
	shade.Parent = jelly
	-- The jelly's width in units of its height, to place things left to right in height units.
	local wide = j.w * aspect / j.h
	local shine =
		frame(jelly, "Shine", Color3.new(1, 1, 1), UDim2.fromScale(0.3 / wide, 0.1), UDim2.fromScale(0.4 / wide, 0.1))
	shine.BackgroundTransparency = 0.35
	shine.Rotation = -24
	shine.ZIndex = 2
	corner(shine, UDim.new(1, 0))
	local inset = (1 - S.badge) / 2
	local badge = frame(
		jelly,
		"Badge",
		tone(Goo.White),
		UDim2.fromScale(inset * 1.4 / wide, inset),
		UDim2.fromScale(S.badge / wide, S.badge)
	)
	badge.ZIndex = 2
	corner(badge, UDim.new(1, 0))
	inkStroke(badge, S.stroke - 1)
	local icon = label(badge, "Icon", look.icon, tone(Goo.Ink))
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.Position = UDim2.fromScale(0.14, 0.14)
	icon.ZIndex = 3
	local text = label(jelly, "Text", look.title, tone(Goo.Ink))
	local textX = (inset * 2.4 + S.badge) / wide
	text.Position = UDim2.fromScale(textX, 0.17)
	text.Size = UDim2.fromScale(0.97 - textX, 0.66)
	text.ZIndex = 2
	return gui
end

function Props.shopStand(style: string): Model
	local look = Props.STAND_STYLES[style]
	assert(look, `Props.shopStand: unknown style {style}`)
	local def = WorldLayout.SHOP_STANDS[look.stand]
	local k = def.scale
	local native = WorldLayout.meshSize(def.mesh, 1)
	local w, h, d = native[1] * k, native[2] * k, native[3] * k
	local c, face = def.counter, def.face
	-- Build space: the skin's box stands on the ground centred on x = z = 0 (the pivot). The Model's box is exactly the
	-- skin's (two corner markers; every primitive fits inside), so MeshSwap lays the mesh into it unmoved and its counter
	-- lands on the Counter part. Front = local -Z, the kit's +Z: the counter is c.z * k ahead of the box centre.
	local cx, cz = c.x * k, -c.z * k
	local m = Instance.new("Model")
	m.Name = look.stand
	local half = MARKER / 2
	marker(m, "BoxLow", Vector3.new(-w / 2 + half, half, -d / 2 + half))
	marker(m, "BoxHigh", Vector3.new(w / 2 - half, h - half, d / 2 - half))
	-- The primitive stand (shown until the skin loads, collidable under it): counter, back, posts, striped awning.
	local wood, woodDark = rgb(196, 140, 90), rgb(130, 88, 56)
	local top = c.top * k
	local counter = part(
		m,
		"Counter",
		Vector3.new((c.width - 0.6) * k, top - 0.4, (c.depth - 0.6) * k),
		CFrame.new(cx, (top - 0.4) / 2, cz),
		wood,
		{ material = "WoodPlanks" }
	)
	part(m, "CounterTop", Vector3.new(c.width * k, 0.4, c.depth * k), CFrame.new(cx, top - 0.2, cz), woodDark, {
		material = "Wood",
	})
	local inner = w - 0.6 -- the primitives keep 0.3 inside the box on every side
	part(m, "Back", Vector3.new(math.min(10, inner), 9, 0.6), CFrame.new(0, 4.5, d / 2 - 0.6), wood, {
		material = "WoodPlanks",
	})
	local postX = math.min(4.8, inner / 2 - 0.3)
	for side, x in { L = -postX, R = postX } do
		part(m, `Post{side}`, Vector3.new(0.6, 9, 0.6), CFrame.new(x, 4.5, cz - c.depth * k / 2), woodDark, {
			material = "Wood",
		})
	end
	-- Striped awning over the whole box depth, tilted down towards the front.
	local tilt = math.rad(15)
	local run = (d - 1.2) / math.cos(tilt)
	local stripes = 7
	local sw = math.min(11.6, inner) / stripes
	for i = 1, stripes do
		local color = if i % 2 == 0 then rgb(255, 255, 255) else rgb(80, 210, 120)
		part(
			m,
			`Awning{i}`,
			Vector3.new(sw, 0.3, run),
			CFrame.new(-sw * stripes / 2 + (i - 0.5) * sw, math.min(9.4, h - 1.5), 0) * CFrame.Angles(-tilt, 0, 0),
			color,
			{ material = "Fabric" }
		)
	end
	-- The SHOP text lies on the skin's own sign face: a SIGN_THICK Sign whose front stands SIGN_LIFT in front of that face,
	-- so the text sits on it instead of floating, and never loses the depth test to the face.
	local signFront = -face.front * k - SIGN_LIFT
	local sign = part(
		m,
		"Sign",
		Vector3.new(face.width * k, face.height * k, SIGN_THICK),
		CFrame.new(face.x * k, face.y * k, signFront + SIGN_THICK / 2),
		tone(look.jelly[2]),
		{ canCollide = false }
	)
	sign.Transparency = 1 -- only the jelly draws; the kit's own sign face shows round it
	sign.CanQuery = false
	Props.standSign(sign, look, face.width / face.height)
	-- A few goo jars on the counter.
	for i, color in { rgb(120, 255, 140), rgb(255, 130, 220), rgb(120, 200, 255) } do
		local jar = part(
			m,
			`Jar{i}`,
			Vector3.new(1.4, 1.1, 1.1),
			CFrame.new(cx - 3 + (i - 1) * 3, top + 0.7, cz) * UPRIGHT,
			color,
			{ shape = "Cylinder", material = "Glass", transparency = 0.25, canCollide = false }
		)
		jar.CastShadow = false
	end
	return finish(m, counter)
end

-- Speed coil ---------------------------------------------------------------

function Props.speedCoil(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "SpeedCoil"
	tool.ToolTip = "Speed Coil"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -0.6, 0)
	local handle = part(
		tool,
		"Handle",
		Vector3.new(2.4, 0.6, 0.6),
		UPRIGHT,
		rgb(60, 60, 70),
		{ shape = "Cylinder", material = "Metal", canCollide = false }
	)
	local function decor(name: string, size: Vector3, cf: CFrame, color: Color3, shape: string, material: string)
		local p = part(tool, name, size, cf, color, { shape = shape, material = material, canCollide = false })
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
	end
	for i = 1, 5 do
		decor(
			`Coil{i}`,
			Vector3.new(0.25, 1.2, 1.2),
			CFrame.new(0, -0.8 + (i - 1) * 0.4, 0) * UPRIGHT,
			if i % 2 == 0 then rgb(60, 200, 255) else rgb(255, 230, 80),
			"Cylinder",
			"Neon"
		)
	end
	decor("Cap", Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 1.35, 0), rgb(120, 255, 140), "Ball", "Neon")
	for _, inst in tool:GetChildren() do
		if inst:IsA("BasePart") then
			inst.Anchored = false
			inst.Massless = true
			inst.CanQuery = false
			inst.CanTouch = inst == handle
		end
	end
	return tool
end

-- Tutorial NPC -------------------------------------------------------------

-- The primitive Guide follows the ranch_guide skin's layout (shared/modeling-kit/models/ranch_guide.py), at
-- GUIDE_SCALE studs per kit unit: the skin's head lands on Head (the NameTag's part), and the body parts it hides
-- are its colliders. Kit (x, y, z-up, front -y) -> Model local (-x, z, y), front -Z.
local GUIDE_SCALE = 0.7825
-- The skin's bounding box in kit units (centre, size): an invisible Bounds part pins the Model's box to it, so
-- MeshSwap centres the skin exactly on this body.
local GUIDE_BOUNDS_CENTRE = { 0.3396, 0.05, 3.9935 }
local GUIDE_BOUNDS_SIZE = { 4.765, 3.481, 7.987 }
local GUIDE_TOP = 7.987 -- kit z of the skin's top (the slime on the hat)

local function guidePos(x: number, y: number, z: number): Vector3
	return Vector3.new(-x, z, y) * GUIDE_SCALE
end

local function guideSize(x: number, y: number, z: number): Vector3
	return Vector3.new(x, z, y) * GUIDE_SCALE
end

-- A limb from `top` (kit) along the kit x-z direction (dx, dz), `length` kit units long, as a Part whose Y axis is
-- the limb's axis.
local function guideLimb(m: Model, name: string, top: { number }, dx: number, dz: number, length: number, color: Color3)
	local d = math.sqrt(dx * dx + dz * dz)
	dx, dz = dx / d, dz / d
	local centre = guidePos(top[1] + dx * length / 2, top[2], top[3] + dz * length / 2)
	-- Model-local axis pointing from the far end back to the top.
	local up = Vector3.new(dx, -dz, 0)
	local right = Vector3.new(up.Y, -up.X, 0)
	local cf = CFrame.fromMatrix(centre, right, up, Vector3.new(0, 0, 1))
	return part(m, name, guideSize(0.85, 0.85, length), cf, color, {})
end

function Props.tutorialNpc(): Model
	local m = Instance.new("Model")
	m.Name = "TutorialNpc"
	local skin, shirt, denim = rgb(255, 210, 166), rgb(214, 92, 84), rgb(84, 140, 214)
	local straw, goo = rgb(252, 216, 110), rgb(110, 226, 170)
	local root = part(
		m,
		"HumanoidRootPart",
		guideSize(2.1, 1.15, 2.1),
		CFrame.new(guidePos(0, 0, 3.3)),
		shirt,
		{ transparency = 1, canCollide = false }
	)
	part(m, "Torso", guideSize(2.1, 1.15, 2.1), CFrame.new(guidePos(0, 0, 3.3)), shirt, {})
	local bib =
		part(m, "Bib", guideSize(1.3, 0.2, 1.4), CFrame.new(guidePos(0, -0.56, 2.95)), denim, { canCollide = false })
	bib.CanQuery = false
	-- Kit -x is the Guide's right (local +X).
	part(m, "Right Leg", guideSize(0.9, 1.0, 2.3), CFrame.new(guidePos(-0.5, 0, 1.15)), denim, {})
	part(m, "Left Leg", guideSize(0.9, 1.0, 2.3), CFrame.new(guidePos(0.5, 0, 1.15)), denim, {})
	-- Right arm relaxed, left arm raised in a wave (hands included).
	guideLimb(m, "Right Arm", { -1.4, 0, 4.1 }, -math.sin(math.rad(8)), -math.cos(math.rad(8)), 2.2, shirt)
	guideLimb(m, "Left Arm", { 1.3, 0, 4.0 }, math.sin(math.rad(145)), -math.cos(math.rad(145)), 2.25, shirt)
	local head = part(m, "Head", guideSize(1.75, 1.55, 1.65), CFrame.new(guidePos(0, 0, 5.375)), skin, {})
	for side, x in { L = 0.36, R = -0.36 } do
		local eye = part(
			m,
			`Eye{side}`,
			guideSize(0.22, 0.06, 0.32),
			CFrame.new(guidePos(x, -0.8, 5.45)),
			rgb(40, 34, 44),
			{ canCollide = false }
		)
		eye.CanQuery = false
	end
	local smile = part(
		m,
		"Smile",
		guideSize(0.5, 0.06, 0.1),
		CFrame.new(guidePos(0, -0.8, 5.0)),
		rgb(40, 34, 44),
		{ canCollide = false }
	)
	smile.CanQuery = false
	for _, piece in
		{
			{ "HatBrim", 0.45, 3.5, 6.23 },
			{ "HatCrown", 1.1, 1.9, 6.7 },
		}
	do
		local p = part(
			m,
			piece[1],
			Vector3.new(piece[2], piece[3], piece[3]) * GUIDE_SCALE,
			CFrame.new(guidePos(0, 0.05, piece[4])) * UPRIGHT,
			straw,
			{ shape = "Cylinder", canCollide = false }
		)
		p.CanQuery = false
	end
	local hat = part(
		m,
		"SlimeHat",
		Vector3.one * 1.24 * GUIDE_SCALE,
		CFrame.new(guidePos(0.05, 0.2, GUIDE_TOP - 0.62)),
		goo,
		{ shape = "Ball", canCollide = false }
	)
	hat.CanQuery = false
	local arrowStart = Instance.new("Attachment")
	arrowStart.Name = "ArrowStart"
	arrowStart.Position = Vector3.new(0, 0.6, 0)
	arrowStart.Parent = hat
	local c, s = GUIDE_BOUNDS_CENTRE, GUIDE_BOUNDS_SIZE
	local bounds = part(
		m,
		"Bounds",
		guideSize(s[1], s[2], s[3]),
		CFrame.new(guidePos(c[1], c[2], c[3])),
		shirt,
		{ transparency = 1, canCollide = false }
	)
	bounds.CanQuery = false
	bounds.CanTouch = false
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(170, 44)
	-- Straight above the head, clear of the slime on the hat.
	tag.StudsOffset = Vector3.new(0, (GUIDE_TOP - 5.375) * GUIDE_SCALE + 0.9, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 80
	tag.LightInfluence = 0 -- the white stays white in shade
	tag.Parent = head
	-- Outlined white Fredoka, like every world label (canvas GooWorldSigns "Guide").
	local text = label(tag, "Text", "Guide", tone(Goo.White))
	text.Size = UDim2.fromScale(1, 1)
	local outline = Instance.new("UIStroke")
	outline.Color = tone(Goo.Ink)
	outline.Thickness = 2.5
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = text
	return finish(m, root)
end

-- Leaderboard board --------------------------------------------------------

function Props.leaderboardBoard(): Model
	local m = Instance.new("Model")
	m.Name = "LeaderboardBoard"
	local frameColor = rgb(70, 52, 50)
	-- The text lies on the skin's own front cream panel (WorldProps skins this
	-- Model with phoenix_top_earners_board, 19.5 tall so scale 0.978, its front
	-- flush with the Model's front at z -0.4). WorldLayout.DEX_FACE x 0.978,
	-- mirrored into the Model's frame (kit front +Z is local -Z): a 12.62 x
	-- 11.25 Board, 0.03 thin, centred (0.34, 11.28) and 1.2 behind the front,
	-- so the board is the face itself, not a slab beside it (v30 C7). The
	-- Frame and posts sit behind it as the pre-mesh look; "Collider" (invisible)
	-- is the solid in front and keeps the Model's front and height.
	-- Invisible: only the SurfaceGui text shows, on the skin's own cream face (B2: no black backing).
	local board = part(m, "Board", Vector3.new(12.62, 11.25, 0.03), CFrame.new(0.342, 11.279, 1.198), rgb(30, 32, 44), {
		canCollide = false,
		transparency = 1,
	})
	part(m, "Frame", Vector3.new(15, 17, 0.6), CFrame.new(0, 11, 1.52), frameColor, { material = "Basalt" })
	for side, x in { L = -6.5, R = 6.5 } do
		part(m, `Post{side}`, Vector3.new(1, 4, 1), CFrame.new(x, 2, 1.52), frameColor, { material = "Basalt" })
	end
	part(m, "Collider", Vector3.new(15, 17, 1.6), CFrame.new(0, 11, 0.4), frameColor, { transparency = 1 })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Adornee = board
	gui.Parent = board
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Parent = gui
	local padding = Instance.new("UIPadding")
	local pad = UDim.new(0.04, 0)
	padding.PaddingTop, padding.PaddingBottom, padding.PaddingLeft, padding.PaddingRight = pad, pad, pad, pad
	padding.Parent = content
	local title = label(content, "Title", Props.LEADERBOARD_TITLE, ink(Props.BOARD_PALETTE.Title))
	title.Size = UDim2.fromScale(1, 0.12)
	-- The skin's red divider runs 2.45 studs below the face top (about 0.21-0.23 of the Board), so the
	-- rows start just under it and the title keeps the band above.
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Position = UDim2.fromScale(0, 0.24)
	rows.Size = UDim2.fromScale(1, 0.76)
	rows.BackgroundTransparency = 1
	rows.Parent = content
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0.01, 0)
	list.Parent = rows
	return finish(m, board)
end

function Props.fillLeaderboard(
	board: Model,
	entries: { { rank: number, name: string, value: number } },
	format: ((number) -> string)?
)
	local rows = board:FindFirstChild("Rows", true)
	if not rows then
		return
	end
	for _, child in rows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local fmt = format or tostring
	local palette = Props.BOARD_PALETTE
	for k, entry in entries do
		if k > Props.LEADERBOARD_ROWS then
			break
		end
		local row = Instance.new("Frame")
		row.Name = `Row_{k}`
		row.LayoutOrder = k
		row.Size = UDim2.fromScale(1, 1 / Props.LEADERBOARD_ROWS - 0.01)
		row.BackgroundColor3 = ink(palette.RowAlt)
		row.BackgroundTransparency = if k % 2 == 0 then 0 else 1 -- tan stripes straight on the face
		row.BorderSizePixel = 0
		local rank = label(row, "Rank", `#{entry.rank}`, ink(palette.Rank[k] or palette.Text))
		rank.Size = UDim2.fromScale(0.15, 1)
		local name = label(row, "Name", entry.name, ink(palette.Text))
		name.Position = UDim2.fromScale(0.17, 0)
		name.Size = UDim2.fromScale(0.5, 1)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local value = label(row, "Value", fmt(entry.value), ink(palette.Value))
		value.Position = UDim2.fromScale(0.68, 0)
		value.Size = UDim2.fromScale(0.32, 1)
		value.TextXAlignment = Enum.TextXAlignment.Right
		row.Parent = rows
	end
end

return Props
