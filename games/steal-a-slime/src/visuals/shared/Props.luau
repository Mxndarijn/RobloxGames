--!strict
--[[
	Props (owner: Archer)

	Builders for world props. Each returns a new, unparented Model / Tool,
	built from primitives, no scripts, no yields, no services. Models pivot at
	their bottom centre and face local -Z (put them down with
	model:PivotTo(CFrame)). Suggested spots: WorldLayout.PROP_SPOTS.

	  Props.shopStand(style?): Model     "ShopStand"; PrimaryPart "Counter"
	      (ProximityPrompt parent), striped awning, "SHOP" sign. Anchored.
	      `style` "ItemShop" | "UpgradeShop" (Props.STAND_STYLES) picks the
	      stand's kit skin (WorldLayout.SHOP_STANDS) and its sign colours; the
	      Model's box is the skin's box.
	  Props.speedCoil(): Tool            "SpeedCoil"; "Handle" Part with
	      welded coil rings, all Massless, CanCollide false, unanchored.
	  Props.tutorialNpc(): Model         "TutorialNpc"; R6-ish primitives
	      (HumanoidRootPart (PrimaryPart), Torso, Head, Left/Right Arm,
	      Left/Right Leg), slime hat, "NameTag" BillboardGui, and an
	      Attachment "ArrowStart" above the head. Anchored, no Humanoid.
	  Props.leaderboardBoard(): Model    "LeaderboardBoard"; PrimaryPart
	      "Board" with SurfaceGui "BoardGui" (Front face) > Frame "Content"
	      > TextLabel "Title" + Frame "Rows" (UIListLayout). The UI fills Rows.
	  Props.fillLeaderboard(board, entries, format?)
	      Optional helper: replaces Rows with "Row_<k>" frames (Rank, Name,
	      Value labels), at most Props.LEADERBOARD_ROWS.
]]

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

local SIGN_BACK = rgb(58, 38, 26) -- dark wood board
local SIGN_TEXT = rgb(255, 240, 200) -- cream
local SIGN_STROKE = rgb(30, 18, 10)

type StandStyle = {
	stand: string, -- the WorldLayout.SHOP_STANDS entry: the kit mesh the stand skins, its sign face and counter
	signBack: Color3,
	signText: Color3,
	signStroke: Color3,
	signPlate: boolean, -- the board colour is painted behind the text, over the kit's own sign face
}

-- Per-shop look (CONTRACT.md §27.2). The two kit meshes carry the shops' own look (a pink market stall full of goods,
-- a blue and gold cabinet showing the six upgrades); the stands only add the sign colours.
Props.STAND_STYLES = table.freeze({
	ItemShop = table.freeze({
		stand = "ItemShopStand",
		signBack = SIGN_BACK,
		signText = SIGN_TEXT,
		signStroke = SIGN_STROKE,
		signPlate = false,
	}),
	UpgradeShop = table.freeze({
		stand = "UpgradeShopStand",
		signBack = rgb(26, 36, 78), -- navy plate on the cabinet's blue sign face
		signText = rgb(255, 214, 90), -- gold
		signStroke = rgb(10, 14, 36),
		signPlate = true,
	}),
}) :: { [string]: StandStyle }

-- The single ShopStand (FEATURES.WorldShops off).
local PLAIN_STAND: StandStyle = table.freeze({
	stand = "ShopStand",
	signBack = SIGN_BACK,
	signText = SIGN_TEXT,
	signStroke = SIGN_STROKE,
	signPlate = false,
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

function Props.shopStand(style: string?): Model
	local look = if style then Props.STAND_STYLES[style] or PLAIN_STAND else PLAIN_STAND
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
	m.Name = "ShopStand"
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
		look.signBack,
		{}
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- unlit: the SHOP text stays readable at night
	gui.Parent = sign
	local text = label(gui, "Text", "SHOP", look.signText)
	text.Size = UDim2.fromScale(1, 1)
	-- Light text with a dark stroke, inset so no post of the skin covers a letter from a front-diagonal view.
	text.TextStrokeColor3 = look.signStroke
	if look.signPlate then
		text.BackgroundColor3 = look.signBack
		text.BackgroundTransparency = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.18, 0)
		corner.Parent = text
	end
	text.TextStrokeTransparency = 0
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.12, 0)
	pad.PaddingRight = UDim.new(0.12, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = text
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

function Props.tutorialNpc(): Model
	local m = Instance.new("Model")
	m.Name = "TutorialNpc"
	local skin, shirt, pants = rgb(255, 214, 170), rgb(80, 170, 255), rgb(60, 70, 110)
	local root = part(
		m,
		"HumanoidRootPart",
		Vector3.new(2, 2, 1),
		CFrame.new(0, 3, 0),
		shirt,
		{ transparency = 1, canCollide = false }
	)
	part(m, "Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), shirt, {})
	part(m, "Left Leg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0), pants, {})
	part(m, "Right Leg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0), pants, {})
	part(m, "Left Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0), skin, {})
	-- Right arm raised, waving / pointing.
	part(
		m,
		"Right Arm",
		Vector3.new(1, 2, 1),
		CFrame.new(1.5, 4, 0) * CFrame.Angles(0, 0, math.rad(150)) * CFrame.new(0, -0.5, 0),
		skin,
		{}
	)
	local head = part(m, "Head", Vector3.new(2, 1, 1), CFrame.new(0, 4.5, 0), skin, {})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	for side, x in { L = -0.3, R = 0.3 } do
		local eye = part(
			m,
			`Eye{side}`,
			Vector3.new(0.18, 0.28, 0.05),
			CFrame.new(x, 4.6, -0.6),
			rgb(30, 30, 40),
			{ canCollide = false }
		)
		eye.CanQuery = false
	end
	local smile = part(
		m,
		"Smile",
		Vector3.new(0.5, 0.08, 0.05),
		CFrame.new(0, 4.25, -0.6),
		rgb(150, 50, 60),
		{ canCollide = false }
	)
	smile.CanQuery = false
	local hat = part(
		m,
		"SlimeHat",
		Vector3.new(1.8, 1.3, 1.8),
		CFrame.new(0, 5.6, 0),
		rgb(120, 255, 140),
		{ shape = "Ball", material = "Glass", transparency = 0.15, canCollide = false }
	)
	hat.CanQuery = false
	local arrowStart = Instance.new("Attachment")
	arrowStart.Name = "ArrowStart"
	arrowStart.Position = Vector3.new(0, 1.2, 0)
	arrowStart.Parent = hat
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(160, 40)
	tag.StudsOffset = Vector3.new(0, 2.6, 0)
	tag.AlwaysOnTop = false
	tag.MaxDistance = 80
	tag.Parent = head
	local text = label(tag, "Text", "Guide", rgb(255, 255, 255))
	text.Size = UDim2.fromScale(1, 1)
	text.TextStrokeTransparency = 0.3
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
