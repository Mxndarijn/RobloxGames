--!strict
--[[
	Props (owner: Archer)

	Builders for world props. Each returns a new, unparented Model / Tool,
	built from primitives, no scripts, no yields, no services. Models pivot at
	their bottom centre and face local -Z (put them down with
	model:PivotTo(CFrame)). Suggested spots: WorldLayout.PROP_SPOTS.

	  Props.shopStand(style?): Model     "ShopStand"; PrimaryPart "Counter"
	      (ProximityPrompt parent), striped awning, "SHOP" sign. Anchored.
	      `style` "ItemShop" | "UpgradeShop" (Props.STAND_STYLES) gives the
	      stand its own sign colours, skin tint and side decor (MeshKeep).
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

-- Side decor stays visible over the kit skin (MeshSwap hides every other part of the Model): no collision, no
-- queries, so it never blocks a player or a prompt.
local function standDecor(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, opts: PartOpts?): Part
	local o: PartOpts = table.clone(opts or {})
	o.canCollide = false
	local p = part(m, name, size, cf, color, o)
	p.CanQuery = false
	p.CanTouch = false
	p:SetAttribute("MeshKeep", true)
	return p
end

-- Decor sits beside the skin (9.6 wide at x 0) at x = +-DECOR_X. The two WidthMarkers keep the Model's box centred
-- on the counter, so the skin stays centred however wide each side's decor is.
local DECOR_X = 6.6
local WIDTH_MARKER_X = 9.2

local function glow(p: BasePart, color: Color3)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.2
	light.Range = 9
	light.Shadows = false
	light.Parent = p
end

-- A row of diamond pennants under the front of the skin's awning, in the shop's own colours (the awning itself is
-- the kit mesh's red and white for both stands). Kept behind the awning's front edge so the Model's box, and with
-- it the skin's place, does not change.
local BUNTING = table.freeze({ y = 5.6, z = -2.45, halfWidth = 4.2, count = 9, size = 0.95 })

local function bunting(m: Model, colors: { Color3 })
	standDecor(
		m,
		"DecorBuntingRope",
		Vector3.new(BUNTING.halfWidth * 2 + 0.6, 0.08, 0.08),
		CFrame.new(0, BUNTING.y + BUNTING.size * 0.7, BUNTING.z),
		rgb(240, 230, 210)
	)
	for i = 1, BUNTING.count do
		local x = -BUNTING.halfWidth + (i - 1) * (BUNTING.halfWidth * 2 / (BUNTING.count - 1))
		standDecor(
			m,
			`DecorPennant{i}`,
			Vector3.new(BUNTING.size, BUNTING.size, 0.06),
			CFrame.new(x, BUNTING.y, BUNTING.z) * CFrame.Angles(0, 0, math.rad(45)),
			colors[(i - 1) % #colors + 1]
		)
	end
end

-- Item Shop: a general store. Crates with potion bottles on the left, a spotted mystery egg on a barrel on the right.
local function itemDecor(m: Model)
	bunting(m, { rgb(100, 255, 140), rgb(255, 220, 80) })
	local crate, crateDark = rgb(176, 122, 72), rgb(120, 80, 46)
	local x = -DECOR_X
	standDecor(
		m,
		"DecorCrate1",
		Vector3.new(2.2, 2.2, 2.2),
		CFrame.new(x, 1.1, -0.2),
		crate,
		{ material = "WoodPlanks" }
	)
	standDecor(
		m,
		"DecorCrate2",
		Vector3.new(1.7, 1.7, 1.7),
		CFrame.new(x + 0.1, 3.05, -0.1) * CFrame.Angles(0, math.rad(22), 0),
		crateDark,
		{ material = "WoodPlanks" }
	)
	for i, color in { rgb(255, 110, 200), rgb(110, 240, 140), rgb(110, 190, 255) } do
		local bx = x - 0.55 + (i - 1) * 0.55
		local bottle = standDecor(
			m,
			`DecorPotion{i}`,
			Vector3.new(1.0, 0.5, 0.5),
			CFrame.new(bx, 4.4, -0.2) * UPRIGHT,
			color,
			{ shape = "Cylinder", material = "Glass", transparency = 0.15 }
		)
		bottle.CastShadow = false
		standDecor(m, `DecorCork{i}`, Vector3.new(0.25, 0.28, 0.28), CFrame.new(bx, 5.0, -0.2) * UPRIGHT, crateDark, {
			shape = "Cylinder",
			material = "Wood",
		})
	end
	x = DECOR_X
	standDecor(m, "DecorBarrel", Vector3.new(2.4, 2.2, 2.2), CFrame.new(x, 1.2, -0.2) * UPRIGHT, crate, {
		shape = "Cylinder",
		material = "Wood",
	})
	for i, y in { 0.45, 1.95 } do
		standDecor(m, `DecorHoop{i}`, Vector3.new(0.18, 2.3, 2.3), CFrame.new(x, y, -0.2) * UPRIGHT, rgb(70, 70, 78), {
			shape = "Cylinder",
			material = "Metal",
		})
	end
	local egg = standDecor(m, "DecorEgg", Vector3.new(2.2, 2.2, 2.2), CFrame.new(x, 3.4, -0.2), rgb(190, 150, 255), {
		shape = "Ball",
	})
	glow(egg, rgb(200, 160, 255))
	for i, spot in { { 0.5, 0.4, -0.85 }, { -0.6, 0.0, -0.75 }, { 0.1, -0.5, -0.95 }, { -0.2, 0.75, -0.6 } } do
		standDecor(
			m,
			`DecorEggSpot{i}`,
			Vector3.new(0.6, 0.6, 0.6),
			CFrame.new(x + spot[1], 3.4 + spot[2], -0.2 + spot[3]),
			rgb(255, 230, 120),
			{ shape = "Ball" }
		)
	end
end

-- One Neon up-chevron (two arms meeting at the top) centred at `at`.
local function standChevron(m: Model, name: string, at: Vector3, color: Color3): BasePart
	local arm = Vector3.new(1.5, 0.45, 0.4)
	local left = standDecor(
		m,
		`{name}L`,
		arm,
		CFrame.new(at + Vector3.new(-0.5, 0, 0)) * CFrame.Angles(0, 0, math.rad(40)),
		color,
		{ material = "Neon" }
	)
	standDecor(
		m,
		`{name}R`,
		arm,
		CFrame.new(at + Vector3.new(0.5, 0, 0)) * CFrame.Angles(0, 0, math.rad(-40)),
		color,
		{ material = "Neon" }
	)
	return left
end

-- Upgrade Shop: a forge. An anvil on a stump on the left, a pole of glowing up-chevrons on the right.
local function upgradeDecor(m: Model)
	bunting(m, { rgb(80, 135, 255), rgb(255, 215, 80) })
	local iron, ironDark = rgb(92, 98, 112), rgb(58, 62, 74)
	local x = -DECOR_X
	standDecor(m, "DecorStump", Vector3.new(1.6, 2.6, 2.6), CFrame.new(x, 0.8, -0.2) * UPRIGHT, rgb(130, 88, 56), {
		shape = "Cylinder",
		material = "Wood",
	})
	standDecor(
		m,
		"DecorAnvilFoot",
		Vector3.new(1.7, 0.6, 1.3),
		CFrame.new(x, 1.9, -0.2),
		ironDark,
		{ material = "Metal" }
	)
	standDecor(
		m,
		"DecorAnvilWaist",
		Vector3.new(1.0, 0.6, 0.8),
		CFrame.new(x, 2.5, -0.2),
		ironDark,
		{ material = "Metal" }
	)
	standDecor(m, "DecorAnvilTop", Vector3.new(2.8, 0.8, 1.4), CFrame.new(x, 3.2, -0.2), iron, { material = "Metal" })
	standDecor(
		m,
		"DecorAnvilHorn",
		Vector3.new(1.2, 0.6, 0.6),
		CFrame.new(x - 1.85, 3.25, -0.2) * CFrame.Angles(0, 0, math.rad(12)),
		iron,
		{ material = "Metal" }
	)
	local ingot = standDecor(
		m,
		"DecorIngot",
		Vector3.new(1.2, 0.4, 0.6),
		CFrame.new(x + 0.3, 3.8, -0.2),
		rgb(255, 150, 50),
		{ material = "Neon" }
	)
	glow(ingot, rgb(255, 150, 60))
	x = DECOR_X
	standDecor(
		m,
		"DecorPoleFoot",
		Vector3.new(1.8, 0.4, 1.8),
		CFrame.new(x, 0.2, -0.2),
		ironDark,
		{ material = "Metal" }
	)
	standDecor(m, "DecorPole", Vector3.new(0.35, 8.2, 0.35), CFrame.new(x, 4.3, 0.1), ironDark, { material = "Metal" })
	local colors = { rgb(90, 220, 255), rgb(120, 170, 255), rgb(255, 210, 80) }
	for i, color in colors do
		local top = standChevron(m, `DecorChevron{i}`, Vector3.new(x, 4.6 + (i - 1) * 1.9, -0.2), color)
		if i == #colors then
			glow(top, color)
		end
	end
end

-- Per-shop look (CONTRACT.md §27.2): sign board / text / stroke, the skin tint (MeshTint on the Model multiplies the
-- kit mesh's vertex colours; nil keeps the kit colours) and the side decor.
Props.STAND_STYLES = table.freeze({
	ItemShop = table.freeze({
		signBack = SIGN_BACK,
		signText = SIGN_TEXT,
		signStroke = SIGN_STROKE,
		signPlate = false,
		tint = nil :: Color3?,
		decor = itemDecor,
	}),
	UpgradeShop = table.freeze({
		signBack = rgb(26, 36, 78), -- navy board
		signText = rgb(255, 214, 90), -- gold
		signStroke = rgb(10, 14, 36),
		signPlate = true, -- the board colour is painted over the kit's butter sign face, so the gold text reads
		tint = rgb(165, 195, 255) :: Color3?, -- cool blue wood and awning
		decor = upgradeDecor,
	}),
})

function Props.shopStand(style: string?): Model
	local look = if style then (Props.STAND_STYLES :: any)[style] else nil
	local m = Instance.new("Model")
	m.Name = "ShopStand"
	local wood, woodDark = rgb(196, 140, 90), rgb(130, 88, 56)
	local counter =
		part(m, "Counter", Vector3.new(10, 3.5, 4), CFrame.new(0, 1.75, 0), wood, { material = "WoodPlanks" })
	part(m, "CounterTop", Vector3.new(10.6, 0.4, 4.6), CFrame.new(0, 3.7, 0), woodDark, { material = "Wood" })
	part(m, "Back", Vector3.new(10, 9, 0.6), CFrame.new(0, 4.5, 3.2), wood, { material = "WoodPlanks" })
	for side, x in { L = -4.8, R = 4.8 } do
		part(m, `Post{side}`, Vector3.new(0.6, 9, 0.6), CFrame.new(x, 4.5, -1.8), woodDark, { material = "Wood" })
	end
	-- Striped awning, tilted down towards the front.
	local stripes = 7
	local w = 11.6 / stripes
	for i = 1, stripes do
		local color = if i % 2 == 0 then rgb(255, 255, 255) else rgb(80, 210, 120)
		local x = -5.8 + (i - 0.5) * w
		part(
			m,
			`Awning{i}`,
			Vector3.new(w, 0.3, 6.4),
			CFrame.new(x, 9.4, 0.4) * CFrame.Angles(math.rad(-15), 0, 0),
			color,
			{ material = "Fabric" }
		)
	end
	-- The SHOP text lies on the kit stand's own sign face (WorldProps skins
	-- this Model with ranch_shop_stand, scaled to the Model's 11.7 height and
	-- flush with its front): BUY_STAND_FACE x 0.827, in the Model's frame the
	-- face is 2.353 behind the front, 10.09 up. A 0.03 thin Sign touches that
	-- face, so the text sits on it instead of floating in front (v29 B4).
	-- "HeightMarker" (invisible) keeps the Model 11.7 tall, so the skin's scale
	-- does not shrink with the lower sign.
	local sign = part(
		m,
		"Sign",
		Vector3.new(6.284, 1.654, 0.03),
		CFrame.new(0, 10.088, 2.338),
		if look then look.signBack else SIGN_BACK,
		{}
	)
	local marker = part(
		m,
		"HeightMarker",
		Vector3.new(0.1, 0.1, 0.1),
		CFrame.new(0, 11.65, 3.2),
		rgb(255, 255, 255),
		{ transparency = 1, canCollide = false }
	)
	marker.CanQuery = false
	marker.CanTouch = false
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- unlit: the SHOP text stays readable at night
	gui.Parent = sign
	local text = label(gui, "Text", "SHOP", if look then look.signText else SIGN_TEXT)
	text.Size = UDim2.fromScale(1, 1)
	-- Light text with a dark stroke on a dark backing, inset so the kit stand's posts never cover a letter
	-- from a front-diagonal view (v186: the "I" of ITEM SHOP, the "U" of UPGRADE SHOP).
	text.TextStrokeColor3 = if look then look.signStroke else SIGN_STROKE
	if look and look.signPlate then
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
			CFrame.new(-3 + (i - 1) * 3, 4.6, 0.4) * UPRIGHT,
			color,
			{ shape = "Cylinder", material = "Glass", transparency = 0.25, canCollide = false }
		)
		jar.CastShadow = false
	end
	if look then
		look.decor(m)
		for i, x in { -WIDTH_MARKER_X, WIDTH_MARKER_X } do
			local widthMarker = part(
				m,
				`WidthMarker{i}`,
				Vector3.new(0.1, 0.1, 0.1),
				CFrame.new(x, 0.05, 0),
				rgb(255, 255, 255),
				{ transparency = 1, canCollide = false }
			)
			widthMarker.CanQuery = false
			widthMarker.CanTouch = false
		end
		if look.tint then
			m:SetAttribute("MeshTint", look.tint)
		end
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
