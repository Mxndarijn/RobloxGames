--!strict
--[[
	Skins menu (Nav key "Skins"). Two tabs under the band: Base (plot skins, contract/plot-skins.md) and Cloud (pet
	seats, contract/pet-seats.md); it opens on Base. In the band: "n/m unlocked" for the open tab.
	Base: the skins on the left, one row each (its icon, name, and a bar with the count toward unlocking it, or Equipped /
	Unlocked), and the selected skin's pane on the right (PlotSkinsView.detail): a big icon, the name, "Find 4 of
	these 5 slimes" over a bar, the slimes themselves (found in colour, the rest as silhouettes with their set or
	"Merge"), and Equip, Equipped or a well saying how many slimes are still needed. Equip asks the server
	(EquipPlotSkin); it decides nothing itself. Without State.plotSkins: one empty line.
	Cloud (PetSeatsView): one row per seat (its icon, name, and Equipped / Unlocked, or its unlock in one line with a
	bar and count, or a gold Exclusive tag with "Only in the Exclusive shop."), and the selected seat's pane: a big
	icon, the name, "How to unlock" / "How to get it" with the same line, the bar, and Equip, Equipped or a well
	saying what is missing or "Exclusive shop". Equip asks the server (EquipPetSeat). With the Exclusive shop on
	(State.exclusiveShop) that last one is a button: it opens the shop on that seat (ctx.openExclusiveShop).
	With State.plotBases (FEATURES.BaseShapes, contract/base-shapes.md) a strip of base buttons runs across the top:
	the building the plot stands in, apart from its skin; each says Equip, Equipped or the rebirth it unlocks at
	(PlotBasesView), and Equip asks the server (EquipPlotBase). An Exclusive base not owned yet carries a gold
	"Exclusive" tag and "Buy · R$<price>": Buy opens Roblox's prompt (ctx.purchase), or the Exclusive shop on that base
	while it is not on sale. More bases than fit in one row take two rows (Skins.baseGrid), scrolling sideways when
	two rows are not enough.
]]

local UI = script.Parent.Parent
local ExclusiveShopView = require(UI.ExclusiveShopView)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local PetSeatsView = require(UI.PetSeatsView)
local PlotBasesView = require(UI.PlotBasesView)
local PlotSkinsView = require(UI.PlotSkinsView)
local SlimeDex = require(UI.SlimeDex)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Skins = {}

local STYLE = table.freeze({
	tabH = Layout.MIN_TOUCH_DESIGN,
	tabGap = 6,
	tabText = 17,
	seatLine = Layout.MIN_TEXT,
	seatTagH = 20,
	howPad = 8,
	howRadius = 14,
	chip = 15,
	chipH = 26,
	listShare = 0.44, -- of the body width
	listMin = 180,
	listMax = 240,
	gap = 10, -- tabs to the blocks under them
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
	baseMinW = 136, -- narrowest base button: its longest name still fits
	baseTagH = 20, -- the gold "Exclusive" tag between name and action
	baseScroll = 6, -- the strip's sideways scroll bar
})

export type BaseGrid = {
	columns: number,
	rows: number,
	w: number, -- one button
	h: number,
	canvasW: number, -- every column; wider than `bodyW` = the strip scrolls sideways
	stripH: number,
}

-- How `n` base buttons sit in a strip `bodyW` wide: one row when they fit at STYLE.baseMinW, else two rows, as
-- wide as fits (at least baseMinW, scrolling sideways past the body). `tall`: a button carries the Exclusive tag.
function Skins.baseGrid(n: number, bodyW: number, tall: boolean): BaseGrid
	local gap = STYLE.baseGap
	local fit = math.max(1, math.floor((bodyW + gap) / (STYLE.baseMinW + gap)))
	local rows = if n > fit then 2 else 1
	local columns = math.max(1, math.ceil(n / rows))
	local w = math.max(STYLE.baseMinW, math.floor((bodyW - gap * (columns - 1)) / columns))
	local h = STYLE.baseH + (if tall then STYLE.baseTagH else 0)
	local canvasW = columns * w + gap * (columns - 1)
	local stripH = rows * h + gap * (rows - 1) + (if canvasW > bodyW then STYLE.baseScroll + 2 else 0)
	return { columns = columns, rows = rows, w = w, h = h, canvasW = canvasW, stripH = stripH }
end

-- The pane's slime cells: how many fit across `inner` px and how wide each is.
function Skins.cells(inner: number): (number, number)
	local columns = math.max(1, math.floor((inner + STYLE.cellGap) / (STYLE.cellMin + STYLE.cellGap)))
	return columns, math.floor((inner - STYLE.cellGap * (columns - 1)) / columns)
end

-- The tabs, in order. "base" is the one the menu opens on.
Skins.TABS = table.freeze({
	table.freeze({ key = "base", label = "Base" }),
	table.freeze({ key = "cloud", label = "Cloud" }),
})

function Skins.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "SkinsPanel", "Skins", "🏠")
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
	local strip = Widgets.scroll({
		Name = "Bases",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = STYLE.baseScroll,
		Visible = false,
		Parent = content,
	})
	local list = Widgets.scrollList({ Name = "List", Parent = content }, STYLE.rowGap)
	local seatList = Widgets.scrollList({ Name = "SeatList", Visible = false, Parent = content }, STYLE.rowGap)
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
	local selectedSeat: string? = nil
	local tab = Skins.TABS[1].key
	local bodyW, bodyH = Layout.MENU_WIDTH - c.pad * 2, fullH
	local stripH = STYLE.baseH
	local repaint: () -> ()
	local paneW = 0 -- the pane's width (layout sets it)

	local function listWidth(): number
		return math.clamp(math.floor(bodyW * STYLE.listShare), STYLE.listMin, STYLE.listMax)
	end

	local tabs: { [string]: any } = {}
	for _, def in Skins.TABS do
		local button = Widgets.button(
			{
				Name = `Tab_{def.key}`,
				Text = def.label,
				TextSize = STYLE.tabText,
				Size = UDim2.fromOffset(0, STYLE.tabH),
				Parent = content,
			},
			Theme.Info,
			function()
				tab = def.key
				repaint()
			end
		)
		button.instance.Parent = content
		tabs[def.key] = button
	end

	local function placeBody()
		-- Tabs share the body width; the last one takes the remainder.
		local n = #Skins.TABS
		local tabW = math.floor((bodyW - STYLE.tabGap * (n - 1)) / n)
		for i, def in Skins.TABS do
			local x = (i - 1) * (tabW + STYLE.tabGap)
			tabs[def.key].instance.Position = UDim2.fromOffset(x, 0)
			tabs[def.key].instance.Size = UDim2.fromOffset(if i == n then bodyW - x else tabW, STYLE.tabH)
		end
		local lw = listWidth()
		local top = STYLE.tabH + STYLE.gap
		Widgets.place(strip, UDim2.fromOffset(0, top), UDim2.fromOffset(bodyW, stripH))
		if strip.Visible then
			top += stripH + STYLE.baseGap
		end
		local h = math.max(bodyH - top, 0)
		for _, l in { list, seatList } do
			Widgets.place(l, UDim2.fromOffset(0, top), UDim2.fromOffset(lw, h))
		end
		empty.Position = UDim2.fromOffset(0, top)
		paneW = bodyW - lw - c.gutter
		Widgets.place(pane, UDim2.fromOffset(lw + c.gutter, top), UDim2.fromOffset(paneW, h))
	end

	-- Base buttons, reused by index.
	type BaseButton = {
		frame: TextButton,
		stroke: UIStroke,
		title: TextLabel,
		state: TextLabel,
		tag: TextLabel,
		row: PlotBasesView.Row?,
	}
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
		local tag = Widgets.chip({
			Name = "Exclusive",
			Text = PlotBasesView.EXCLUSIVE,
			TextSize = STYLE.baseState,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, STYLE.baseTagH),
			Visible = false,
			Parent = frame,
		}, Theme.Gold)
		local made: BaseButton
		frame.Activated:Connect(function()
			local row = made.row
			if row == nil then
				return
			end
			if row.state == "unlocked" and ctx.request then
				ctx.request("EquipPlotBase", function() end, row.id)
			elseif row.exclusive then
				if row.purchase and ctx.purchase then
					ctx.purchase.prompt(row.purchase)
				elseif row.shopKey and ctx.openExclusiveShop then
					ctx.openExclusiveShop(row.shopKey)
				end
			end
		end)
		made = { frame = frame, stroke = stroke, title = title, state = state, tag = tag, row = nil }
		baseButtons[i] = made
		return made
	end

	local function paintBases(baseRows: { PlotBasesView.Row }, grid: BaseGrid)
		local n = #baseRows
		local w, h = grid.w, grid.h
		local half = STYLE.baseH // 2
		strip.CanvasSize = UDim2.fromOffset(grid.canvasW, 0)
		for i, row in baseRows do
			local b = baseButton(i)
			local locked = row.state == "locked"
			local col, line = (i - 1) % grid.columns, (i - 1) // grid.columns
			b.row = row
			b.frame.Visible = true
			b.frame:SetAttribute("BaseId", row.id)
			b.frame:SetAttribute("State", row.state)
			b.frame:SetAttribute("Exclusive", row.exclusive)
			b.frame.Position = UDim2.fromOffset(col * (w + STYLE.baseGap), line * (h + STYLE.baseGap))
			b.frame.Size = UDim2.fromOffset(w, h)
			b.title.Size = UDim2.new(1, -8, 0, half - 2)
			b.state.Position = UDim2.new(0, 4, 1, -half)
			b.state.Size = UDim2.new(1, -8, 0, half - 3)
			b.tag.Visible = row.exclusive
			b.frame.BackgroundColor3 = if row.state == "equipped" then Theme.BgLight else Theme.Row
			b.stroke.Color = if row.state == "equipped" then Theme.Good else Theme.Ink
			b.stroke.Thickness = if row.state == "equipped" then STYLE.selectStroke else Widgets.KIT.rowStroke
			b.title.Text = row.title
			b.title.TextColor3 = if locked then Theme.Muted else Theme.Text
			b.state.Text = row.action
			b.state.TextColor3 = if row.state == "equipped"
				then Theme.Good
				elseif row.state == "unlocked" or row.exclusive then Theme.Accent
				else Theme.Muted
		end
		for i = n + 1, #baseButtons do
			baseButtons[i].frame.Visible = false
		end
	end

	local function equip(id: string)
		if ctx.request then
			if tab == "cloud" then
				ctx.request("EquipPetSeat", function() end, id)
			else
				ctx.request("EquipPlotSkin", function() end, id)
			end
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
			Size = UDim2.new(1, 0, 0, STYLE.rowH),
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
		-- An Exclusive skin not owned yet: a gold "Exclusive" instead of a progress bar.
		r.state.Visible = not locked or row.exclusive
		r.state.Text = if row.exclusive
			then ExclusiveShopView.EXCLUSIVE
			elseif row.state == "equipped" then PlotSkinsView.EQUIPPED
			else "Unlocked"
		r.state.TextColor3 = if row.exclusive
			then Theme.Gold
			elseif row.state == "equipped" then Theme.Good
			else Theme.Muted
		r.bar.Visible = locked and not row.exclusive
		r.setBar(row.fraction)
		r.count.Visible = locked and not row.exclusive
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

	-- Seat rows (Cloud tab): taller while they carry an unlock line.
	local function seatTextWidth(): number
		return listWidth() - STYLE.rowPad * 3 - STYLE.icon
	end
	local function seatRowHeight(row: PetSeatsView.Row): number
		if row.state ~= "locked" then
			return STYLE.rowH
		end
		local lineH = math.ceil(Layout.wrappedHeight(row.line, STYLE.seatLine, seatTextWidth()))
		local extra = if row.exclusive then STYLE.seatTagH + 2 else STYLE.bar + 6
		return math.max(STYLE.rowH, 8 + STYLE.nameH + 2 + lineH + extra + 8)
	end

	local function makeSeatRow(row: PetSeatsView.Row): any
		local frame = create("TextButton", {
			Name = row.key,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Row,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, STYLE.rowH),
		}, { Widgets.corner(Widgets.KIT.rowRadius) :: Instance }) :: TextButton
		local stroke = Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke)
		stroke.Parent = frame
		local image = create("Frame", {
			Name = "Image",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, STYLE.rowPad, 0.5, 0),
			Size = UDim2.fromOffset(STYLE.icon, STYLE.icon),
			Parent = frame,
		}, { Widgets.corner(Widgets.KIT.radius) :: Instance, Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
		local icon = ItemIconView.new({
			Name = "SeatIcon",
			Id = `PetSeat_{row.id}`,
			Size = STYLE.icon,
			Parent = image,
		}, icons)
		local textX = STYLE.rowPad * 2 + STYLE.icon
		local title = Widgets.label({
			Name = "Title",
			Font = Theme.Font,
			TextSize = STYLE.name,
			Position = UDim2.fromOffset(textX, 8),
			Size = UDim2.new(1, -(textX + STYLE.rowPad), 0, STYLE.nameH),
			Parent = frame,
		})
		local stateLabel = Widgets.label({
			Name = "State",
			Font = Theme.Font,
			TextSize = STYLE.state,
			Position = UDim2.fromOffset(textX, 8 + STYLE.nameH + 2),
			Size = UDim2.new(1, -(textX + STYLE.rowPad), 0, 18),
			Parent = frame,
		})
		local tag = Widgets.chip({
			Name = "Exclusive",
			Text = PetSeatsView.EXCLUSIVE,
			TextSize = STYLE.state,
			Position = UDim2.fromOffset(textX, 8 + STYLE.nameH + 2),
			Size = UDim2.fromOffset(0, STYLE.seatTagH),
			Parent = frame,
		}, Theme.Gold)
		local line = Widgets.label({
			Name = "Line",
			[Widgets.fontKey(Theme.FontBody)] = Theme.FontBody,
			TextSize = STYLE.seatLine,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(textX, 8 + STYLE.nameH + 2),
			Size = UDim2.new(1, -(textX + STYLE.rowPad), 0, 18),
			Parent = frame,
		})
		local countW = 64
		local bar, setBar = Widgets.bar(
			frame,
			Theme.Good,
			UDim2.new(1, -(textX + STYLE.rowPad + countW + 6), 0, STYLE.bar),
			UDim2.fromOffset(textX, 0)
		)
		bar.Name = "Progress"
		local count = Widgets.label({
			Name = "Count",
			Font = Theme.Font,
			TextSize = STYLE.state,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(countW, 18),
			Parent = frame,
		})
		frame.Activated:Connect(function()
			selectedSeat = frame:GetAttribute("SeatId") :: string?
			repaint()
		end)
		return {
			instance = frame,
			stroke = stroke,
			image = image,
			icon = icon,
			title = title,
			state = stateLabel,
			tag = tag,
			line = line,
			bar = bar,
			setBar = setBar,
			count = count,
		}
	end

	local function updateSeatRow(r: any, row: PetSeatsView.Row)
		local locked = row.state == "locked"
		local on = row.id == selectedSeat
		local textX = STYLE.rowPad * 2 + STYLE.icon
		local textW = seatTextWidth()
		r.instance.Size = UDim2.new(1, 0, 0, seatRowHeight(row))
		r.instance:SetAttribute("SeatId", row.id)
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
		r.tag.Visible = row.exclusive
		local y = 8 + STYLE.nameH + 2
		if row.exclusive then
			y += STYLE.seatTagH + 2
		end
		local lineH = if locked then math.ceil(Layout.wrappedHeight(row.line, STYLE.seatLine, textW)) else 0
		r.line.Visible = locked
		r.line.Text = row.line
		r.line.Position = UDim2.fromOffset(textX, y)
		r.line.Size = UDim2.new(1, -(textX + STYLE.rowPad), 0, lineH)
		local hasBar = locked and not row.exclusive
		local barY = y + lineH + 6
		r.bar.Visible = hasBar
		r.count.Visible = hasBar
		r.bar.Position = UDim2.fromOffset(textX, barY)
		r.count.Position = UDim2.new(1, -STYLE.rowPad, 0, barY + STYLE.bar // 2 - 9)
		r.setBar(row.fraction)
		r.count.Text = row.count
	end

	local seatRows = Widgets.keyedList(
		seatList,
		function(row: PetSeatsView.Row)
			return row.key
		end,
		makeSeatRow,
		function(r: any, row: PetSeatsView.Row)
			updateSeatRow(r, row)
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
	-- Cloud tab: the Exclusive tag and the "How to unlock" box.
	local paneTag = Widgets.chip({
		Name = "Exclusive",
		Text = PetSeatsView.EXCLUSIVE,
		TextSize = STYLE.state,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(0, STYLE.seatTagH + 4),
		Visible = false,
		Parent = pane,
	}, Theme.Gold)
	local how = create("Frame", {
		Name = "How",
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.45,
		Visible = false,
		Parent = pane,
	}, { Widgets.corner(STYLE.howRadius) :: Instance })
	local howHead = Widgets.label({
		Name = "Heading",
		Font = Theme.Font,
		TextSize = STYLE.line,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = how,
	})
	local howLine = Widgets.label({
		Name = "Line",
		[Widgets.fontKey(Theme.FontBody)] = Theme.FontBody,
		TextSize = STYLE.line,
		TextColor3 = Theme.Text,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = how,
	})
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
			local id = if tab == "cloud" then selectedSeat else selected
			if id then
				equip(id)
			end
		end
	)
	local well = Widgets.status({
		Name = "Well",
		TextSize = STYLE.buttonText,
		Size = UDim2.fromOffset(0, STYLE.button),
		Parent = pane,
	})
	local shopButton = Widgets.button(
		{
			Name = "ExclusiveShop",
			Text = PetSeatsView.EXCLUSIVE_ACTION,
			TextSize = STYLE.buttonText,
			Size = UDim2.fromOffset(0, STYLE.button),
			Visible = false,
		},
		Theme.Accent,
		function()
			if selectedSeat and ctx.openExclusiveShop then
				ctx.openExclusiveShop(`seat:{selectedSeat}`)
			end
		end
	)
	shopButton.instance.Parent = pane
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
		paneTag.Visible = false
		how.Visible = false
		shopButton.instance.Visible = false
		if detail == nil then
			return
		end
		local inner = math.max(paneW - STYLE.pad * 2, 1)
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

	-- The pane for a seat: big icon, name, the Exclusive tag, how to get it, the bar and the button or well.
	local function paintSeatPane(detail: PetSeatsView.Detail?)
		pane.Visible = detail ~= nil
		for _, cl in cells do
			cl.frame.Visible = false
			SlimePreview.unmount(cl.preview)
			cl.preview:SetAttribute("Look", nil)
		end
		paneLine.Visible = false
		if detail == nil then
			paneTag.Visible = false
			how.Visible = false
			shopButton.instance.Visible = false
			return
		end
		local inner = math.max(paneW - STYLE.pad * 2, 1)
		local y = STYLE.pad
		bigWell.Position = UDim2.new(0.5, 0, 0, y)
		bigWell.BackgroundColor3 = Theme.BgLight
		local iconId = `PetSeat_{detail.id}`
		if bigWell:GetAttribute("SkinId") ~= iconId then
			bigWell:SetAttribute("SkinId", iconId)
			bigIcon.set(iconId)
		end
		bigIcon.setFrame(if detail.state == "locked" then Theme.Muted else nil)
		bigIcon.setActive(open)
		y += STYLE.bigIcon + 6
		local titleH = math.ceil(Layout.wrappedHeight(detail.title, STYLE.title, inner, true))
		paneTitle.Text = detail.title
		paneTitle.Visible = true
		paneTitle.Position = UDim2.fromOffset(STYLE.pad, y)
		paneTitle.Size = UDim2.fromOffset(inner, titleH)
		y += titleH + 4
		paneTag.Visible = detail.exclusive
		if detail.exclusive then
			paneTag.Position = UDim2.new(0.5, 0, 0, y)
			y += STYLE.seatTagH + 4 + 6
		end
		how.Visible = true
		local howInner = math.max(inner - STYLE.howPad * 2, 1)
		local headH = if detail.heading ~= "" then 18 else 0
		local lineH = math.ceil(Layout.wrappedHeight(detail.line, STYLE.line, howInner))
		howHead.Visible = detail.heading ~= ""
		howHead.Text = detail.heading
		howHead.TextColor3 = if detail.exclusive then Theme.Gold else Theme.Good
		howHead.Position = UDim2.fromOffset(STYLE.howPad, STYLE.howPad)
		howHead.Size = UDim2.fromOffset(howInner, headH)
		howLine.Text = detail.line
		howLine.Position = UDim2.fromOffset(STYLE.howPad, STYLE.howPad + headH)
		howLine.Size = UDim2.fromOffset(howInner, lineH)
		how.Position = UDim2.fromOffset(STYLE.pad, y)
		how.Size = UDim2.fromOffset(inner, STYLE.howPad * 2 + headH + lineH)
		y += STYLE.howPad * 2 + headH + lineH + 8
		local hasCount = detail.count ~= nil and detail.state == "locked"
		paneBar.Visible = hasCount
		paneCount.Visible = hasCount
		if hasCount then
			local countW = 64
			paneBar.Position = UDim2.fromOffset(STYLE.pad, y + 4)
			paneBar.Size = UDim2.fromOffset(inner - countW - 6, STYLE.bar)
			setPaneBar(detail.fraction)
			paneCount.Text = detail.count or ""
			paneCount.TextXAlignment = Enum.TextXAlignment.Right
			paneCount.Position = UDim2.fromOffset(STYLE.pad + inner - countW, y)
			paneCount.Size = UDim2.fromOffset(countW, 18)
			y += 18 + 8
		end
		local canEquip = detail.state == "unlocked"
		local canShop = detail.exclusive
			and ctx.openExclusiveShop ~= nil
			and type(latest) == "table"
			and latest.exclusiveShop ~= nil
		equipButton.instance.Visible = canEquip
		shopButton.instance.Visible = canShop
		well.Visible = not canEquip and not canShop
		well.Text = detail.action
		well.TextColor3 = if detail.state == "equipped"
			then Theme.Good
			elseif detail.exclusive then Theme.Gold
			else Theme.Muted
		for _, inst in { equipButton.instance :: GuiObject, shopButton.instance, well } do
			inst.Position = UDim2.fromOffset(STYLE.pad, y)
			inst.Size = UDim2.fromOffset(inner, STYLE.button)
		end
		y += STYLE.button + STYLE.pad
		pane.CanvasSize = UDim2.fromOffset(0, y)
	end

	-- Cloud tab: the seat rows and the selected seat's pane.
	local function repaintSeats()
		local seatRowsList = PetSeatsView.rows(latest.petSeats, ctx.Config)
		if strip.Visible then
			-- the base strip belongs to the Base tab
			strip.Visible = false
			placeBody()
		end
		empty.Text = PetSeatsView.EMPTY
		empty.Visible = #seatRowsList == 0
		list.Visible = false
		seatList.Visible = #seatRowsList > 0
		summary.Visible = #seatRowsList > 0
		summary.Text = PetSeatsView.summary(seatRowsList)
		local known = false
		for _, row in seatRowsList do
			known = known or row.id == selectedSeat
		end
		if not known then
			selectedSeat = PetSeatsView.firstSelected(seatRowsList)
		end
		if not open then
			return
		end
		attach()
		seatRows.sync(seatRowsList)
		paintSeatPane(if selectedSeat then PetSeatsView.detail(latest.petSeats, selectedSeat) else nil)
	end

	function repaint()
		for key, button in tabs do
			button.setColor(if key == tab then Theme.Accent else Theme.Info)
			button.instance:SetAttribute("Selected", key == tab)
		end
		if latest == nil then
			return
		end
		if tab == "cloud" then
			repaintSeats()
			return
		end
		seatList.Visible = false
		empty.Text = PlotSkinsView.EMPTY
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
		local baseRows = PlotBasesView.rows(latest.plotBases, ctx.Config)
		local tall = false
		for _, row in baseRows do
			tall = tall or row.exclusive
		end
		local grid = Skins.baseGrid(#baseRows, bodyW, tall)
		if strip.Visible ~= (#baseRows > 0) or stripH ~= grid.stripH then
			strip.Visible = #baseRows > 0
			stripH = grid.stripH
			placeBody()
		end
		paintBases(baseRows, grid)
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
		if isOpen and not open then
			tab = Skins.TABS[1].key -- every open starts on Base
		end
		open = isOpen
		for _, r in rows.rows do
			r.icon.setActive(isOpen)
		end
		for _, r in seatRows.rows do
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

	-- The skin or seat shown in the pane (tests), and picking one (the rows do the same).
	function self.selected(): string?
		return if tab == "cloud" then selectedSeat else selected
	end
	function self.select(id: string)
		if tab == "cloud" then
			selectedSeat = id
		else
			selected = id
		end
		repaint()
	end
	-- The open tab ("base" / "cloud") and switching it (the tab buttons do the same).
	function self.tab(): string
		return tab
	end
	function self.setTab(key: string)
		tab = key
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
