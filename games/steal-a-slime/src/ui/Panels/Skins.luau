--!strict
--[[
	Plot skins panel (Nav key "Skins", contract/plot-skins.md). In the band: "n/m unlocked". In the body: the
	skins on the left, one row each (its icon, name, and a bar with the count toward unlocking it, or Equipped /
	Unlocked), and the selected skin's pane on the right (PlotSkinsView.detail): a big icon, the name, "Find 4 of
	these 5 slimes" over a bar, the slimes themselves (found in colour, the rest as silhouettes with their set or
	"Merge"), and Equip, Equipped or a well saying how many slimes are still needed. Equip asks the server
	(EquipPlotSkin); it decides nothing itself. Without State.plotSkins: one empty line.
	With State.plotBases (FEATURES.BaseShapes, contract/base-shapes.md) a strip of base buttons runs across the top:
	the building the plot stands in, apart from its skin; each says Equip, Equipped or the rebirth it unlocks at
	(PlotBasesView), and Equip asks the server (EquipPlotBase).
]]

local UI = script.Parent.Parent
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local PlotBasesView = require(UI.PlotBasesView)
local PlotSkinsView = require(UI.PlotSkinsView)
local SlimeDex = require(UI.SlimeDex)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Skins = {}

local STYLE = table.freeze({
	chip = 15,
	chipH = 26,
	listShare = 0.44, -- of the body width
	listMin = 180,
	listMax = 240,
	gap = 10,
	scrollBar = 8,
	rowH = 64,
	rowGap = 8,
	rowPad = 8,
	icon = 48,
	name = 16,
	nameH = 20,
	state = Layout.MIN_TEXT,
	bar = 10,
	selectStroke = 3,
	-- pane
	pad = 10,
	bigIcon = 88,
	title = 20,
	titleH = 24,
	line = Layout.MIN_TEXT,
	cellMin = 70,
	cellGap = 6,
	cellH = 96,
	cellImage = 44,
	cellName = Layout.MIN_TEXT,
	cellNameH = 17,
	tagH = 22,
	button = Layout.MIN_TOUCH_DESIGN,
	buttonText = 17,
	wellRadius = 11,
	-- base strip
	baseH = Layout.MIN_TOUCH_DESIGN,
	baseGap = 8,
	baseTitle = 14,
	baseState = Layout.MIN_TEXT,
})

-- The pane's slime cells: how many fit across `inner` px and how wide each is.
function Skins.cells(inner: number): (number, number)
	local columns = math.max(1, math.floor((inner + STYLE.cellGap) / (STYLE.cellMin + STYLE.cellGap)))
	return columns, math.floor((inner - STYLE.cellGap * (columns - 1)) / columns)
end

function Skins.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "SkinsPanel", "Plot skins", "🏠")
	local c = Layout.PANEL_CHROME
	local icons = ItemIcons.of(ctx)
	local builders: SlimePreview.Builders = { species = ctx.buildSpecies, slime = ctx.buildSlime }

	local summary = Widgets.chip({
		Name = "Summary",
		TextSize = STYLE.chip,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(c.close + c.closeInset * 2), 0, c.closeInset + c.close // 2),
		Size = UDim2.fromOffset(0, STYLE.chipH),
		ZIndex = 2,
		Parent = panel.frame,
	}, Theme.Text)

	-- Everything in the body hangs off `content`, which joins the body the first time the menu opens with a
	-- State: a menu nobody opened costs only its chrome (ui-perf-budget.json). It is as tall as the menu's
	-- full body, so init.client (Widgets.contentHeight) sizes this list menu to fill the window.
	local fullH = Layout.menuHeight("Skins") - c.header - c.pad
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

	local empty = Widgets.label({
		Name = "Empty",
		Text = PlotSkinsView.EMPTY,
		TextColor3 = Theme.Muted,
		TextSize = Layout.MIN_TEXT,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 40),
		Visible = false,
		Parent = content,
	})
	local strip = create("Frame", {
		Name = "Bases",
		BackgroundTransparency = 1,
		Visible = false,
		Parent = content,
	})
	local list = Widgets.scrollList({ Name = "List", Parent = content }, STYLE.rowGap)
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

	local open = false
	local latest: any = nil
	local selected: string? = nil
	local bodyW, bodyH = 536, 505
	local repaint: () -> ()

	local function listWidth(): number
		return math.clamp(math.floor(bodyW * STYLE.listShare), STYLE.listMin, STYLE.listMax)
	end

	local function placeBody()
		local lw = listWidth()
		local top = if strip.Visible then STYLE.baseH + STYLE.baseGap else 0
		strip.Size = UDim2.fromOffset(bodyW, STYLE.baseH)
		list.Position = UDim2.fromOffset(0, top)
		list.Size = UDim2.fromOffset(lw, bodyH - top)
		pane.Position = UDim2.fromOffset(lw + STYLE.gap, top)
		pane.Size = UDim2.fromOffset(bodyW - lw - STYLE.gap, bodyH - top)
	end

	-- Base buttons, reused by index.
	type BaseButton = { frame: TextButton, stroke: UIStroke, title: TextLabel, state: TextLabel }
	local baseButtons: { BaseButton } = {}
	local function baseButton(i: number): BaseButton
		local existing = baseButtons[i]
		if existing then
			return existing
		end
		local frame = create("TextButton", {
			Name = `Base{i}`,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Row,
			BorderSizePixel = 0,
			Parent = strip,
		}, { Widgets.corner(Widgets.KIT.rowRadius) }) :: TextButton
		local stroke = Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke)
		stroke.Parent = frame
		local title = Widgets.label({
			Name = "Title",
			Font = Theme.Font,
			TextSize = STYLE.baseTitle,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(4, 3),
			Size = UDim2.new(1, -8, 0.5, -2),
			Parent = frame,
		})
		local state = Widgets.label({
			Name = "State",
			Font = Theme.Font,
			TextSize = STYLE.baseState,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.new(1, -8, 0.5, -3),
			Parent = frame,
		})
		frame.Activated:Connect(function()
			local id = frame:GetAttribute("BaseId")
			if frame:GetAttribute("State") == "unlocked" and type(id) == "string" and ctx.request then
				ctx.request("EquipPlotBase", function() end, id)
			end
		end)
		local made = { frame = frame, stroke = stroke, title = title, state = state }
		baseButtons[i] = made
		return made
	end

	local function paintBases(baseRows: { PlotBasesView.Row })
		local n = #baseRows
		local w = if n > 0 then math.floor((bodyW - STYLE.baseGap * (n - 1)) / n) else 0
		for i, row in baseRows do
			local b = baseButton(i)
			local locked = row.state == "locked"
			b.frame.Visible = true
			b.frame:SetAttribute("BaseId", row.id)
			b.frame:SetAttribute("State", row.state)
			b.frame.Position = UDim2.fromOffset((i - 1) * (w + STYLE.baseGap), 0)
			b.frame.Size = UDim2.fromOffset(w, STYLE.baseH)
			b.frame.BackgroundColor3 = if row.state == "equipped" then Theme.BgLight else Theme.Row
			b.stroke.Color = if row.state == "equipped" then Theme.Good else Theme.Ink
			b.stroke.Thickness = if row.state == "equipped" then STYLE.selectStroke else Widgets.KIT.rowStroke
			b.title.Text = row.title
			b.title.TextColor3 = if locked then Theme.Muted else Theme.Text
			b.state.Text = row.action
			b.state.TextColor3 = if row.state == "equipped"
				then Theme.Good
				elseif row.state == "unlocked" then Theme.Accent
				else Theme.Muted
		end
		for i = n + 1, #baseButtons do
			baseButtons[i].frame.Visible = false
		end
	end

	local function equip(id: string)
		if ctx.request then
			ctx.request("EquipPlotSkin", function() end, id)
		end
	end

	-- Skin rows.
	local function makeRow(row: PlotSkinsView.Row): any
		local frame = create("TextButton", {
			Name = row.key,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Row,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -STYLE.scrollBar, 0, STYLE.rowH),
		}, { Widgets.corner(Widgets.KIT.rowRadius) }) :: TextButton
		local stroke = Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke)
		stroke.Parent = frame
		local image = create("Frame", {
			Name = "Image",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, STYLE.rowPad, 0.5, 0),
			Size = UDim2.fromOffset(STYLE.icon, STYLE.icon),
			Parent = frame,
		}, { Widgets.corner(Widgets.KIT.radius), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
		local icon = ItemIconView.new({
			Name = "SkinIcon",
			Id = `PlotSkin_{row.id}`,
			Size = STYLE.icon,
			Parent = image,
		}, icons)
		local textX = STYLE.rowPad * 2 + STYLE.icon
		local title = Widgets.label({
			Name = "Title",
			Font = Theme.Font,
			TextSize = STYLE.name,
			Position = UDim2.fromOffset(textX, 10),
			Size = UDim2.new(1, -(textX + STYLE.rowPad), 0, STYLE.nameH),
			Parent = frame,
		})
		local stateLabel = Widgets.label({
			Name = "State",
			Font = Theme.Font,
			TextSize = STYLE.state,
			Position = UDim2.fromOffset(textX, 10 + STYLE.nameH + 4),
			Size = UDim2.new(1, -(textX + STYLE.rowPad), 0, 18),
			Parent = frame,
		})
		local countW = 40
		local bar, setBar = Widgets.bar(
			frame,
			Theme.Good,
			UDim2.new(1, -(textX + STYLE.rowPad + countW + 6), 0, STYLE.bar),
			UDim2.fromOffset(textX, 10 + STYLE.nameH + 8)
		)
		bar.Name = "Progress"
		local count = Widgets.label({
			Name = "Count",
			Font = Theme.Font,
			TextSize = STYLE.state,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -STYLE.rowPad, 0, 10 + STYLE.nameH + 4),
			Size = UDim2.fromOffset(countW, 18),
			Parent = frame,
		})
		frame.Activated:Connect(function()
			selected = frame:GetAttribute("SkinId") :: string?
			repaint()
		end)
		return {
			instance = frame,
			stroke = stroke,
			image = image,
			icon = icon,
			title = title,
			state = stateLabel,
			bar = bar,
			setBar = setBar,
			count = count,
		}
	end

	local function updateRow(r: any, row: PlotSkinsView.Row)
		local locked = row.state == "locked"
		local on = row.id == selected
		r.instance:SetAttribute("SkinId", row.id)
		r.instance:SetAttribute("State", row.state)
		r.instance:SetAttribute("Selected", on)
		r.instance.BackgroundColor3 = if on then Theme.BgLight else Theme.Row
		r.stroke.Color = if on then Theme.Good else Theme.Ink
		r.stroke.Thickness = if on then STYLE.selectStroke else Widgets.KIT.rowStroke
		r.image.BackgroundColor3 = Widgets.color3(row.color)
		r.image.BackgroundTransparency = if locked then 0.6 else 0
		r.icon.setFrame(if locked then Theme.Muted else nil)
		r.icon.setActive(open)
		r.title.Text = row.title
		r.title.TextColor3 = if locked then Theme.Muted else Theme.Text
		r.state.Visible = not locked
		r.state.Text = if row.state == "equipped" then PlotSkinsView.EQUIPPED else "Unlocked"
		r.state.TextColor3 = if row.state == "equipped" then Theme.Good else Theme.Muted
		r.bar.Visible = locked
		r.setBar(row.fraction)
		r.count.Visible = locked
		r.count.Text = row.count
	end

	local rows = Widgets.keyedList(
		list,
		function(row: PlotSkinsView.Row)
			return row.key
		end,
		makeRow,
		function(r: any, row: PlotSkinsView.Row)
			updateRow(r, row)
		end
	)

	-- The pane: built once, its slime cells reused by index.
	local bigWell = create("Frame", {
		Name = "BigIcon",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(STYLE.bigIcon, STYLE.bigIcon),
		Parent = pane,
	}, { Widgets.corner(Widgets.KIT.panelRadius), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
	local bigIcon = ItemIconView.new({ Name = "SkinIcon", Size = STYLE.bigIcon, Parent = bigWell }, icons)
	local function paneLabel(name: string, size: number, color: Color3, font: any): TextLabel
		return Widgets.label({
			Name = name,
			[Widgets.fontKey(font)] = font,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = pane,
		})
	end
	local paneTitle = paneLabel("PaneTitle", STYLE.title, Theme.Text, Theme.Font)
	local paneLine = paneLabel("Line", STYLE.line, Theme.Muted, Theme.FontBody)
	local paneBar, setPaneBar = Widgets.bar(pane, Theme.Good, UDim2.fromOffset(0, STYLE.bar))
	paneBar.Name = "Progress"
	local paneCount = paneLabel("PaneCount", STYLE.line, Theme.Good, Theme.Font)
	local equipButton = Widgets.button(
		{
			Name = "Equip",
			Text = PlotSkinsView.EQUIP,
			TextSize = STYLE.buttonText,
			Size = UDim2.fromOffset(0, STYLE.button),
			Parent = pane,
		},
		Theme.Accent,
		function()
			if selected then
				equip(selected)
			end
		end
	)
	local well = Widgets.status({
		Name = "Well",
		TextSize = STYLE.buttonText,
		Size = UDim2.fromOffset(0, STYLE.button),
		Parent = pane,
	})
	type Cell = { frame: Frame, preview: ViewportFrame, glyph: TextLabel, name: TextLabel, tag: TextLabel }
	local cells: { Cell } = {}

	local function cell(i: number): Cell
		local existing = cells[i]
		if existing then
			return existing
		end
		local frame = create("Frame", {
			Name = `Slime{i}`,
			BackgroundColor3 = Theme.Ink,
			BackgroundTransparency = 0.45,
			Parent = pane,
		}, { Widgets.corner(16) })
		local image = create("Frame", {
			Name = "Image",
			BackgroundColor3 = Theme.BgLight,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(STYLE.cellImage, STYLE.cellImage),
			Parent = frame,
		}, { Widgets.corner(STYLE.wellRadius) })
		local preview = create("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = image,
		})
		local glyph = Widgets.label({
			Name = "Glyph",
			Text = "?",
			Font = Theme.Font,
			TextSize = 22,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = image,
		})
		local name = Widgets.label({
			Name = "Name",
			Font = Theme.Font,
			TextSize = STYLE.cellName,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(2, 6 + STYLE.cellImage + 3),
			Size = UDim2.new(1, -4, 0, STYLE.cellNameH),
			Parent = frame,
		})
		local tag = Widgets.chip({
			Name = "Tag",
			TextSize = STYLE.cellName,
			AutomaticSize = Enum.AutomaticSize.None,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6 + STYLE.cellImage + 3 + STYLE.cellNameH + 3),
			Size = UDim2.new(1, -8, 0, STYLE.tagH),
			Parent = frame,
		}, Theme.Muted)
		local made = { frame = frame, preview = preview, glyph = glyph, name = name, tag = tag }
		cells[i] = made
		return made
	end

	local function paintPane(detail: PlotSkinsView.Detail?)
		pane.Visible = detail ~= nil
		if detail == nil then
			return
		end
		local w = pane.Size.X.Offset
		local inner = math.max(w - STYLE.pad * 2, 1)
		local y = STYLE.pad
		bigWell.Position = UDim2.new(0.5, 0, 0, y)
		bigWell.BackgroundColor3 = Theme.BgLight
		if bigWell:GetAttribute("SkinId") ~= detail.id then
			bigWell:SetAttribute("SkinId", detail.id)
			bigIcon.set(`PlotSkin_{detail.id}`)
		end
		bigIcon.setFrame(if detail.state == "locked" then Theme.Muted else nil)
		bigIcon.setActive(open)
		y += STYLE.bigIcon + 6
		local function put(label: TextLabel, size: number, text: string, gapAfter: number)
			label.Text = text
			label.Visible = text ~= ""
			if text ~= "" then
				local h = math.ceil(Layout.wrappedHeight(text, size, inner, true))
				label.Position = UDim2.fromOffset(STYLE.pad, y)
				label.Size = UDim2.fromOffset(inner, h)
				y += h + gapAfter
			end
		end
		put(paneTitle, STYLE.title, detail.title, 2)
		put(paneLine, STYLE.line, detail.line, 6)
		local hasCount = detail.count ~= nil
		paneBar.Visible = hasCount
		paneCount.Visible = hasCount
		if hasCount then
			local countW = 40
			paneBar.Position = UDim2.fromOffset(STYLE.pad, y + 4)
			paneBar.Size = UDim2.fromOffset(inner - countW - 6, STYLE.bar)
			setPaneBar(detail.fraction)
			paneCount.Text = detail.count or ""
			paneCount.TextXAlignment = Enum.TextXAlignment.Right
			paneCount.Position = UDim2.fromOffset(STYLE.pad + inner - countW, y)
			paneCount.Size = UDim2.fromOffset(countW, 18)
			y += 18 + 8
		end
		local columns, cellW = Skins.cells(inner)
		for i, slime in detail.slimes do
			local cl = cell(i)
			local col = (i - 1) % columns
			local rowN = (i - 1) // columns
			cl.frame.Visible = true
			cl.frame.Position =
				UDim2.fromOffset(STYLE.pad + col * (cellW + STYLE.cellGap), y + rowN * (STYLE.cellH + STYLE.cellGap))
			cl.frame.Size = UDim2.fromOffset(cellW, STYLE.cellH)
			cl.frame:SetAttribute("Species", slime.species)
			cl.frame:SetAttribute("Found", slime.found)
			cl.name.Text = slime.title
			cl.name.TextColor3 = if slime.found then Theme.Text else Theme.Muted
			cl.tag.Text = slime.tag
			cl.tag.TextColor3 = if slime.found then Theme.Good else Theme.Muted
			if open then
				local ok = SlimePreview.mountSpecies(cl.preview, {
					key = slime.species,
					found = slime.found,
					tier = slime.tier,
					speciesColor = slime.speciesColor,
				}, builders, SlimeDex.genome)
				cl.glyph.Visible = not ok and not slime.found
			end
		end
		for i = #detail.slimes + 1, #cells do
			cells[i].frame.Visible = false
			SlimePreview.unmount(cells[i].preview)
			cells[i].preview:SetAttribute("Look", nil)
		end
		if #detail.slimes > 0 then
			local lines = math.ceil(#detail.slimes / columns)
			y += lines * STYLE.cellH + (lines - 1) * STYLE.cellGap + STYLE.pad
		end
		local canEquip = detail.state == "unlocked"
		equipButton.instance.Visible = canEquip
		well.Visible = not canEquip
		well.Text = detail.action
		well.TextColor3 = if detail.state == "equipped" then Theme.Good else Theme.Muted
		for _, inst in { equipButton.instance, well } do
			inst.Position = UDim2.fromOffset(STYLE.pad, y)
			inst.Size = UDim2.fromOffset(inner, STYLE.button)
		end
		y += STYLE.button + STYLE.pad
		pane.CanvasSize = UDim2.fromOffset(0, y)
	end

	function repaint()
		if latest == nil then
			return
		end
		local skinRows = PlotSkinsView.rows(latest.plotSkins, ctx.Config)
		empty.Visible = #skinRows == 0
		list.Visible = #skinRows > 0
		summary.Visible = #skinRows > 0
		summary.Text = PlotSkinsView.summary(skinRows)
		local known = false
		for _, row in skinRows do
			known = known or row.id == selected
		end
		if not known then
			selected = PlotSkinsView.firstSelected(skinRows)
		end
		if not open then
			return
		end
		attach()
		local baseRows = PlotBasesView.rows(latest.plotBases)
		if strip.Visible ~= (#baseRows > 0) then
			strip.Visible = #baseRows > 0
			placeBody()
		end
		paintBases(baseRows)
		rows.sync(skinRows)
		local cards = SlimeDex.cards(latest.dex, ctx.Config, function(id: string)
			local entry = if ctx.SlimeRoster then ctx.SlimeRoster.get(id) else nil
			local look = if ctx.SlimeLooks then ctx.SlimeLooks.get(id) else nil
			local set = if ctx.setName then ctx.setName(id) else nil
			return if entry then entry.name else nil, if look then look.color else nil, set
		end)
		local slimesOf = function(id: string): { string }
			local def = if ctx.PlotSkins then ctx.PlotSkins.get(id) else nil
			return if def then ctx.PlotSkins.slimes(def) else {}
		end
		paintPane(if selected then PlotSkinsView.detail(latest.plotSkins, selected, cards, slimesOf) else nil)
	end

	local self = { frame = panel.frame, close = panel.close }

	function self.setOpen(isOpen: boolean)
		open = isOpen
		for _, r in rows.rows do
			r.icon.setActive(isOpen)
		end
		bigIcon.setActive(isOpen)
		if not isOpen then
			for _, cl in cells do
				SlimePreview.unmount(cl.preview)
				cl.preview:SetAttribute("Look", nil)
				cl.preview.Visible = false
			end
		end
		repaint()
	end

	function self.layout(r: Layout.Rect)
		local body = Layout.panelBody(r)
		bodyW, bodyH = math.floor(body.w), math.floor(body.h)
		content.Size = UDim2.fromOffset(bodyW, fullH)
		placeBody()
		repaint()
	end

	-- The skin shown in the pane (tests), and picking one (the rows do the same).
	function self.selected(): string?
		return selected
	end
	function self.select(id: string)
		selected = id
		repaint()
	end

	function self.update(state: any)
		latest = state
		repaint()
	end

	placeBody()
	return self
end

return Skins
