--!strict
--[[
	SlimeDex panel (Nav key "Dex", contract/species-dex.md §36.5).

	In the band, beside the title: the completion percent and "n/m found" chips. In the body, top to bottom:
	  * the tabs (SlimeDex.tabs): Fountain, Merges, Bosses, Secrets, each with its found count; the shown one is
	    Accent jelly, the others Info;
	  * the reward line: the next species milestone and what it pays, over a bar toward it;
	  * the tab's content:
	      - a species tab: a scroll list of card lines grouped by rarity (SlimeDex.lines) on the left, each card
	        only the species mesh (a flat black silhouette while not found) and the name; the selected card's
	        side pane on the right (SlimeDex.detail): a big preview, the rarity, how to get it, its set, how many
	        are in your base and the merges it is used in, with "See merges" opening those;
	      - Merges: one line on what to do, then a scroll list of recipe rows (SlimeDex.recipes): three
	        ingredient slots ("In base" with a mint ring, "Found", or "???" and its set), then the result with
	        its status ("Ready to merge", "Need 2 more", "Made"). Ready rows have the mint ring.

	The lists are only rebuilt while the panel is open: update() while closed just marks them dirty. Previews are
	virtualised: only the cards and slots in or near the scroll window hold a mounted ViewportFrame, at most
	SlimePreview.MAX_LIVE at once. layout(rect) gets the panel box; every size follows its body.
]]

local UI = script.Parent.Parent
local Layout = require(UI.Layout)
local SlimeDex = require(UI.SlimeDex)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Dex = {}

-- Design px and text sizes of the panel's parts.
local STYLE = table.freeze({
	chip = 15,
	chipH = 26,
	chipGap = 6,
	tabH = SlimeDex.BODY.tabH,
	tabGap = 6,
	tabText = 15,
	gap = SlimeDex.BODY.gap, -- between the body's blocks
	rewardH = SlimeDex.BODY.rewardH,
	rewardPad = 12,
	rewardText = 15,
	rewardTextH = 18,
	rewardBar = 10,
	scrollBar = 10, -- list width kept free for the scroll bar
	listGap = 8,
	heading = 17,
	headingH = 24,
	cardTitle = 15,
	cardPad = 8,
	wellRadius = 11,
	glyph = 26,
	selectStroke = 3,
})

-- The side pane.
local PANE = table.freeze({
	minW = 170,
	maxW = 230,
	share = 0.4, -- of the body width
	gap = 10, -- grid to pane
	pad = 10,
	preview = 92,
	title = 19,
	titleH = 24,
	rarity = Layout.MIN_TEXT,
	rarityH = 22,
	key = Layout.MIN_TEXT,
	keyH = 17,
	value = 15,
	gapSmall = 2,
	gapBig = 10,
})

-- Merge recipe rows.
local RECIPE = table.freeze({
	h = 118,
	pad = 8,
	op = 16, -- "+" and "=" columns
	opText = 28,
	resultShare = 0.3, -- of the row's inner width
	slotH = 102,
	slotRadius = 16,
	image = 44,
	resultImage = 52,
	name = Layout.MIN_TEXT,
	nameH = 17,
	tag = Layout.MIN_TEXT,
	tagH = 22,
	statusH = 26,
	legend = Layout.MIN_TEXT,
	legendH = 20,
	legendGap = 6,
	showAllW = 110,
})

Dex.HINT = "Put all three in the Merge vat to make the slime."
Dex.SEE_MERGES = "See merges"
Dex.SHOW_ALL = "Show all"

local C = SlimeDex.CARD
local PREVIEW_MARGIN = C.h * 2 -- cards this far past the scroll window keep their preview

-- A section heading row in a list: the rarity name in its colour and the found count.
local function headingRow(name: string): any
	local frame = create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -STYLE.scrollBar, 0, STYLE.headingH),
	})
	local title = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = STYLE.heading,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, STYLE.headingH),
		Parent = frame,
	})
	local detail = Widgets.label({
		Name = "Detail",
		Font = Theme.Font,
		TextSize = Layout.MIN_TEXT,
		TextColor3 = Theme.Muted,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, STYLE.headingH),
		Parent = frame,
	})
	return { instance = frame, title = title, detail = detail }
end

-- A square preview well: a ViewportFrame over a BgLight square, and a "?" for a slot with no species.
local function previewWell(parent: Instance, size: number, name: string?): (Frame, ViewportFrame, TextLabel)
	local well = create("Frame", {
		Name = name or "Image",
		BackgroundColor3 = Theme.BgLight,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	}, { Widgets.corner(STYLE.wellRadius) })
	local viewport = create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = well,
	})
	local glyph = Widgets.label({
		Name = "Glyph",
		Text = "?",
		Font = Theme.Font,
		TextSize = STYLE.glyph,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = well,
	})
	return well, viewport, glyph
end

function Dex.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "DexPanel", "SlimeDex", "📖")
	local c = Layout.PANEL_CHROME

	-- Band chips, right to left from the close button: the found count, then the percent.
	local function bandChip(name: string, color: Color3): TextLabel
		return Widgets.chip({
			Name = name,
			TextSize = STYLE.chip,
			AnchorPoint = Vector2.new(1, 0.5),
			Size = UDim2.fromOffset(0, STYLE.chipH),
			ZIndex = 2,
			Parent = panel.frame,
		}, color)
	end
	local countChip = bandChip("Count", Theme.Text)
	local percentChip = bandChip("Percent", Theme.Good)

	-- Everything in the body hangs off `content`, which joins the body the first time the menu opens with a
	-- State: a menu nobody opened costs only its chrome (ui-perf-budget.json). It is as tall as the menu's
	-- full body, so init.client (Widgets.contentHeight) sizes this list menu to fill the window.
	local fullH = Layout.menuHeight("Dex") - c.header - c.pad
	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Layout.MENU_WIDTH, fullH),
	})
	local function attach()
		if content.Parent == nil then
			content.Parent = panel.body
		end
	end

	-- Tabs, built once for every kind; the ones without cards are hidden.
	local tabs: { [string]: any } = {}
	local currentTab = SlimeDex.TABS[1].key
	local filter: string? = nil -- Merges: only the recipes that take this species
	local selected: { [string]: string } = {} -- species tab -> selected card key
	local rebuildNow: () -> ()

	local function setTab(key: string, only: string?)
		currentTab = key
		filter = only
		rebuildNow()
	end

	for _, def in SlimeDex.TABS do
		local tab = Widgets.button(
			{
				Name = `Tab_{def.key}`,
				Text = def.label,
				TextSize = STYLE.tabText,
				Size = UDim2.fromOffset(0, STYLE.tabH),
				Parent = content,
			},
			Theme.Info,
			function()
				setTab(def.key, nil)
			end
		)
		tab.instance.Parent = content
		tabs[def.key] = tab
	end

	-- The reward line.
	local reward = Widgets.rowFrame({
		Name = "Reward",
		Visible = false,
		Size = UDim2.new(1, 0, 0, STYLE.rewardH),
		Parent = content,
	})
	local rewardText = Widgets.label({
		Name = "RewardText",
		Font = Theme.Font,
		TextSize = STYLE.rewardText,
		Position = UDim2.fromOffset(STYLE.rewardPad, 4),
		Size = UDim2.new(1, -STYLE.rewardPad * 2 - 56, 0, STYLE.rewardTextH),
		Parent = reward,
	})
	local rewardCount = Widgets.label({
		Name = "RewardCount",
		Font = Theme.Font,
		TextSize = STYLE.rewardText,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -STYLE.rewardPad, 0, 4),
		Size = UDim2.fromOffset(56, STYLE.rewardTextH),
		Parent = reward,
	})
	local rewardBar, setRewardBar = Widgets.bar(
		reward,
		Theme.Gold,
		UDim2.new(1, -STYLE.rewardPad * 2, 0, STYLE.rewardBar),
		UDim2.fromOffset(STYLE.rewardPad, 4 + STYLE.rewardTextH + 6)
	)
	rewardBar.Name = "RewardBar"

	-- Species tabs: the card grid and the side pane.
	local list = Widgets.scrollList({ Name = "List", Parent = content }, STYLE.listGap)
	local pane = Widgets.scroll({
		Name = "Pane",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Row,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollBarThickness = 4,
		Parent = content,
	})
	Widgets.corner(Widgets.KIT.rowRadius).Parent = pane
	Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke).Parent = pane
	local paneWell, paneView, paneGlyph = previewWell(pane, PANE.preview, "PaneImage")
	local function paneLabel(name: string, size: number, color: Color3, font: any): TextLabel
		return Widgets.label({
			Name = name,
			[Widgets.fontKey(font)] = font,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = pane,
		})
	end
	local paneTitle = paneLabel("PaneTitle", PANE.title, Theme.Text, Theme.Font)
	paneTitle.TextXAlignment = Enum.TextXAlignment.Center
	local paneRarity = Widgets.chip({
		Name = "PaneRarity",
		TextSize = PANE.rarity,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(0, PANE.rarityH),
		Parent = pane,
	}, Theme.Ink)
	Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke).Parent = paneRarity
	local facts: { { key: TextLabel, value: TextLabel } } = {}
	for i, name in { "How", "Set", "Have", "UsedIn" } do
		facts[i] = {
			key = paneLabel(`{name}Key`, PANE.key, Theme.Muted, Theme.Font),
			value = paneLabel(name, PANE.value, Theme.Text, Theme.FontBody),
		}
	end
	local seeMerges = Widgets.button(
		{
			Name = "SeeMerges",
			Text = Dex.SEE_MERGES,
			TextSize = STYLE.tabText,
			Size = UDim2.fromOffset(0, STYLE.tabH),
			Parent = pane,
		},
		Theme.Info,
		function()
			local id = selected[currentTab]
			if id then
				setTab(SlimeDex.MERGES, id)
			end
		end
	)

	-- Merges tab: the line on what to do (or the filter and Show all), then the recipe rows.
	local legend = Widgets.label({
		Name = "Legend",
		TextSize = RECIPE.legend,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, 0, 0, RECIPE.legendH),
		Parent = content,
	})
	local showAll = Widgets.button(
		{
			Name = "ShowAll",
			Text = Dex.SHOW_ALL,
			TextSize = STYLE.tabText,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(RECIPE.showAllW, STYLE.tabH),
			Parent = content,
		},
		Theme.Info,
		function()
			setTab(SlimeDex.MERGES, nil)
		end
	)
	local recipeList = Widgets.scrollList({ Name = "Recipes", Parent = content }, STYLE.listGap)

	local open = false

	-- Species name, colour and set for slots, previews and the pane.
	local function lookup(id: string): (string?, { number }?, string?)
		local entry = if ctx.SlimeRoster then ctx.SlimeRoster.get(id) else nil
		local look = if ctx.SlimeLooks then ctx.SlimeLooks.get(id) else nil
		local set = if ctx.setName then ctx.setName(id) else nil
		return if entry then entry.name else nil, if look then look.color else nil, set
	end

	-- Body box from layout(); nil = wide and tall enough for everything.
	local bodyW: number = 536
	local bodyH: number = 505

	local function contentTop(): number
		return SlimeDex.contentTop(reward.Visible)
	end

	local function paneWidth(): number
		return math.clamp(math.floor(bodyW * PANE.share), PANE.minW, PANE.maxW)
	end

	local function gridWidth(): number
		return math.max(C.minW, bodyW - paneWidth() - PANE.gap)
	end

	local function grid(): SlimeDex.Grid
		return SlimeDex.grid(gridWidth() - STYLE.scrollBar)
	end

	-- Chips in the band, right to left from the close button.
	local function placeChips()
		local x = -(c.close + c.closeInset * 2)
		for _, chip in { countChip, percentChip } do
			local w = math.ceil(Layout.lineWidth(chip.Text, STYLE.chip, true)) + 20
			chip.Size = UDim2.fromOffset(w, STYLE.chipH)
			chip.Position = UDim2.new(1, x, 0, c.closeInset + c.close // 2)
			x -= w + STYLE.chipGap
		end
	end

	-- Every block's box for the current tab and body.
	local function placeBody()
		local shown: { any } = {}
		for _, def in SlimeDex.TABS do
			if tabs[def.key].instance.Visible then
				table.insert(shown, tabs[def.key])
			end
		end
		local n = math.max(#shown, 1)
		local tabW = math.floor((bodyW - STYLE.tabGap * (n - 1)) / n)
		for i, tab in shown do
			tab.instance.Position = UDim2.fromOffset((i - 1) * (tabW + STYLE.tabGap), 0)
			tab.instance.Size = UDim2.fromOffset(tabW, STYLE.tabH)
		end
		reward.Position = UDim2.fromOffset(0, STYLE.tabH + STYLE.gap)
		local top = contentTop()
		local height = math.max(bodyH - top, 0)
		local merges = currentTab == SlimeDex.MERGES
		list.Visible = not merges
		pane.Visible = not merges
		legend.Visible = merges
		showAll.instance.Visible = merges and filter ~= nil
		recipeList.Visible = merges
		local gw = gridWidth()
		list.Position = UDim2.fromOffset(0, top)
		list.Size = UDim2.fromOffset(gw, height)
		pane.Position = UDim2.fromOffset(gw + PANE.gap, top)
		pane.Size = UDim2.fromOffset(bodyW - gw - PANE.gap, height)
		local legendH = if filter then STYLE.tabH else RECIPE.legendH
		legend.Position = UDim2.fromOffset(0, top + (legendH - RECIPE.legendH) // 2)
		legend.Size = UDim2.fromOffset(bodyW - (if filter then RECIPE.showAllW + STYLE.gap else 0), RECIPE.legendH)
		showAll.instance.Position = UDim2.new(1, 0, 0, top)
		recipeList.Position = UDim2.fromOffset(0, top + legendH + RECIPE.legendGap)
		recipeList.Size = UDim2.fromOffset(bodyW, math.max(height - legendH - RECIPE.legendGap, 0))
	end

	-------------------------------------------------------------------------------------------------------------
	-- Previews: every mesh well in both lists and the pane. A well is mounted only while it is in or near its
	-- list's scroll window (the pane's always), at most SlimePreview.MAX_LIVE at once.
	type Look = SlimePreview.SpeciesLook
	local builders: SlimePreview.Builders = { species = ctx.buildSpecies, slime = ctx.buildSlime }
	type Well = {
		viewport: ViewportFrame,
		glyph: TextLabel,
		order: number, -- creation order: ties in the nearest-first sort go to the earlier well
		look: Look?,
		list: ScrollingFrame?,
		row: GuiObject?,
	}
	local wellCount = 0
	local wells: { [ViewportFrame]: Well } = {}

	local function mountLook(w: Well)
		local look = w.look
		if look == nil then
			return
		end
		local ok = SlimePreview.mountSpecies(w.viewport, look, builders, SlimeDex.genome)
		w.glyph.Visible = not ok and not look.found
	end

	local function unmountLook(w: Well)
		if w.viewport:GetAttribute("Look") ~= nil then
			SlimePreview.unmount(w.viewport)
			w.viewport:SetAttribute("Look", nil)
		end
		w.viewport.Visible = false
		w.glyph.Visible = w.look == nil or not w.look.found
	end

	-- Points a well at a species (nil = an unknown slot: the "?" glyph).
	local function setLook(
		viewport: ViewportFrame,
		glyph: TextLabel,
		look: Look?,
		owner: ScrollingFrame?,
		row: GuiObject?
	)
		local w = wells[viewport]
		if w == nil then
			wellCount += 1
			w = { viewport = viewport, glyph = glyph, order = wellCount }
			wells[viewport] = w
		end
		-- A changed look is remounted in place by the next refresh (the viewport keeps its WorldModel).
		w.look, w.list, w.row = look, owner, row
		if look == nil then
			unmountLook(w)
		end
	end

	local function viewHeight(frame: ScrollingFrame): number
		-- From the frame's offset size (set by placeBody), not AbsoluteSize: that is 0 until the first layout pass.
		return math.max(frame.Size.Y.Offset, C.h)
	end

	local function refreshPreviews()
		if not open then
			return -- a closed menu keeps what it showed; nothing new is mounted
		end
		local near: { { w: Well, dist: number } } = {}
		for viewport, w in wells do
			if viewport.Parent == nil then
				wells[viewport] = nil
				continue
			end
			local frame = w.list
			if w.look == nil then
				unmountLook(w)
			elseif frame == nil then
				if pane.Visible then
					table.insert(near, { w = w, dist = -1 })
				else
					unmountLook(w)
				end
			else
				local row = w.row
				local y = if row and row.Parent == frame then row.Position.Y.Offset else nil
				local top = frame.CanvasPosition.Y - PREVIEW_MARGIN
				local bottom = frame.CanvasPosition.Y + viewHeight(frame) + PREVIEW_MARGIN
				if frame.Visible and y and y + C.h > top and y < bottom then
					table.insert(near, { w = w, dist = math.abs(y + C.h / 2 - (top + bottom) / 2) })
				else
					unmountLook(w)
				end
			end
		end
		table.sort(near, function(a, b)
			if a.dist ~= b.dist then
				return a.dist < b.dist
			end
			return a.w.order < b.w.order
		end)
		for i, entry in near do
			if i <= SlimePreview.MAX_LIVE then
				mountLook(entry.w)
			else
				unmountLook(entry.w)
			end
		end
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshPreviews)
	recipeList:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshPreviews)

	-------------------------------------------------------------------------------------------------------------
	-- Species cards: kept across rebuilds (keyed by species id) and moved between lines.
	local cardViews: { [string]: any } = {}
	local paintSelection: () -> ()
	local selectCard: (id: string) -> ()

	local function makeCard(card: SlimeDex.Card): any
		local frame = create("TextButton", {
			Name = card.key,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Row,
			BorderSizePixel = 0,
		}, { Widgets.corner(Widgets.KIT.rowRadius) }) :: TextButton
		local stroke = Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke)
		stroke.Parent = frame
		local image, viewport, glyph = previewWell(frame, C.preview)
		image.AnchorPoint = Vector2.new(0.5, 0)
		image.Position = UDim2.new(0.5, 0, 0, STYLE.cardPad)
		local title = Widgets.label({
			Name = "Title",
			Font = Theme.Font,
			TextSize = STYLE.cardTitle,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(4, STYLE.cardPad + C.preview + 8),
			Size = UDim2.new(1, -8, 0, 20),
			Parent = frame,
		})
		frame.Activated:Connect(function()
			selectCard(frame.Name)
		end)
		return {
			instance = frame,
			stroke = stroke,
			image = image,
			preview = viewport,
			glyph = glyph,
			title = title,
			card = card,
		}
	end

	local function updateCard(v: any, card: SlimeDex.Card, line: GuiObject)
		v.card = card
		v.instance:SetAttribute("Found", card.found)
		v.instance:SetAttribute("Kind", card.kind)
		v.title.Text = card.title
		v.title.TextColor3 = if card.found then Theme.Text else Theme.Muted
		setLook(
			v.preview,
			v.glyph,
			{ key = card.key, found = card.found, tier = card.tier, speciesColor = card.speciesColor },
			list,
			line
		)
	end

	local function sizeCard(v: any, g: SlimeDex.Grid, column: number)
		v.instance.Size = UDim2.fromOffset(g.cardW, g.cardH)
		v.instance.Position = UDim2.fromOffset((column - 1) * (g.cardW + g.gap), 0)
	end

	type Item = { key: string, line: SlimeDex.Line }
	local rows = Widgets.keyedList(list, function(item: Item)
		return item.key
	end, function(item: Item)
		if item.line.kind == "header" then
			return headingRow(item.key)
		end
		local frame = create("Frame", {
			Name = item.key,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -STYLE.scrollBar, 0, C.h),
		})
		return { instance = frame }
	end, function(r: any, item: Item)
		local line = item.line
		if line.kind == "header" then
			local rarity = ctx.Config.RARITIES[line.tier]
			r.title.Text = line.title or ""
			r.title.TextColor3 = if rarity then Widgets.color3(rarity.color) else Theme.Gold
			r.detail.Text = line.detail or ""
			r.detail.Position = UDim2.fromOffset(math.ceil(Layout.lineWidth(r.title.Text, STYLE.heading, true)) + 10, 0)
			return
		end
		local g = grid()
		r.instance.Size = UDim2.new(1, -STYLE.scrollBar, 0, g.cardH)
		for column, card in line.cards or {} do
			local v = cardViews[card.key]
			if v == nil then
				v = makeCard(card)
				cardViews[card.key] = v
			end
			v.instance.Parent = r.instance
			sizeCard(v, g, column)
			updateCard(v, card, r.instance)
		end
	end)

	-------------------------------------------------------------------------------------------------------------
	-- The side pane for the selected card.
	local pendingCards: { SlimeDex.Card } = {}
	local inBase: { [string]: number } = {}

	local function placePane(detail: SlimeDex.Detail?)
		local w = pane.Size.X.Offset
		local inner = math.max(w - PANE.pad * 2, 1)
		for _, child in pane:GetChildren() do
			if child:IsA("GuiObject") then
				(child :: GuiObject).Visible = detail ~= nil
			end
		end
		if detail == nil then
			pane.CanvasSize = UDim2.new()
			return
		end
		local y = PANE.pad
		paneWell.AnchorPoint = Vector2.new(0.5, 0)
		paneWell.Position = UDim2.new(0.5, 0, 0, y)
		y += PANE.preview + PANE.gapSmall * 3
		local function put(label: TextLabel, size: number, text: string, gapAfter: number)
			label.Text = text
			label.Visible = text ~= ""
			if text ~= "" then
				local h = math.ceil(Layout.wrappedHeight(text, size, inner, true))
				label.Position = UDim2.fromOffset(PANE.pad, y)
				label.Size = UDim2.fromOffset(inner, h)
				y += h + gapAfter
			end
		end
		put(paneTitle, PANE.title, detail.title, PANE.gapSmall)
		paneRarity.Text = detail.rarity
		paneRarity.BackgroundColor3 = Widgets.color3(detail.rarityColor)
		Widgets.inkOn(paneRarity, paneRarity.BackgroundColor3)
		paneRarity.Position = UDim2.new(0.5, 0, 0, y)
		y += PANE.rarityH + PANE.gapBig
		local names = {}
		for _, used in detail.usedIn do
			table.insert(names, used.title)
		end
		local values = {
			{ "How to get it", detail.how },
			{ "Set", detail.set or "" },
			{ "You have", detail.have },
			{ "Used in merges", table.concat(names, ", ") },
		}
		for i, fact in facts do
			local text = values[i][2]
			fact.key.Visible = text ~= ""
			if text ~= "" then
				put(fact.key, PANE.key, values[i][1], PANE.gapSmall)
				put(fact.value, PANE.value, text, PANE.gapBig)
			else
				fact.value.Visible = false
			end
		end
		facts[3].value.TextColor3 = if (inBase[detail.key] or 0) > 0 then Theme.Good else Theme.Text
		seeMerges.instance.Visible = #detail.usedIn > 0
		if #detail.usedIn > 0 then
			seeMerges.instance.Position = UDim2.fromOffset(PANE.pad, y)
			seeMerges.instance.Size = UDim2.fromOffset(inner, STYLE.tabH)
			y += STYLE.tabH + PANE.pad
		end
		pane.CanvasSize = UDim2.fromOffset(0, y)
	end

	local function selectedCard(): SlimeDex.Card?
		local id = selected[currentTab]
		for _, card in pendingCards do
			if card.key == id and card.kind == currentTab then
				return card
			end
		end
		return nil
	end

	function paintSelection()
		local card = selectedCard()
		for key, v in cardViews do
			local on = card ~= nil and key == card.key
			v.instance:SetAttribute("Selected", on)
			v.instance.BackgroundColor3 = if on then Theme.BgLight else Theme.Row
			v.stroke.Color = if on then Theme.Good else Theme.Ink
			v.stroke.Thickness = if on then STYLE.selectStroke else Widgets.KIT.rowStroke
		end
		if card then
			setLook(
				paneView,
				paneGlyph,
				{ key = card.key, found = card.found, tier = card.tier, speciesColor = card.speciesColor },
				nil,
				nil
			)
			placePane(SlimeDex.detail(card, pendingCards, inBase, ctx.Config))
		else
			setLook(paneView, paneGlyph, nil, nil, nil)
			placePane(nil)
		end
	end

	-------------------------------------------------------------------------------------------------------------
	-- Merge recipe rows.
	local function makeRecipe(recipe: SlimeDex.Recipe): any
		local frame = Widgets.rowFrame({
			Name = recipe.key,
			Size = UDim2.new(1, -STYLE.scrollBar, 0, RECIPE.h),
		})
		local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
		local function op(name: string, text: string): TextLabel
			return Widgets.label({
				Name = name,
				Text = text,
				Font = Theme.Font,
				TextSize = RECIPE.opText,
				TextColor3 = Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.None,
				Size = UDim2.fromOffset(RECIPE.op, RECIPE.h),
				Parent = frame,
			})
		end
		local slots = {}
		for i = 1, 3 do
			local slot = create("Frame", {
				Name = `Slot{i}`,
				BackgroundColor3 = Theme.Ink,
				BackgroundTransparency = 0.45,
				Size = UDim2.fromOffset(0, RECIPE.slotH),
				Position = UDim2.fromOffset(0, (RECIPE.h - RECIPE.slotH) // 2),
				Parent = frame,
			}, { Widgets.corner(RECIPE.slotRadius) })
			local ring = Widgets.stroke(Theme.Good, STYLE.selectStroke)
			ring.Parent = slot
			local image, viewport, glyph = previewWell(slot, RECIPE.image)
			image.AnchorPoint = Vector2.new(0.5, 0)
			image.Position = UDim2.new(0.5, 0, 0, 6)
			local name = Widgets.label({
				Name = "Name",
				Font = Theme.Font,
				TextSize = RECIPE.name,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(2, 6 + RECIPE.image + 3),
				Size = UDim2.new(1, -4, 0, RECIPE.nameH),
				Parent = slot,
			})
			local tag = Widgets.chip({
				Name = "Tag",
				TextSize = RECIPE.tag,
				AutomaticSize = Enum.AutomaticSize.None,
				TextTruncate = Enum.TextTruncate.AtEnd,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 6 + RECIPE.image + 3 + RECIPE.nameH + 4),
				Size = UDim2.new(1, -8, 0, RECIPE.tagH),
				Parent = slot,
			}, Theme.Muted)
			slots[i] = { frame = slot, ring = ring, preview = viewport, glyph = glyph, name = name, tag = tag }
		end
		local plus1, plus2, equals = op("Plus1", "+"), op("Plus2", "+"), op("Equals", "=")
		local result = create("Frame", {
			Name = "Result",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, RECIPE.slotH),
			Position = UDim2.fromOffset(0, (RECIPE.h - RECIPE.slotH) // 2),
			Parent = frame,
		})
		local resultImage, resultView, resultGlyph = previewWell(result, RECIPE.resultImage)
		resultImage.AnchorPoint = Vector2.new(0.5, 0)
		resultImage.Position = UDim2.fromScale(0.5, 0)
		local resultName = Widgets.label({
			Name = "Name",
			Font = Theme.Font,
			TextSize = RECIPE.name + 1,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, RECIPE.resultImage + 2),
			Size = UDim2.new(1, 0, 0, RECIPE.nameH + 1),
			Parent = result,
		})
		local status = Widgets.status({
			Name = "Status",
			TextSize = RECIPE.tag,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.new(1, -6, 0, RECIPE.statusH),
			Parent = result,
		})
		return {
			instance = frame,
			stroke = stroke,
			slots = slots,
			ops = { plus1, plus2, equals },
			result = result,
			resultView = resultView,
			resultGlyph = resultGlyph,
			resultName = resultName,
			status = status,
		}
	end

	local function placeRecipe(r: any)
		local inner = bodyW - STYLE.scrollBar - RECIPE.pad * 2
		local resultW = math.floor(inner * RECIPE.resultShare)
		local slotW = math.max(math.floor((inner - resultW - RECIPE.op * 3) / 3), 1)
		local x = RECIPE.pad
		for i, slot in r.slots do
			slot.frame.Position = UDim2.fromOffset(x, slot.frame.Position.Y.Offset)
			slot.frame.Size = UDim2.fromOffset(slotW, RECIPE.slotH)
			x += slotW
			local opLabel = r.ops[i]
			opLabel.Position = UDim2.fromOffset(x, 0)
			x += RECIPE.op
		end
		r.result.Position = UDim2.fromOffset(x, r.result.Position.Y.Offset)
		r.result.Size = UDim2.fromOffset(inner + RECIPE.pad - x, RECIPE.slotH)
	end

	local function updateRecipe(r: any, recipe: SlimeDex.Recipe)
		r.instance:SetAttribute("Status", recipe.status)
		local ready = recipe.status == "ready"
		r.instance.BackgroundColor3 = if ready then Theme.BgLight else Theme.Row
		r.stroke.Color = if ready then Theme.Good else Theme.Ink
		r.stroke.Thickness = if ready then STYLE.selectStroke else Widgets.KIT.rowStroke
		for i, slot in r.slots do
			local s = recipe.slots[i]
			slot.frame:SetAttribute("State", s.state)
			slot.frame:SetAttribute("Species", s.species)
			slot.ring.Enabled = s.state == "base"
			slot.name.Text = s.label
			slot.name.TextColor3 = if s.species then Theme.Text else Theme.Muted
			slot.tag.Text = s.tag
			slot.tag.TextColor3 = if s.state == "base" then Theme.Good else Theme.Muted
			local look: Look? = nil
			if s.species then
				local _, color = lookup(s.species)
				local entry = if ctx.SlimeRoster then ctx.SlimeRoster.get(s.species) else nil
				look = {
					key = s.species,
					found = true,
					tier = if entry then entry.tier else recipe.result.tier,
					speciesColor = color or s.color,
				}
			end
			setLook(slot.preview, slot.glyph, look, recipeList, r.instance)
		end
		local card = recipe.result
		r.resultName.Text = card.title
		r.resultName.TextColor3 = if card.found then Widgets.color3(card.color) else Theme.Text
		setLook(
			r.resultView,
			r.resultGlyph,
			{ key = card.key, found = card.found, tier = card.tier, speciesColor = card.speciesColor },
			recipeList,
			r.instance
		)
		r.status.Text = recipe.statusText
		r.status.TextColor3 = if recipe.status == "need" then Theme.Muted else Theme.Good
		placeRecipe(r)
	end

	local recipeRows = Widgets.keyedList(
		recipeList,
		function(recipe: SlimeDex.Recipe)
			return recipe.key
		end,
		makeRecipe,
		function(r: any, recipe: SlimeDex.Recipe)
			updateRecipe(r, recipe)
		end
	)

	-------------------------------------------------------------------------------------------------------------
	-- Rebuilds: only while open, and only when what the lists show changed.
	local pendingSignature: string? = nil
	local builtSignature: string? = nil
	local dirty = true
	local hasState = false -- nothing to build before the first State
	local builds = 0

	local function shownTabs()
		local present: { [string]: boolean } = {}
		for _, tab in SlimeDex.tabs(pendingCards) do
			present[tab.key] = true
		end
		return present
	end

	-- The tab to show: the current one if it has cards, else the first that does.
	local function validTab()
		local present = shownTabs()
		if present[currentTab] then
			return
		end
		for _, def in SlimeDex.TABS do
			if present[def.key] then
				currentTab = def.key
				filter = nil
				return
			end
		end
	end

	local function signature(): string
		local parts = table.create(#pendingCards + 4)
		table.insert(parts, `{currentTab}|{filter or ""}|{bodyW}|{grid().columns}`)
		for _, card in pendingCards do
			local slots = {}
			for _, slot in card.slots or {} do
				table.insert(slots, `{slot.species or ""}:{slot.set or ""}`)
			end
			table.insert(
				parts,
				`{card.key}|{card.found}|{card.title}|{inBase[card.key] or 0}|{table.concat(slots, ",")}`
			)
		end
		return table.concat(parts, "\n")
	end

	local function paintTabs()
		local present = shownTabs()
		for _, tab in SlimeDex.tabs(pendingCards) do
			local t = tabs[tab.key]
			t.setText(`{tab.label}\n{tab.count}`)
		end
		for key, t in tabs do
			t.instance.Visible = present[key] == true
			t.setColor(if key == currentTab then Theme.Accent else Theme.Info)
			t.instance:SetAttribute("Selected", key == currentTab)
		end
	end

	local function rebuild()
		if not (open and dirty and hasState) then
			return
		end
		dirty = false
		builtSignature = pendingSignature
		builds += 1
		attach()
		paintTabs()
		placeBody()
		if currentTab == SlimeDex.MERGES then
			local recipes = SlimeDex.recipes(pendingCards, inBase, filter)
			recipeRows.sync(recipes)
			local name = nil
			for _, card in pendingCards do
				if card.key == filter then
					name = card.title
				end
			end
			legend.Text = if name then `Merges with {name}` else Dex.HINT
		else
			local cards = SlimeDex.ofKind(pendingCards, currentTab)
			if selectedCard() == nil then
				local first: SlimeDex.Card? = nil
				for _, card in cards do
					if card.found then
						first = card
						break
					end
				end
				first = first or cards[1]
				if first then
					selected[currentTab] = first.key
				end
			end
			local items: { Item } = {}
			for _, line in SlimeDex.lines(cards, grid().columns, ctx.Config) do
				table.insert(items, { key = line.key, line = line })
			end
			rows.sync(items)
			-- Cards of other tabs leave the grid (kept for when their tab comes back).
			local shown: { [string]: boolean } = {}
			for _, card in cards do
				shown[card.key] = true
			end
			for key, v in cardViews do
				if not shown[key] then
					v.instance.Parent = nil
				end
			end
			paintSelection()
		end
		refreshPreviews()
	end

	local function markDirty()
		validTab()
		pendingSignature = signature()
		dirty = pendingSignature ~= builtSignature
		rebuild()
	end

	function rebuildNow()
		list.CanvasPosition = Vector2.zero
		recipeList.CanvasPosition = Vector2.zero
		markDirty()
	end

	function selectCard(id: string)
		selected[currentTab] = id
		paintSelection()
		refreshPreviews()
	end

	local self = { frame = panel.frame, close = panel.close }

	-- Called by init.client when the menu opens / closes.
	function self.setOpen(isOpen: boolean)
		open = isOpen
		rebuild()
		refreshPreviews()
	end

	-- Called by init.client with the panel box (Layout.panelFor).
	function self.layout(r: Layout.Rect)
		local body = Layout.panelBody(r)
		bodyH, bodyW = math.floor(body.h), math.floor(body.w)
		content.Size = UDim2.fromOffset(bodyW, fullH)
		placeChips()
		placeBody()
		markDirty() -- the column count and row sizes follow the width
	end

	-- Live (mounted) previews now, and a manual refresh (tests).
	function self.liveCount(): number
		local n = 0
		for viewport in wells do
			if viewport:GetAttribute("Look") ~= nil then
				n += 1
			end
		end
		return n
	end
	self.refreshPreviews = refreshPreviews

	-- How many times the lists were rebuilt (tests).
	function self.builds(): number
		return builds
	end

	-- The grid the cards use now (tests).
	function self.grid(): SlimeDex.Grid
		return grid()
	end

	-- The tab shown, and switching it (tests; the tab buttons do the same).
	function self.tab(): string
		return currentTab
	end
	function self.selectTab(key: string, only: string?)
		setTab(key, only)
	end
	function self.select(id: string)
		selectCard(id)
	end

	function self.update(state: any)
		local summary = SlimeDex.summary(state.dex)
		percentChip.Text = summary.percent
		countChip.Text = summary.count
		placeChips()
		local line = SlimeDex.rewardLine(state)
		local hadReward = reward.Visible
		reward.Visible = line ~= nil
		if line then
			rewardText.Text = line.text
			rewardCount.Text = line.count or ""
			setRewardBar(line.fraction)
		end
		if hadReward ~= reward.Visible then
			placeBody()
		end
		hasState = true
		pendingCards = SlimeDex.cards(state.dex, ctx.Config, lookup)
		inBase = SlimeDex.inBase(state.slimes)
		markDirty()
	end

	return self
end

return Dex
