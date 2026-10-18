--!strict
--[[
	SlimeInfoCard (contract/slime-labels.md)

	One small rounded card above every slime model (tag Constants.SLIME_TAG):
	species name in the rarity colour, rarity and mutations, income per second,
	and the wild buy price or the pad growth. The server writes the values as
	model attributes; the text is Shared.SlimeLabel. Client only, nothing
	replicates.

	Cost: a BillboardGui per slime with MaxDistance (the engine culls it), sized
	in studs plus pixels so it shrinks with distance and stays readable. It is
	re-rendered only on AttributeChanged of the label attributes: no frame
	loop, no tween, no polling. Parented to the Body (Archivable false, so a
	FollowPets clone never copies it) and gone with the model or its tag.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local SlimeLabel = require(Shared:WaitForChild("SlimeLabel"))
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local SlimeInfoCard = {}

SlimeInfoCard.NAME = "SlimeInfoCard"

-- Card size: studs (shrinks with distance) plus pixels (keeps it readable far away).
SlimeInfoCard.SIZE = table.freeze({
	widthStuds = 2.2,
	widthPx = 64,
	rowStuds = 0.3, -- one weight-1 row
	rowPx = 10,
	maxDistance = 60, -- studs: hidden beyond
	padPx = 3, -- inner padding
	corner = 6,
	stroke = 1.5,
	bgTransparency = 0.2,
	maxTextSize = 22,
	lift = 0.25, -- rarity text colour mixed this far towards white, so dark rarities read on the dark card
})

-- Row weights (heights relative to one row). The name row is a bit larger.
SlimeInfoCard.ROWS = table.freeze({
	{ name = "Title", weight = 1.3 },
	{ name = "Rarity", weight = 1 },
	{ name = "Income", weight = 1 },
	{ name = "Extra", weight = 1 },
})

export type Row = { name: string, y: number, h: number } -- y / h: fractions of the card's inner height

local function hex(c: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- Rarity colour for text on the card (the stroke keeps the plain rarity colour).
function SlimeInfoCard.textColor(color: { number }): Color3
	return rgb(color):Lerp(Color3.new(1, 1, 1), SlimeInfoCard.SIZE.lift)
end

-- The rows shown for `count` rows (3 = no extra line, 4 = with it), stacked top to bottom.
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
	return UDim2.new(s.widthStuds, s.widthPx, weight * s.rowStuds, weight * s.rowPx + 2 * s.padPx)
end

-- Rich text of the rarity row: rarity in its colour, then the mutations in gold.
function SlimeInfoCard.rarityText(view: SlimeLabel.View): string
	local text = `<font color="{hex(SlimeInfoCard.textColor(view.rarityColor))}">{view.rarity}</font>`
	if view.mutation then
		text ..= ` <font color="{hex(Theme.Muted)}">·</font> <font color="{hex(Theme.Gold)}">{view.mutation}</font>`
	end
	return text
end

local function row(name: string, font: Enum.Font, color: Color3, parent: Instance): TextLabel
	return create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = font,
		TextColor3 = color,
		TextScaled = true,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Theme.Bg,
		Parent = parent,
	}, {
		create("UITextSizeConstraint", { MaxTextSize = SlimeInfoCard.SIZE.maxTextSize }),
	})
end

-- An empty card (call `render` to fill it).
function SlimeInfoCard.build(): BillboardGui
	local s = SlimeInfoCard.SIZE
	local gui = create("BillboardGui", {
		Name = SlimeInfoCard.NAME,
		Archivable = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = s.maxDistance,
		SizeOffset = Vector2.new(0, 0.5), -- bottom edge on the anchor: the card sits above the mesh top
		Size = SlimeInfoCard.size(3),
	})
	local card = create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = s.bgTransparency,
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		Widgets.corner(s.corner),
		create("UIStroke", { Name = "Stroke", Thickness = s.stroke, Color = Theme.Muted, Transparency = 0.15 }),
		Widgets.padding(s.padPx),
	})
	row("Title", Theme.Font, Theme.Text, card)
	local rarity = row("Rarity", Theme.Font, Theme.Text, card)
	rarity.RichText = true
	row("Income", Theme.Font, Theme.Accent, card)
	row("Extra", Theme.FontBody, Theme.Muted, card)
	return gui
end

-- Shows `view` on a built card and places it `height` studs above its Adornee (nil = hide the card).
function SlimeInfoCard.render(gui: BillboardGui, view: SlimeLabel.View?, height: number?)
	gui.Enabled = view ~= nil
	if not view then
		return
	end
	local card = gui:FindFirstChild("Card") :: Frame
	local count = SlimeLabel.rows(view)
	gui.Size = SlimeInfoCard.size(count)
	gui.StudsOffsetWorldSpace = Vector3.new(0, if type(height) == "number" then height else 0, 0)
	local color = rgb(view.rarityColor)
	local stroke = card:FindFirstChild("Stroke") :: UIStroke
	stroke.Color = color
	local texts: { [string]: string? } = {
		Title = view.name,
		Rarity = SlimeInfoCard.rarityText(view),
		Income = view.income,
		Extra = view.extra,
	}
	local shown: { [string]: Row } = {}
	for _, r in SlimeInfoCard.rows(count) do
		shown[r.name] = r
	end
	for _, spec in SlimeInfoCard.ROWS do
		local label = card:FindFirstChild(spec.name) :: TextLabel
		local r = shown[spec.name]
		label.Visible = r ~= nil
		if r then
			label.Position = UDim2.fromScale(0, r.y)
			label.Size = UDim2.fromScale(1, r.h)
			label.Text = texts[spec.name] or ""
		end
	end
	local title = card:FindFirstChild("Title") :: TextLabel
	title.TextColor3 = SlimeInfoCard.textColor(view.rarityColor)
	local extra = card:FindFirstChild("Extra") :: TextLabel
	extra.TextColor3 = if view.extra and string.sub(view.extra, 1, 4) == "Buy " then Theme.Gold else Theme.Muted
end

-- The label attributes of a model, as SlimeLabel reads them.
function SlimeInfoCard.read(model: Instance): SlimeLabel.Attributes
	local a = SlimeLabel.ATTRIBUTES
	return {
		name = model:GetAttribute(a.name),
		tier = model:GetAttribute(a.tier),
		mutations = model:GetAttribute(a.mutations),
		income = model:GetAttribute(a.income),
		price = model:GetAttribute(a.price),
		growth = model:GetAttribute(a.growth),
		boss = model:GetAttribute(a.boss),
	}
end

local WATCHED: { [string]: boolean } = {}
for _, name in SlimeLabel.ATTRIBUTES do
	WATCHED[name] = true
end
WATCHED[Constants.LABEL_HEIGHT_ATTRIBUTE] = true

export type Options = {
	collection: CollectionService,
	tag: string,
}

-- Draws a card on every tagged slime model. Returns a cleanup that removes them all.
function SlimeInfoCard.start(opts: Options): () -> ()
	local cards: { [Instance]: { gui: BillboardGui, conn: RBXScriptConnection } } = {}
	-- Tagged models whose Body has not replicated yet: the tag can arrive before the model's children.
	local waiting: { [Instance]: RBXScriptConnection } = {}

	local function refresh(model: Instance)
		local entry = cards[model]
		if entry then
			SlimeInfoCard.render(
				entry.gui,
				SlimeLabel.view(SlimeInfoCard.read(model)),
				model:GetAttribute(Constants.LABEL_HEIGHT_ATTRIBUTE)
			)
		end
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
			entry.gui:Destroy()
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
		gui.Adornee = body
		local conn = model.AttributeChanged:Connect(function(name: string)
			if WATCHED[name] then
				refresh(model)
			end
		end)
		cards[model] = { gui = gui, conn = conn }
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
	end
end

return SlimeInfoCard
