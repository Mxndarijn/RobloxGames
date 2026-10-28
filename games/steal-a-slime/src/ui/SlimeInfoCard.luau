--!strict
--[[
	SlimeInfoCard (contract/slime-labels.md)

	The label of every slime model (tag Constants.SLIME_TAG). A wild, carried
	or escaping slime gets a floating tag above its mesh (canvas
	GooWorldLabels "Wild slime tag"), no panel: the rarity on a goo pill in
	the rarity colour (a rainbow for Secret), the species name in white
	outlined in Ink, the income per second in mint and, while it is for sale
	and the player stands within priceDistance, a "Buy $price" chip. Where
	tags overlap on screen the nearest one shows and the ones behind it hide
	(declutter). A slime resting on a pad (LabelPad set) shows no tag:
	its label is a goo-dipped sign on a stake in front of the pad's cork stand
	(SlimePadSign). The server writes the values as model attributes; the text
	is Shared.SlimeLabel. Client only, nothing replicates.

	Cost: a BillboardGui per slime with MaxDistance (the engine culls it), sized
	in studs plus pixels so it shrinks with distance and stays readable, and a
	plank per pad slime. Both are re-rendered only on AttributeChanged of the
	label attributes, and the tags are refitted when the camera's viewport
	size changes (a phone gets a smaller pixel floor and a shorter
	MaxDistance). No frame loop of its own and no tween: the client loop
	calls the `tick` that `start` returns, which resizes a tag only as it
	crosses closeLimit, re-renders it only as the player crosses
	priceDistance, and hides the tags that overlap a nearer one. The tag is parented
	to the Body (Archivable false, so a FollowPets clone never copies it); the
	planks go in one local folder. Both go with the model or its tag.
]]

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local SlimeLabel = require(Shared:WaitForChild("SlimeLabel"))
local SlimePadSign = require(script.Parent.SlimePadSign)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local SlimeInfoCard = {}

SlimeInfoCard.NAME = "SlimeInfoCard"
SlimeInfoCard.SIGN_FOLDER = "SlimePadSigns"

-- Tag size: studs (shrinks with distance) plus pixels (keeps it readable far away: the name row stays about
-- rowPx * its weight px tall at the edge of maxDistance). The pixels are for a viewport referenceHeightPx tall
-- and shrink with a shorter one (down to minPxScale), so a phone's tag takes the screen share a monitor's does.
SlimeInfoCard.SIZE = table.freeze({
	widthStuds = 3.4,
	widthPx = 160,
	rowStuds = 0.4, -- one weight-1 row
	rowPx = 20, -- the pixel floor of a weight-1 row
	referenceHeightPx = 720, -- viewport height the pixel floor is drawn for
	minPxScale = 0.6, -- the pixel floor never shrinks below this fraction
	maxDistance = 60, -- studs: hidden beyond
	smallViewportPx = 500, -- a viewport shorter than this (a phone) shows tags only up to smallMaxDistance
	smallMaxDistance = 40, -- studs
	closeLimit = 12, -- studs: a nearer camera draws the tag as large as at this distance, no larger (tick)
	priceDistance = 20, -- studs from the player's character: the Buy chip shows only nearer than this (tick)
	overlapSlack = 0.12, -- each side of a tag's screen box is pulled in by this fraction before overlap is tested
	maxTextSize = 72,
	stroke = 2, -- px Ink outline round the text and the pills
	pill = 0.86, -- a pill's height, fraction of its row (the rest is the gap to the next row)
	pillPad = 0.14, -- a pill's text inset top and bottom, fraction of its height
})

-- Rows, top to bottom, with heights relative to one row. The name is the largest; the price chip is next, so
-- it reads as the thing to act on.
SlimeInfoCard.ROWS = table.freeze({
	{ name = "Rarity", weight = 0.8 },
	{ name = "Title", weight = 1.3 },
	{ name = "Income", weight = 0.95 },
	{ name = "Price", weight = 1 },
})

export type Row = { name: string, y: number, h: number } -- y / h: fractions of the tag's height
export type Fit = { pxScale: number, maxDistance: number } -- how a tag is sized for one viewport

local rgb = SlimePadSign.rgb

-- Width / height of a pill holding `text`: Fredoka glyphs are about 0.4 of the pill's height wide at the
-- pill's text size, plus half a height of goo at each end. Too long a text only shrinks (TextScaled).
function SlimeInfoCard.pillAspect(text: string): number
	return 0.4 * (utf8.len(text) or #text) + 1
end

-- The rarity pill's look: its fill colour, the gradient over it (a rainbow for Secret, plain white otherwise,
-- which leaves the fill as it is) and the text colours that read on it.
function SlimeInfoCard.pillLook(view: SlimeLabel.View): (Color3, ColorSequence, Color3, number)
	if SlimeLabel.isRainbow(view) then
		return Color3.new(1, 1, 1), SlimePadSign.rainbow(), Theme.Ink, 1
	end
	local fill = rgb(view.rarityColor)
	if Widgets.isBright(fill) then
		return fill, ColorSequence.new(Color3.new(1, 1, 1)), Theme.Ink, 1
	end
	return fill, ColorSequence.new(Color3.new(1, 1, 1)), Theme.Text, 0
end

-- The rows shown for `count` rows (3 = not for sale, 4 = with the price), stacked top to bottom.
function SlimeInfoCard.rows(count: number): { Row }
	local total = 0
	for i = 1, count do
		total += SlimeInfoCard.ROWS[i].weight
	end
	local out: { Row } = {}
	local y = 0
	for i = 1, count do
		local h = SlimeInfoCard.ROWS[i].weight / total
		table.insert(out, { name = SlimeInfoCard.ROWS[i].name, y = y, h = h })
		y += h
	end
	return out
end

-- BillboardGui size for `count` rows; `pxScale` (default 1) scales the pixel floor, never the studs.
function SlimeInfoCard.size(count: number, pxScale: number?): UDim2
	local s = SlimeInfoCard.SIZE
	local k = pxScale or 1
	local weight = 0
	for i = 1, count do
		weight += SlimeInfoCard.ROWS[i].weight
	end
	return UDim2.new(
		s.widthStuds,
		math.floor(s.widthPx * k + 0.5),
		weight * s.rowStuds,
		math.floor(weight * s.rowPx * k + 0.5)
	)
end

-- The tag fit for a viewport `viewportHeight` px tall: the pixel floor scaled to it, and a shorter MaxDistance
-- on a small screen, where many tags at once pile up.
function SlimeInfoCard.fit(viewportHeight: number): Fit
	local s = SlimeInfoCard.SIZE
	return {
		pxScale = math.clamp(viewportHeight / s.referenceHeightPx, s.minPxScale, 1),
		maxDistance = if viewportHeight < s.smallViewportPx then s.smallMaxDistance else s.maxDistance,
	}
end

-- Screen px per stud at `distance` studs from a camera with vertical field of view `fovDegrees` on a viewport
-- `viewportHeight` px tall.
function SlimeInfoCard.pxPerStud(viewportHeight: number, fovDegrees: number, distance: number): number
	return viewportHeight / (2 * math.max(distance, 0.01) * math.tan(math.rad(fovDegrees) / 2))
end

-- The tag size drawn all in px: what `size(count, pxScale)` comes to at `pxPerStud`. A tag nearer the camera
-- than closeLimit gets this, at closeLimit's px per stud, so it stops growing.
function SlimeInfoCard.fixedSize(count: number, pxScale: number, pxPerStud: number): UDim2
	local s = SlimeInfoCard.size(count, pxScale)
	return UDim2.fromOffset(
		math.floor(s.X.Scale * pxPerStud + s.X.Offset + 0.5),
		math.floor(s.Y.Scale * pxPerStud + s.Y.Offset + 0.5)
	)
end

local DEFAULT_FIT: Fit = table.freeze(SlimeInfoCard.fit(SlimeInfoCard.SIZE.referenceHeightPx))

-- `view` without its Buy chip (the same table when it has none).
function SlimeInfoCard.unpriced(view: SlimeLabel.View): SlimeLabel.View
	if view.price == nil then
		return view
	end
	local copy = table.clone(view)
	copy.price = nil
	return copy
end

-- One tag on screen: `x` the centre of its bottom edge, `y` that edge (px, y down), `w` / `h` its px size,
-- `depth` its distance from the camera.
export type ScreenTag = { key: any, x: number, y: number, w: number, h: number, depth: number }

-- The keys of the tags to hide: nearest first, a tag whose box overlaps a tag already kept is hidden. Each box
-- is pulled in by overlapSlack per side first, so tags that only touch at their edges both stay.
function SlimeInfoCard.declutter(tags: { ScreenTag }): { [any]: boolean }
	local sorted = table.clone(tags)
	table.sort(sorted, function(a: ScreenTag, b: ScreenTag)
		return a.depth < b.depth
	end)
	local slack = SlimeInfoCard.SIZE.overlapSlack
	local kept: { { number } } = {}
	local hidden: { [any]: boolean } = {}
	for _, t in sorted do
		local dx, dy = t.w * slack, t.h * slack
		local box = { t.x - t.w / 2 + dx, t.y - t.h + dy, t.x + t.w / 2 - dx, t.y - dy }
		local clash = false
		for _, k in kept do
			if box[1] < k[3] and k[1] < box[3] and box[2] < k[4] and k[2] < box[4] then
				clash = true
				break
			end
		end
		if clash then
			hidden[t.key] = true
		else
			table.insert(kept, box)
		end
	end
	return hidden
end

-- Outlined text: the colour edged in Ink.
local function text(name: string, color: Color3, parent: Instance): TextLabel
	return create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = color,
		TextScaled = true,
		Parent = parent,
	}, {
		create("UITextSizeConstraint", { MaxTextSize = SlimeInfoCard.SIZE.maxTextSize }),
		create("UIStroke", {
			Name = "Stroke",
			Thickness = SlimeInfoCard.SIZE.stroke,
			Color = Theme.Ink,
			LineJoinMode = Enum.LineJoinMode.Round,
		}),
	})
end

-- A pill: text on a rounded fill, as wide as its text (UIAspectRatioConstraint "Fit", set on render) and
-- never wider than the tag.
local function pill(name: string, fill: Color3, color: Color3, parent: Instance): TextLabel
	local s = SlimeInfoCard.SIZE
	return create(
		"TextLabel",
		{
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = fill,
			BackgroundTransparency = 0,
			Font = Theme.Font,
			TextColor3 = color,
			TextStrokeColor3 = Theme.Ink,
			TextStrokeTransparency = 1,
			TextScaled = true,
			Parent = parent,
		},
		{
			Widgets.pill(),
			create("UIStroke", {
				Name = "Stroke",
				Thickness = s.stroke,
				Color = Theme.Ink,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			create("UIAspectRatioConstraint", { Name = "Fit", AspectRatio = 3 }),
			create("UIPadding", {
				PaddingTop = UDim.new(s.pillPad, 0),
				PaddingBottom = UDim.new(s.pillPad, 0),
			}),
			create("UITextSizeConstraint", { MaxTextSize = s.maxTextSize }),
		} :: { Instance }
	)
end

-- An empty tag (call `render` to fill it).
function SlimeInfoCard.build(): BillboardGui
	local gui = create("BillboardGui", {
		Name = SlimeInfoCard.NAME,
		Archivable = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = SlimeInfoCard.SIZE.maxDistance,
		SizeOffset = Vector2.new(0, 0.5), -- bottom edge on the anchor: the tag sits above the mesh top
		Size = SlimeInfoCard.size(3),
	})
	local tag = create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local rarity = pill("Rarity", Color3.new(1, 1, 1), Theme.Ink, tag)
	create("UIGradient", { Name = "Fill", Parent = rarity })
	text("Title", Color3.new(1, 1, 1), tag)
	text("Income", Theme.Good, tag)
	pill("Price", Theme.Ink, Theme.Gold, tag)
	return gui
end

local PILLS = table.freeze({ Rarity = true, Price = true })

-- Shows `view` on a built tag, places it `height` studs above its Adornee and sizes it for `fit` (default: a
-- referenceHeightPx viewport). A nil view hides the tag.
function SlimeInfoCard.render(gui: BillboardGui, view: SlimeLabel.View?, height: number?, fit: Fit?)
	gui.Enabled = view ~= nil
	if not view then
		return
	end
	local tag = gui:FindFirstChild("Card") :: Frame
	local count = SlimeLabel.rows(view)
	local f = fit or DEFAULT_FIT
	gui.Size = SlimeInfoCard.size(count, f.pxScale)
	gui.MaxDistance = f.maxDistance
	gui.StudsOffsetWorldSpace = Vector3.new(0, if type(height) == "number" then height else 0, 0)
	local texts: { [string]: string? } = {
		Title = view.name,
		Rarity = view.rarity,
		Income = view.income,
		Price = if view.price then `Buy {view.price}` else nil,
	}
	local shown: { [string]: Row } = {}
	for _, r in SlimeInfoCard.rows(count) do
		shown[r.name] = r
	end
	for _, spec in SlimeInfoCard.ROWS do
		local label = tag:FindFirstChild(spec.name) :: TextLabel
		local r = shown[spec.name]
		label.Visible = r ~= nil
		if r then
			local value = texts[spec.name] or ""
			label.Text = value
			if PILLS[spec.name] then
				local h = r.h * SlimeInfoCard.SIZE.pill
				label.Position = UDim2.fromScale(0.5, r.y + r.h / 2)
				label.Size = UDim2.fromScale(1, h);
				(label:FindFirstChild("Fit") :: UIAspectRatioConstraint).AspectRatio = SlimeInfoCard.pillAspect(value)
			else
				label.Position = UDim2.fromScale(0, r.y)
				label.Size = UDim2.fromScale(1, r.h)
			end
		end
	end
	local rarity = tag:FindFirstChild("Rarity") :: TextLabel
	local fill, shading, ink, strokeHidden = SlimeInfoCard.pillLook(view)
	rarity.BackgroundColor3 = fill
	rarity.TextColor3 = ink
	rarity.TextStrokeTransparency = strokeHidden
	local gradient = rarity:FindFirstChild("Fill") :: UIGradient
	gradient.Color = shading
end

-- The label attributes of a model, as SlimeLabel reads them.
function SlimeInfoCard.read(model: Instance): SlimeLabel.Attributes
	local a = SlimeLabel.ATTRIBUTES
	return {
		name = model:GetAttribute(a.name),
		tier = model:GetAttribute(a.tier),
		income = model:GetAttribute(a.income),
		price = model:GetAttribute(a.price),
		growth = model:GetAttribute(a.growth),
		boss = model:GetAttribute(a.boss),
		pad = model:GetAttribute(a.pad),
		status = model:GetAttribute(a.status),
	}
end

local WATCHED: { [string]: boolean } = {}
for _, name in SlimeLabel.ATTRIBUTES do
	WATCHED[name] = true
end
WATCHED[Constants.LABEL_HEIGHT_ATTRIBUTE] = true
WATCHED[Constants.HATCHED_AT_ATTRIBUTE] = true
WATCHED[Constants.HATCH_POPPING_ATTRIBUTE] = true
WATCHED[Constants.EGG_SMASHED_AT_ATTRIBUTE] = true

export type Options = {
	collection: CollectionService,
	tag: string,
	signParent: Instance?, -- where pad planks go; default a local Folder SIGN_FOLDER in workspace
	world: Workspace?, -- whose CurrentCamera's viewport sizes the tags; default workspace
	focus: (() -> Vector3?)?, -- where the player stands (priceDistance); default the local character, else the camera
}

type Entry = {
	body: BasePart,
	anchor: Attachment,
	gui: BillboardGui?, -- built on first need: a slime resting on a pad never has one
	conn: RBXScriptConnection,
	view: SlimeLabel.View?, -- the slime's label, nil while the tag is hidden
	shown: SlimeLabel.View?, -- what gui draws: `view`, without the Buy chip unless `priced`
	priced: boolean?, -- the player is within priceDistance, so a for-sale slime shows its Buy chip (tick)
	capped: boolean?, -- drawn at its closeLimit size (tick)
	covered: boolean?, -- behind a nearer tag on screen, so its card is hidden (tick)
	moved: RBXScriptConnection, -- AncestryChanged: the pad may only be findable once the model sits in its plot
	sign: Part?,
	signPad: BasePart?,
}

-- Labels every tagged slime model. Returns a cleanup that removes them all, and a tick for the client loop that
-- keeps tags near the camera from growing past their closeLimit size.
function SlimeInfoCard.start(opts: Options): (() -> (), () -> ())
	local cards: { [Instance]: Entry } = {}
	-- Tagged models whose Body has not replicated yet: the tag can arrive before the model's children.
	local waiting: { [Instance]: RBXScriptConnection } = {}
	local ownFolder: Folder? = nil
	local world: any = opts.world or workspace
	local camera: Camera? = nil
	local viewportConn: RBXScriptConnection? = nil
	local function viewportHeight(): number
		return if camera then camera.ViewportSize.Y else SlimeInfoCard.SIZE.referenceHeightPx
	end
	local fit: Fit = SlimeInfoCard.fit(viewportHeight())

	local function signParent(): Instance
		if opts.signParent then
			return opts.signParent
		end
		if not ownFolder then
			ownFolder = create("Folder", { Name = SlimeInfoCard.SIGN_FOLDER, Archivable = false, Parent = workspace })
		end
		return ownFolder :: Folder
	end

	local function dropSign(entry: Entry)
		if entry.sign then
			entry.sign:Destroy()
		end
		entry.sign = nil
		entry.signPad = nil
	end

	-- Sizes a shown tag for the current fit: at its closeLimit size (all px) while `capped`, else studs plus px.
	local function applySize(entry: Entry, gui: BillboardGui, view: SlimeLabel.View)
		local count = SlimeLabel.rows(view)
		local cam = camera
		if entry.capped and cam then
			local px = SlimeInfoCard.pxPerStud(cam.ViewportSize.Y, cam.FieldOfView, SlimeInfoCard.SIZE.closeLimit)
			gui.Size = SlimeInfoCard.fixedSize(count, fit.pxScale, px)
		else
			gui.Size = SlimeInfoCard.size(count, fit.pxScale)
		end
	end

	-- Renders the entry's view on its tag, with the Buy chip only while `priced`, at its current size.
	local function draw(model: Instance, entry: Entry, gui: BillboardGui)
		local view = entry.view
		local shown = if view and not entry.priced then SlimeInfoCard.unpriced(view) else view
		entry.shown = shown
		SlimeInfoCard.render(gui, shown, model:GetAttribute(Constants.LABEL_HEIGHT_ATTRIBUTE), fit)
		if shown then
			applySize(entry, gui, shown)
		end
	end

	local function refresh(model: Instance)
		local entry = cards[model]
		if not entry then
			return
		end
		local view = SlimeLabel.view(SlimeInfoCard.read(model))
		entry.view = nil
		-- A slime that just hatched keeps its label hidden until the hatch show reveals it.
		local hatchedAt = model:GetAttribute(Constants.HATCHED_AT_ATTRIBUTE)
		-- A hatching slime and a dropped wild egg that smashed (contract/mystery-egg.md 40.7) show no label.
		if
			model:GetAttribute(Constants.HATCH_POPPING_ATTRIBUTE) == true
			or model:GetAttribute(Constants.EGG_SMASHED_AT_ATTRIBUTE) ~= nil
		then
			view = nil
		elseif view and hatchedAt ~= nil and SlimeLabel.hiddenByHatch(hatchedAt, workspace:GetServerTimeNow()) then
			view = nil
			local wait = (hatchedAt :: number) + Config.MYSTERY_EGG.HATCH_REVEAL_SECONDS - workspace:GetServerTimeNow()
			task.delay(math.max(0.05, wait), function()
				refresh(model)
			end)
		end
		local pad = if view and view.pad then SlimePadSign.findPad(model, view.pad) else nil
		if view and pad then
			if entry.gui then
				SlimeInfoCard.render(entry.gui, nil, nil, fit)
			end
			if entry.signPad ~= pad then
				dropSign(entry)
				local sign = SlimePadSign.build()
				SlimePadSign.place(sign, pad, signParent())
				entry.sign = sign
				entry.signPad = pad
			end
			SlimePadSign.render(entry.sign :: Part, view)
			return
		end
		dropSign(entry)
		local gui = entry.gui
		if not gui then
			if not view then
				return
			end
			gui = SlimeInfoCard.build()
			gui.Adornee = entry.anchor
			entry.gui = gui
			entry.view = view
			draw(model, entry, gui)
			gui.Parent = entry.body
			return
		end
		entry.view = view
		draw(model, entry, gui)
	end

	local function remove(model: Instance)
		local pending = waiting[model]
		if pending then
			waiting[model] = nil
			pending:Disconnect()
		end
		local entry = cards[model]
		if entry then
			cards[model] = nil
			entry.conn:Disconnect()
			entry.moved:Disconnect()
			if entry.gui then
				entry.gui:Destroy()
			end
			dropSign(entry)
		end
	end

	local function add(model: Instance)
		if cards[model] or waiting[model] or not model:IsA("Model") then
			return
		end
		local body = model.PrimaryPart or model:FindFirstChild("Body")
		if not (body and body:IsA("BasePart")) then
			waiting[model] = model.ChildAdded:Connect(function(child: Instance)
				if child.Name == "Body" and child:IsA("BasePart") then
					waiting[model]:Disconnect()
					waiting[model] = nil
					add(model)
				end
			end)
			return
		end
		-- The tag hangs on the TagAnchor, which SlimeLifeRunner moves after the drawn slime (it never steps with the
		-- replicated Body); at the Body's centre until a rig moves it.
		local anchor = body:FindFirstChild(Constants.TAG_ANCHOR)
		if not (anchor and anchor:IsA("Attachment")) then
			local made = Instance.new("Attachment")
			made.Name = Constants.TAG_ANCHOR
			made.Archivable = false
			made.Parent = body
			anchor = made
		end
		local conn = model.AttributeChanged:Connect(function(name: string)
			if WATCHED[name] then
				refresh(model)
			end
		end)
		local moved = model.AncestryChanged:Connect(function()
			refresh(model)
		end)
		cards[model] = { body = body, anchor = anchor :: Attachment, conn = conn, moved = moved }
		refresh(model)
	end

	-- Resizes the shown tags only when the viewport's fit changes (a window drag mostly keeps it).
	local function refit()
		local nextFit = SlimeInfoCard.fit(viewportHeight())
		if nextFit.pxScale == fit.pxScale and nextFit.maxDistance == fit.maxDistance then
			return
		end
		fit = nextFit
		for _, entry in cards do
			local gui = entry.gui
			if gui then
				gui.MaxDistance = fit.maxDistance
				if entry.shown then
					applySize(entry, gui, entry.shown)
				end
			end
		end
	end
	local function watchCamera()
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		camera = world.CurrentCamera
		if camera then
			viewportConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
		end
		refit()
	end
	local cameraConn: RBXScriptConnection = world:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	local function focus(eye: Vector3): Vector3
		if opts.focus then
			return opts.focus() or eye
		end
		local player = Players.LocalPlayer
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position else eye
	end

	-- Hides (or shows again) a tag's card when it goes behind (or comes out from behind) a nearer tag.
	local function cover(entry: Entry, covered: boolean)
		if (entry.covered == true) == covered then
			return
		end
		entry.covered = covered
		local card = entry.gui and entry.gui:FindFirstChild("Card")
		if card and card:IsA("GuiObject") then
			card.Visible = not covered
		end
	end

	-- Per frame, touching a tag only when something about it changes: the Buy chip shows while the player is
	-- within priceDistance; a tag nearer the camera than closeLimit is drawn at its closeLimit size (all px); and a
	-- tag whose screen box overlaps a nearer tag's is hidden. Distances are to where the tag is drawn (its offset
	-- above the anchor).
	local function tick()
		local cam = camera
		if not cam then
			return
		end
		local eye = cam.CFrame.Position
		local at = focus(eye)
		local s = SlimeInfoCard.SIZE
		local screen: { ScreenTag } = {}
		for model, entry in cards do
			local gui, view = entry.gui, entry.view
			if gui and view and gui.Enabled then
				local spot = entry.anchor.WorldPosition + gui.StudsOffsetWorldSpace
				local priced = view.price ~= nil and (spot - at).Magnitude < s.priceDistance
				if priced ~= (entry.priced == true) then
					entry.priced = priced
					draw(model, entry, gui)
				end
				local near = (spot - eye).Magnitude < s.closeLimit
				if near ~= (entry.capped == true) then
					entry.capped = near
					applySize(entry, gui, entry.shown or view)
				end
				local point, onScreen = cam:WorldToViewportPoint(spot)
				if onScreen and point.Z <= gui.MaxDistance then
					local size = gui.Size
					local px = SlimeInfoCard.pxPerStud(cam.ViewportSize.Y, cam.FieldOfView, point.Z)
					table.insert(screen, {
						key = model,
						x = point.X,
						y = point.Y,
						w = size.X.Scale * px + size.X.Offset,
						h = size.Y.Scale * px + size.Y.Offset,
						depth = point.Z,
					})
				end
			end
		end
		local hidden = SlimeInfoCard.declutter(screen)
		for model, entry in cards do
			cover(entry, hidden[model] == true)
		end
	end

	local added = opts.collection:GetInstanceAddedSignal(opts.tag):Connect(add)
	local removed = opts.collection:GetInstanceRemovedSignal(opts.tag):Connect(remove)
	for _, model in opts.collection:GetTagged(opts.tag) do
		add(model)
	end

	return function()
		added:Disconnect()
		removed:Disconnect()
		cameraConn:Disconnect()
		if viewportConn then
			viewportConn:Disconnect()
			viewportConn = nil
		end
		for model in waiting do
			remove(model)
		end
		for model in cards do
			remove(model)
		end
		if ownFolder then
			ownFolder:Destroy()
			ownFolder = nil
		end
	end,
		tick
end

return SlimeInfoCard
