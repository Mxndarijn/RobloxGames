--!strict
--[[
	Props (owner: Archer)

	Builders for world props. Each returns a new, unparented Model / Tool,
	built from primitives, no scripts, no yields, no services. Models pivot at
	their bottom centre and face local -Z (put them down with
	model:PivotTo(CFrame)). Suggested spots: WorldLayout.PROP_SPOTS.

	  Props.shopStand(): Model           "ShopStand"; PrimaryPart "Counter"
	      (ProximityPrompt parent), striped awning, "SHOP" sign. Anchored.
	  Props.speedCoil(): Tool            "SpeedCoil"; "Handle" Part with
	      welded coil rings, all Massless, CanCollide false, unanchored.
	  Props.tutorialNpc(): Model         "TutorialNpc"; R6-ish primitives
	      (HumanoidRootPart (PrimaryPart), Torso, Head, Left/Right Arm,
	      Left/Right Leg), slime hat, "NameTag" BillboardGui, and an
	      Attachment "ArrowStart" above the head. Anchored, no Humanoid.
	  Props.tutorialArrow(from, to, fromAttachment?): (Beam, Attachment, Attachment)
	      Beam "TutorialArrow" from `fromAttachment` (or a new Attachment
	      "ArrowFrom" in `from`) to a new Attachment "ArrowTo" in `to`. The
	      Beam is parented to `from`; destroy the three returned instances
	      to remove it. New attachments point their X axis world-up, so the
	      beam arcs up out of `from` and drops onto `to`. Untextured
	      (Texture stays empty; TextureMode Wrap + TextureSpeed are set for
	      a later chevron texture); animate it with Props.arrowBands.
	  Props.arrowBands(phase): NumberSequence
	      Beam Transparency with ARROW_BANDS bright bands that move from
	      Attachment0 to Attachment1 as `phase` goes 0 -> 1.
	  Props.tutorialChevrons(): Model    "TutorialChevrons": ARROW_CHEVRONS
	      Models "Chevron_<k>" (one per ARROW_SPACING studs of curve show,
	      at least 3) plus a big "Marker", each two Neon arms "ArmL"
	      / "ArmR" (anchored, no collision / query / touch / shadow).
	      Place them every frame with Props.placeChevrons.
	  Props.arrowCurve(beam): { Vector3 }  the beam's cubic Bezier
	      control points (Roblox Beam curve: CurveSize along WorldAxis).
	  Props.curvePoint(curve, t): (Vector3, Vector3)  point and unit tangent.
	  Props.placeChevrons(model, curve, phase, eye, now)
	      Chevrons flow along the curve (one spacing per phase cycle), lie
	      flat to `eye` and point along the path as seen from `eye`; the Marker bobs above the end,
	      pointing down.
	  Props.leaderboardBoard(): Model    "LeaderboardBoard"; PrimaryPart
	      "Board" with SurfaceGui "BoardGui" (Front face) > Frame "Content"
	      > TextLabel "Title" + Frame "Rows" (UIListLayout). The UI fills Rows.
	  Props.fillLeaderboard(board, entries, format?)
	      Optional helper: replaces Rows with "Row_<k>" frames (Rank, Name,
	      Value labels), at most Props.LEADERBOARD_ROWS.
]]

local RareSpawn = if script then require(script.Parent.RareSpawn) else require("./RareSpawn")

local Props = {}

Props.LEADERBOARD_ROWS = 10
Props.LEADERBOARD_TITLE = "Top Earners"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
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

function Props.shopStand(): Model
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
	local sign = part(m, "Sign", Vector3.new(6.284, 1.654, 0.03), CFrame.new(0, 10.088, 2.338), rgb(255, 245, 220), {})
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
	gui.Parent = sign
	local text = label(gui, "Text", "SHOP", rgb(40, 140, 70))
	text.Size = UDim2.fromScale(1, 1)
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

Props.ARROW_COLOR = rgb(255, 226, 60)
Props.ARROW_TIP_COLOR = rgb(110, 255, 130)
Props.ARROW_BANDS = 3
Props.ARROW_CHEVRONS = 14 -- pool size; at most this many show
Props.ARROW_SPACING = 6 -- studs between chevrons along the curve
Props.ARROW_CURVE = 6 -- studs the beam rises out of / drops onto its ends
-- Same cap as the rare-spawn beams (v30 C11): a 256-stud neon Beam is a night streak, so the arrow is a short
-- marker leading off from the character towards the target (guarded by the fx_streaks watcher shot).
Props.ARROW_MAX_LENGTH = RareSpawn.MAX_BEAM_HEIGHT

-- Local CFrame at `position` in `p` whose X axis (Beam curve axis) is world-up.
local function upFrame(p: BasePart, position: Vector3): CFrame
	local x = p.CFrame:VectorToObjectSpace(Vector3.new(0, 1, 0))
	local ref = if math.abs(x.Z) < 0.9 then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
	return CFrame.fromMatrix(position, x, ref:Cross(x).Unit)
end

local function upAttachment(p: BasePart, name: string, position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = upFrame(p, position)
	a.Parent = p
	return a
end

-- Where the arrow's far end sits: on the target when it is within ARROW_MAX_LENGTH, else that far from `from`
-- towards it (world position).
local function arrowEnd(from: BasePart, to: BasePart): Vector3
	local top = to.Position + Vector3.new(0, to.Size.Y / 2 + 0.5, 0)
	local offset = top - from.Position
	if offset.Magnitude <= Props.ARROW_MAX_LENGTH then
		return top
	end
	return from.Position + offset.Unit * Props.ARROW_MAX_LENGTH
end

-- Re-aims a capped arrow's end attachment (lives on `from` when the target is too far); call as either moves.
function Props.arrowAim(a1: Attachment, from: BasePart, to: BasePart)
	local owner = a1.Parent :: BasePart
	if owner == from then
		a1.CFrame = upFrame(from, from.CFrame:PointToObjectSpace(arrowEnd(from, to)))
	end
end

function Props.tutorialArrow(from: BasePart, to: BasePart, fromAttachment: Attachment?): (Beam, Attachment, Attachment)
	local a0 = fromAttachment or upAttachment(from, "ArrowFrom", Vector3.new(0, 0, 0))
	local near = (to.Position - from.Position).Magnitude <= Props.ARROW_MAX_LENGTH
	local a1 = if near
		then upAttachment(to, "ArrowTo", Vector3.new(0, to.Size.Y / 2 + 0.5, 0))
		else upAttachment(from, "ArrowTo", from.CFrame:PointToObjectSpace(arrowEnd(from, to)))
	local beam = Instance.new("Beam")
	beam.Name = "TutorialArrow"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.8
	beam.Width1 = 0.4
	beam.FaceCamera = true
	beam.LightEmission = 0.4 -- additive 1 washed out to a white smear edge-on
	beam.LightInfluence = 0
	beam.Brightness = 2
	beam.Segments = 32
	beam.CurveSize0 = Props.ARROW_CURVE
	beam.CurveSize1 = -Props.ARROW_CURVE
	beam.Texture = "" -- no asset id we can vouch for; the chevron parts carry the shape
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 3
	beam.TextureSpeed = 1.5
	beam.Color = ColorSequence.new(Props.ARROW_COLOR, Props.ARROW_TIP_COLOR)
	beam.Transparency = Props.arrowBands(0)
	beam.Parent = from
	return beam, a0, a1
end

function Props.arrowBands(phase: number): NumberSequence
	local keys = {}
	local n = 16 -- NumberSequence allows 20 keypoints
	for k = 0, n - 1 do
		local t = k / (n - 1)
		local wave = 0.5 + 0.5 * math.cos(2 * math.pi * (t * Props.ARROW_BANDS - phase))
		table.insert(keys, NumberSequenceKeypoint.new(t, 0.55 - 0.45 * wave))
	end
	return NumberSequence.new(keys)
end

local CHEVRON_ARM = 2
local CHEVRON_ANGLE = math.rad(48)

local function chevron(parent: Instance, name: string, scale: number, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = name
	for _, side in { "ArmL", "ArmR" } do
		local arm = part(m, side, Vector3.new(0.55, 0.3, CHEVRON_ARM) * scale, CFrame.new(), color, {
			material = "Neon",
			canCollide = false,
		})
		arm.CanQuery = false
		arm.CanTouch = false
		arm.CastShadow = false
	end
	m:SetAttribute("Scale", scale)
	m.Parent = parent
	return m
end

function Props.tutorialChevrons(): Model
	local m = Instance.new("Model")
	m.Name = "TutorialChevrons"
	for k = 1, Props.ARROW_CHEVRONS do
		chevron(m, `Chevron_{k}`, 1, Props.ARROW_COLOR)
	end
	chevron(m, "Marker", 2.4, Props.ARROW_TIP_COLOR)
	return m
end

function Props.arrowCurve(beam: Beam): { Vector3 }
	local a0, a1 = beam.Attachment0 :: Attachment, beam.Attachment1 :: Attachment
	-- parent CFrame * attachment CFrame == WorldCFrame (Lune has no WorldCFrame)
	local w0 = (a0.Parent :: BasePart).CFrame * a0.CFrame
	local w1 = (a1.Parent :: BasePart).CFrame * a1.CFrame
	return {
		w0.Position,
		w0.Position + w0.RightVector * beam.CurveSize0,
		w1.Position - w1.RightVector * beam.CurveSize1,
		w1.Position,
	}
end

function Props.curvePoint(curve: { Vector3 }, t: number): (Vector3, Vector3)
	local u = 1 - t
	local p0, p1, p2, p3 = curve[1], curve[2], curve[3], curve[4]
	local point = p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
	local d = (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * t) + (p3 - p2) * (3 * t * t)
	if d.Magnitude < 1e-4 then
		d = p3 - p0
	end
	return point, if d.Magnitude < 1e-4 then Vector3.new(0, -1, 0) else d.Unit
end

-- Chevron tip at `tip` lying flat to `eye` (billboard) and pointing along `dir` as
-- seen from `eye`, so it reads as a V even when the path runs away from the camera.
local function placeChevron(m: Model, tip: Vector3, dir: Vector3, eye: Vector3, transparency: number)
	local scale = (m:GetAttribute("Scale") :: number?) or 1
	local view = eye - tip
	view = if view.Magnitude > 1e-3 then view.Unit else Vector3.new(0, 1, 0)
	local flat = dir - view * dir:Dot(view)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, -1, 0) - view * -view.Y -- head-on: point down the screen
	end
	if flat.Magnitude < 1e-3 then
		flat = view:Cross(Vector3.new(1, 0, 0))
	end
	dir = flat.Unit
	local side = dir:Cross(view).Unit
	local normal = view
	local half = CHEVRON_ARM * scale / 2
	for _, arm in m:GetChildren() do
		if arm:IsA("BasePart") then
			local sign = if arm.Name == "ArmL" then 1 else -1
			local back = (-dir * math.cos(CHEVRON_ANGLE) + side * sign * math.sin(CHEVRON_ANGLE)).Unit
			local centre = tip + back * (half - 0.25 * scale) -- arms overlap at the tip
			arm.CFrame = CFrame.lookAt(centre, centre + back, normal)
			arm.Transparency = transparency
		end
	end
end

function Props.placeChevrons(model: Model, curve: { Vector3 }, phase: number, eye: Vector3, now: number)
	-- Bezier length ~ mean of chord and control polygon.
	local chord = (curve[4] - curve[1]).Magnitude
	local polygon = (curve[2] - curve[1]).Magnitude + (curve[3] - curve[2]).Magnitude + (curve[4] - curve[3]).Magnitude
	local n = math.clamp(math.floor((chord + polygon) / 2 / Props.ARROW_SPACING), 3, Props.ARROW_CHEVRONS)
	for k = 1, Props.ARROW_CHEVRONS do
		local m = model:FindFirstChild(`Chevron_{k}`)
		if m and m:IsA("Model") and k > n then
			placeChevron(m, curve[1], Vector3.new(0, 1, 0), eye, 1)
		elseif m and m:IsA("Model") then
			local s = ((k - 1 + phase) % n) / n -- 0..1 along the run
			local t = 0.06 + 0.82 * s -- clear of the character and the marker
			local point, dir = Props.curvePoint(curve, t)
			local fade = math.min(s / 0.15, (1 - s) / 0.15, 1) -- fade in / out at the run's ends
			placeChevron(m, point, dir, eye, 1 - 0.95 * math.max(fade, 0))
		end
	end
	local marker = model:FindFirstChild("Marker")
	if marker and marker:IsA("Model") then
		local tip = curve[4] + Vector3.new(0, 1.5 + 0.8 * (0.5 + 0.5 * math.sin(now * 4)), 0)
		placeChevron(marker, tip, Vector3.new(0, -1, 0), eye, 0)
	end
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
	local board = part(m, "Board", Vector3.new(12.62, 11.25, 0.03), CFrame.new(0.342, 11.279, 1.198), rgb(30, 32, 44), {
		canCollide = false,
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
	content.BackgroundColor3 = rgb(30, 32, 44)
	content.BorderSizePixel = 0
	content.Parent = gui
	local padding = Instance.new("UIPadding")
	local pad = UDim.new(0.04, 0)
	padding.PaddingTop, padding.PaddingBottom, padding.PaddingLeft, padding.PaddingRight = pad, pad, pad, pad
	padding.Parent = content
	local title = label(content, "Title", Props.LEADERBOARD_TITLE, rgb(255, 210, 90))
	title.Size = UDim2.fromScale(1, 0.12)
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Position = UDim2.fromScale(0, 0.15)
	rows.Size = UDim2.fromScale(1, 0.85)
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
	for k, entry in entries do
		if k > Props.LEADERBOARD_ROWS then
			break
		end
		local row = Instance.new("Frame")
		row.Name = `Row_{k}`
		row.LayoutOrder = k
		row.Size = UDim2.fromScale(1, 1 / Props.LEADERBOARD_ROWS - 0.01)
		row.BackgroundColor3 = if k % 2 == 0 then rgb(44, 46, 60) else rgb(54, 56, 72)
		row.BorderSizePixel = 0
		local rankColor = if k == 1
			then rgb(255, 215, 60)
			elseif k == 2 then rgb(210, 210, 225)
			elseif k == 3 then rgb(220, 150, 90)
			else rgb(230, 230, 240)
		local rank = label(row, "Rank", `#{entry.rank}`, rankColor)
		rank.Size = UDim2.fromScale(0.15, 1)
		local name = label(row, "Name", entry.name, rgb(240, 240, 250))
		name.Position = UDim2.fromScale(0.17, 0)
		name.Size = UDim2.fromScale(0.5, 1)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local value = label(row, "Value", fmt(entry.value), rgb(140, 255, 150))
		value.Position = UDim2.fromScale(0.68, 0)
		value.Size = UDim2.fromScale(0.32, 1)
		value.TextXAlignment = Enum.TextXAlignment.Right
		row.Parent = rows
	end
end

return Props
