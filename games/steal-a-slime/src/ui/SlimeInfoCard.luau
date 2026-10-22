--!strict
--[[
	SlimeInfoCard (contract/slime-labels.md)

	The label of every slime model (tag Constants.SLIME_TAG). A wild, carried
	or escaping slime gets a floating tag above its mesh (canvas
	GooWorldLabels "Wild slime tag"), no panel: the rarity on a goo pill in
	the rarity colour (a rainbow for Secret), the species name in white
	outlined in Ink, the income per second in mint and, while it is for sale,
	a "Buy $price" chip. A slime resting on a pad (LabelPad set) shows no tag:
	its label is a goo-dipped sign on a stake in front of the pad's cork stand
	(SlimePadSign). The server writes the values as model attributes; the text
	is Shared.SlimeLabel. Client only, nothing replicates.

	Cost: a BillboardGui per slime with MaxDistance (the engine culls it), sized
	in studs plus pixels so it shrinks with distance and stays readable, and a
	plank per pad slime. Both are re-rendered only on AttributeChanged of the
	label attributes: no frame loop, no tween, no polling. The tag is parented
	to the Body (Archivable false, so a FollowPets clone never copies it); the
	planks go in one local folder. Both go with the model or its tag.
]]

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
-- rowPx * its weight px tall at the edge of maxDistance).
SlimeInfoCard.SIZE = table.freeze({
	widthStuds = 3.4,
	widthPx = 160,
	rowStuds = 0.4, -- one weight-1 row
	rowPx = 20, -- the pixel floor of a weight-1 row
	maxDistance = 60, -- studs: hidden beyond
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

-- BillboardGui size for `count` rows.
function SlimeInfoCard.size(count: number): UDim2
	local s = SlimeInfoCard.SIZE
	local weight = 0
	for i = 1, count do
		weight += SlimeInfoCard.ROWS[i].weight
	end
	return UDim2.new(s.widthStuds, s.widthPx, weight * s.rowStuds, math.floor(weight * s.rowPx + 0.5))
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

-- Shows `view` on a built tag and places it `height` studs above its Adornee (nil = hide the tag).
function SlimeInfoCard.render(gui: BillboardGui, view: SlimeLabel.View?, height: number?)
	gui.Enabled = view ~= nil
	if not view then
		return
	end
	local tag = gui:FindFirstChild("Card") :: Frame
	local count = SlimeLabel.rows(view)
	gui.Size = SlimeInfoCard.size(count)
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

export type Options = {
	collection: CollectionService,
	tag: string,
	signParent: Instance?, -- where pad planks go; default a local Folder SIGN_FOLDER in workspace
}

type Entry = {
	gui: BillboardGui,
	conn: RBXScriptConnection,
	moved: RBXScriptConnection, -- AncestryChanged: the pad may only be findable once the model sits in its plot
	sign: Part?,
	signPad: BasePart?,
}

-- Labels every tagged slime model. Returns a cleanup that removes them all.
function SlimeInfoCard.start(opts: Options): () -> ()
	local cards: { [Instance]: Entry } = {}
	-- Tagged models whose Body has not replicated yet: the tag can arrive before the model's children.
	local waiting: { [Instance]: RBXScriptConnection } = {}
	local ownFolder: Folder? = nil
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

	local function refresh(model: Instance)
		local entry = cards[model]
		if not entry then
			return
		end
		local view = SlimeLabel.view(SlimeInfoCard.read(model))
		-- A slime that just hatched keeps its label hidden until the hatch show reveals it.
		local hatchedAt = model:GetAttribute(Constants.HATCHED_AT_ATTRIBUTE)
		if model:GetAttribute(Constants.HATCH_POPPING_ATTRIBUTE) == true then
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
			SlimeInfoCard.render(entry.gui, nil, nil)
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
		SlimeInfoCard.render(entry.gui, view, model:GetAttribute(Constants.LABEL_HEIGHT_ATTRIBUTE))
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
			entry.gui:Destroy()
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
		local gui = SlimeInfoCard.build()
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
		gui.Adornee = anchor
		local conn = model.AttributeChanged:Connect(function(name: string)
			if WATCHED[name] then
				refresh(model)
			end
		end)
		local moved = model.AncestryChanged:Connect(function()
			refresh(model)
		end)
		cards[model] = { gui = gui, conn = conn, moved = moved }
		refresh(model)
		gui.Parent = body
	end

	local added = opts.collection:GetInstanceAddedSignal(opts.tag):Connect(add)
	local removed = opts.collection:GetInstanceRemovedSignal(opts.tag):Connect(remove)
	for _, model in opts.collection:GetTagged(opts.tag) do
		add(model)
	end

	return function()
		added:Disconnect()
		removed:Disconnect()
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
	end
end

return SlimeInfoCard
