--!strict
--[[
	SlimeDex panel (Nav key "Dex", CONTRACT.md §35.5): completion up top (big percent, "Species n / 50", the
	stamp line, a bar), the next milestone of each ladder with the income bonus, then a scroll list: the
	milestone bar card, plot skin cards, and one card per species grouped by rarity (SlimeDex.lines), the event
	Secrets last. A card shows the species mesh (`ctx.buildSpecies`, a ViewportFrame) in full colour when found
	and as a flat black silhouette when not, its name or "???", the hint line, three ingredient slots for
	hybrids and the 8 stamp dots (+ gold stamps). Cards sit in a grid that fits the panel width (one column
	on a narrow phone).

	The list (and its previews) is only rebuilt while the panel is open: update() while closed just marks it
	dirty, and setOpen(true) rebuilds if dirty or never built. Previews are virtualised: only cards in or near
	the scroll window hold a ViewportFrame, at most SlimePreview.MAX_LIVE at once. layout(rect) gets the panel
	box: the grid follows its width, and on a short body the header drops rows (SlimeDex.header).
]]

local UI = script.Parent.Parent
local FriendBadge = require(UI.FriendBadge)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local Progress = require(UI.Progress)
local SlimeDex = require(UI.SlimeDex)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Dex = {}

-- Design px and text sizes of the panel's parts.
local STYLE = table.freeze({
	percent = 34,
	count = 16,
	caption = 13,
	rewards = 13,
	headerText = 15,
	headerDetail = 13,
	cardTitle = 15,
	cardHint = 11,
	badge = 11,
	slot = 24,
	slotText = 11,
	dot = 10,
	dotGap = 3,
	gold = 11,
	pad = 6,
	skinRow = 72,
	skinImage = 64,
	milestone = 84,
	listGap = 4,
	scrollBar = 10, -- list width kept free for the scroll bar
})

local C = SlimeDex.CARD
local PREVIEW_MARGIN = C.h * 2 -- cards this far past the scroll window keep their preview

function Dex.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "DexPanel", "SlimeDex", "📖", Color3.fromRGB(150, 90, 220))

	local percent = Widgets.label({
		Name = "Percent",
		Font = Theme.Font,
		TextSize = STYLE.percent,
		TextColor3 = Theme.Accent,
		Size = UDim2.fromOffset(110, 40),
		Parent = panel.body,
	})
	local count = Widgets.label({
		Name = "Count",
		Font = Theme.Font,
		TextSize = STYLE.count,
		Size = UDim2.new(1, -116, 0, 20),
		Position = UDim2.fromOffset(116, 2),
		Parent = panel.body,
	})
	local caption = Widgets.label({
		Name = "Caption",
		Text = "",
		TextSize = STYLE.caption,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, -116, 0, 16),
		Position = UDim2.fromOffset(116, 22),
		Parent = panel.body,
	})
	local bar, setBar = Widgets.bar(panel.body, Theme.Accent, UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 46))

	local rewardLine = Widgets.label({
		Name = "Rewards",
		Visible = false,
		TextSize = STYLE.rewards,
		TextColor3 = Theme.Gold,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, SlimeDex.HEADER.rewards - 2),
		Position = UDim2.fromOffset(0, SlimeDex.HEADER.bar),
		Parent = panel.body,
	})

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, SlimeDex.HEADER.bar + SlimeDex.HEADER.gap),
		Size = UDim2.new(1, 0, 1, -(SlimeDex.HEADER.bar + SlimeDex.HEADER.gap)),
		Parent = panel.body,
	}, STYLE.listGap)

	local open = false
	local icons = ItemIcons.of(ctx)

	-- Species name + colour for ingredient slots and previews.
	local function lookup(id: string): (string?, { number }?)
		local entry = if ctx.SlimeRoster then ctx.SlimeRoster.get(id) else nil
		local look = if ctx.SlimeLooks then ctx.SlimeLooks.get(id) else nil
		return if entry then entry.name else nil, if look then look.color else nil
	end

	-- First list row: bar to the next unclaimed species milestone (Progress.dexMilestones) with its reward
	-- icon and a tick row of the milestones; hidden on a server without dex rewards. Built on the first
	-- update that carries dex rewards.
	local mile: any = nil
	local function buildMilestone()
		local card = create("Frame", {
			Name = "Milestones",
			LayoutOrder = -1,
			Size = UDim2.new(1, -STYLE.scrollBar, 0, STYLE.milestone),
			BackgroundTransparency = 0.2,
			BackgroundColor3 = Theme.Row,
			Parent = list,
		}, { Widgets.corner(12) })
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = "Dex_50",
			Size = 56,
			Position = UDim2.fromOffset(8, 8),
			Parent = card,
		}, icons)
		icon.setActive(open)
		local label = Widgets.label({
			Name = "MilestoneCount",
			Font = Theme.Font,
			TextSize = STYLE.count,
			Position = UDim2.fromOffset(72, 6),
			Size = UDim2.new(1, -80, 0, 20),
			Parent = card,
		})
		local back, setFill = Widgets.bar(card, Theme.Gold, UDim2.new(1, -80, 0, 14), UDim2.fromOffset(72, 30))
		back.Name = "MilestoneBar"
		local ticks = Widgets.label({
			Name = "MilestoneTicks",
			TextSize = STYLE.caption,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(72, 50),
			Size = UDim2.new(1, -80, 0, 18),
			Parent = card,
		})
		return { card = card, icon = icon, label = label, setFill = setFill, ticks = ticks }
	end

	local hasRewards = false
	-- Body box from layout(); nil = tall and wide enough for everything.
	local bodyH: number? = nil
	local bodyW: number? = nil
	local function placeList()
		local header = SlimeDex.header(bodyH or math.huge, hasRewards)
		bar.Visible = header.bar
		rewardLine.Visible = header.rewards
		rewardLine.Position = UDim2.fromOffset(0, header.rewardsY)
		list.Position = UDim2.fromOffset(0, header.listTop)
		list.Size = if bodyH and bodyH < header.listTop
			then UDim2.fromScale(1, 0)
			else UDim2.new(1, 0, 1, -header.listTop)
	end

	local function grid(): SlimeDex.Grid
		return SlimeDex.grid((bodyW or 1000) - STYLE.scrollBar)
	end

	-- One card per species, kept across rebuilds (keyed by species id) and moved between lines.
	local cardViews: { [string]: any } = {}

	local function makeCard(card: SlimeDex.Card): any
		local frame = create("Frame", {
			Name = card.key,
			BackgroundTransparency = 0.15,
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(12) })
		local stroke = Widgets.stroke(Theme.Muted, 2)
		stroke.Parent = frame
		local image = create("Frame", {
			Name = "Image",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, STYLE.pad),
			Size = UDim2.fromOffset(C.preview, C.preview),
			BackgroundColor3 = Theme.BgLight,
			Parent = frame,
		}, { Widgets.corner(14) })
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
			TextSize = 30,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = image,
		})
		local badge = Widgets.label({
			Name = "Badge",
			Font = Theme.Font,
			TextSize = STYLE.badge,
			TextColor3 = Theme.Bg,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Warn,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(STYLE.pad, STYLE.pad),
			Size = UDim2.fromOffset(70, 16),
			Visible = false,
			Parent = frame,
		})
		Widgets.corner(6).Parent = badge
		local title = Widgets.label({
			Name = "Title",
			Font = Theme.Font,
			TextSize = STYLE.cardTitle,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(STYLE.pad, STYLE.pad + C.preview + 4),
			Size = UDim2.new(1, -STYLE.pad * 2, 0, 20),
			Parent = frame,
		})
		local hint = Widgets.label({
			Name = "Hint",
			TextSize = STYLE.cardHint,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(STYLE.pad, STYLE.pad + C.preview + 26),
			Size = UDim2.new(1, -STYLE.pad * 2, 0, 28),
			Parent = frame,
		})
		local slotRow = create("Frame", {
			Name = "Slots",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, STYLE.pad + C.preview + 56),
			Size = UDim2.fromOffset(STYLE.slot * 3 + 12, STYLE.slot),
			Visible = false,
			Parent = frame,
		})
		local slots: { any } = {}
		for i = 1, 3 do
			local slot = Widgets.label({
				Name = `Slot{i}`,
				Font = Theme.Font,
				TextSize = STYLE.slotText,
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundTransparency = 0,
				Position = UDim2.fromOffset((i - 1) * (STYLE.slot + 6), 0),
				Size = UDim2.fromOffset(STYLE.slot, STYLE.slot),
				Parent = slotRow,
			})
			Widgets.corner(STYLE.slot // 2).Parent = slot
			slots[i] = slot
		end
		local stampRow = create("Frame", {
			Name = "Stamps",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -STYLE.pad - 2),
			Size = UDim2.fromOffset(0, STYLE.dot),
			Parent = frame,
		})
		local dots: { Frame } = {}
		local goldLabel = Widgets.label({
			Name = "Gold",
			Font = Theme.Font,
			TextSize = STYLE.gold,
			TextColor3 = Theme.Gold,
			Size = UDim2.fromOffset(30, STYLE.dot + 4),
			Visible = false,
			Parent = stampRow,
		})
		return {
			instance = frame,
			stroke = stroke,
			image = image,
			preview = preview,
			glyph = glyph,
			badge = badge,
			title = title,
			hint = hint,
			slotRow = slotRow,
			slots = slots,
			stampRow = stampRow,
			dots = dots,
			goldLabel = goldLabel,
			card = card,
		}
	end

	local function updateCard(v: any, card: SlimeDex.Card)
		v.card = card
		local frame = v.instance
		frame:SetAttribute("Found", card.found)
		frame:SetAttribute("Kind", card.kind)
		local rarity = Widgets.color3(card.color)
		v.stroke.Color = if card.found then rarity else Theme.Disabled
		v.glyph.Visible = not card.found and v.preview:GetAttribute("Look") == nil
		v.title.Text = card.title
		v.title.TextColor3 = if card.found then rarity else Theme.Muted
		v.hint.Text = card.hint or (if card.found then "" else "Not found yet")
		v.badge.Visible = card.badge ~= nil
		v.badge.Text = card.badge or ""
		local slots = card.slots
		v.slotRow.Visible = slots ~= nil
		if slots then
			for i, slot in v.slots do
				local s = slots[i]
				slot.Text = if s and s.species then string.upper(string.sub(s.label, 1, 2)) else "?"
				slot.BackgroundColor3 = Widgets.color3(if s then s.color else SlimeDex.SILHOUETTE)
				slot.TextColor3 = if s and s.species then Theme.Bg else Theme.Muted
				slot:SetAttribute("Species", if s then s.species else nil)
			end
		end
		-- Stamp dots: one per core stamp (lit = stamped), then the gold count.
		local stamps = card.stamps
		for i = #v.dots + 1, #stamps do
			local dot = create("Frame", {
				Name = `Stamp{i}`,
				Size = UDim2.fromOffset(STYLE.dot, STYLE.dot),
				Position = UDim2.fromOffset((i - 1) * (STYLE.dot + STYLE.dotGap), 0),
				Parent = v.stampRow,
			}, { Widgets.corner(STYLE.dot // 2) })
			v.dots[i] = dot
		end
		for i, dot in v.dots do
			local stamp = stamps[i]
			dot.Visible = stamp ~= nil
			if stamp then
				dot.BackgroundColor3 = if stamp.on then Widgets.color3(stamp.color) else Theme.BgLight
				dot.BackgroundTransparency = if stamp.on then 0 else 0.3
				dot:SetAttribute("Mutation", stamp.mutation)
				dot:SetAttribute("On", stamp.on)
			end
		end
		local dotsW = if #stamps > 0 then #stamps * (STYLE.dot + STYLE.dotGap) - STYLE.dotGap else 0
		v.goldLabel.Visible = #card.gold > 0
		v.goldLabel.Text = `+{#card.gold}★`
		v.goldLabel.Position = UDim2.fromOffset(dotsW + 4, -2)
		v.stampRow.Size = UDim2.fromOffset(dotsW + (if #card.gold > 0 then 34 else 0), STYLE.dot)
	end

	local function sizeCard(v: any, g: SlimeDex.Grid, column: number)
		v.instance.Size = UDim2.fromOffset(g.cardW, g.cardH)
		v.instance.Position = UDim2.fromOffset((column - 1) * (g.cardW + g.gap), 0)
	end

	-- Plot skin cards (SlimeDex.skinRows): picture, title, set progress and Equip / Equipped / Locked.
	local function makeSkin(row: SlimeDex.SkinRow): any
		local frame = create("Frame", {
			Name = row.key,
			Size = UDim2.new(1, -STYLE.scrollBar, 0, STYLE.skinRow),
			BackgroundTransparency = 0.2,
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(12) })
		local image = create("Frame", {
			Name = "Image",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(STYLE.skinImage, STYLE.skinImage),
			Parent = frame,
		}, { Widgets.corner(14) })
		local skinIcon = ItemIconView.new({
			Name = "SkinIcon",
			Id = `PlotSkin_{row.skin.id}`,
			Size = STYLE.skinImage,
			Parent = image,
		}, icons)
		local lock = Widgets.label({
			Name = "Glyph",
			Text = "🔒",
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			Size = UDim2.fromOffset(26, 26),
			Parent = image,
		})
		local title = Widgets.label({
			Name = "Title",
			Font = Theme.Font,
			TextSize = STYLE.count,
			Position = UDim2.fromOffset(STYLE.skinImage + 12, 14),
			Size = UDim2.new(1, -(STYLE.skinImage + 104), 0, 22),
			Parent = frame,
		})
		local detail = Widgets.label({
			Name = "Detail",
			TextSize = STYLE.caption,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(STYLE.skinImage + 12, 40),
			Size = UDim2.new(1, -(STYLE.skinImage + 104), 0, 18),
			Parent = frame,
		})
		local equip = Widgets.button(
			{
				Name = "Equip",
				Text = "Equip",
				TextSize = 14,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(78, 32),
				Parent = frame,
			},
			Theme.Accent,
			function()
				local id = frame:GetAttribute("SkinId")
				if type(id) == "string" and ctx.request then
					ctx.request("EquipPlotSkin", function() end, id)
				end
			end
		)
		return {
			instance = frame,
			image = image,
			skinIcon = skinIcon,
			lock = lock,
			title = title,
			detail = detail,
			equip = equip,
		}
	end

	local function updateSkin(r: any, row: SlimeDex.SkinRow)
		local skin = row.skin
		r.instance:SetAttribute("Locked", row.locked)
		r.instance:SetAttribute("SkinId", skin.id)
		r.equip.setText(if skin.equipped then "Equipped" elseif skin.unlocked then "Equip" else "Locked")
		r.equip.setEnabled(skin.unlocked and not skin.equipped)
		r.image.BackgroundColor3 = Widgets.color3(row.color)
		r.lock.Visible = not skin.unlocked
		r.skinIcon.setFrame(if skin.unlocked then nil else Theme.Muted)
		r.skinIcon.setActive(open)
		r.title.Text = row.title
		r.title.TextColor3 = if skin.unlocked then Theme.Text else Theme.Muted
		r.detail.Text = row.detail
	end

	-- List rows: plot skins, rarity headers and card lines (SlimeDex.lines).
	type Item = { key: string, skin: SlimeDex.SkinRow?, line: SlimeDex.Line? }

	local rows = Widgets.keyedList(list, function(item: Item)
		return item.key
	end, function(item: Item)
		if item.skin then
			return makeSkin(item.skin)
		end
		local line = item.line :: SlimeDex.Line
		local frame = create("Frame", {
			Name = line.key,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -STYLE.scrollBar, 0, if line.kind == "header" then C.header else C.h),
		})
		local r: any = { instance = frame }
		if line.kind == "header" then
			r.title = Widgets.label({
				Name = "Title",
				Font = Theme.Font,
				TextSize = STYLE.headerText,
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(0.7, 0, 0, 20),
				Parent = frame,
			})
			r.detail = Widgets.label({
				Name = "Detail",
				TextSize = STYLE.headerDetail,
				TextColor3 = Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, 6),
				Size = UDim2.new(0.3, 0, 0, 18),
				Parent = frame,
			})
		end
		return r
	end, function(r: any, item: Item)
		r.item = item
		if item.skin then
			updateSkin(r, item.skin)
			return
		end
		local line = item.line :: SlimeDex.Line
		if line.kind == "header" then
			local rarity = ctx.Config.RARITIES[line.tier]
			r.title.Text = line.title or ""
			r.title.TextColor3 = if rarity then Widgets.color3(rarity.color) else Theme.Gold
			r.detail.Text = line.detail or ""
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
			updateCard(v, card)
		end
	end)

	-- Mounts the preview of every card in or near the scroll window (nearest the window centre first, at most
	-- SlimePreview.MAX_LIVE) and unmounts the rest. A card's viewport is only remounted when its look changes
	-- (a failed look is not retried).
	local function viewHeight(): number
		-- From the card (init.client sizes its frame in offsets), not AbsoluteSize: that is 0 until the first
		-- layout pass.
		local chrome = Layout.PANEL_CHROME
		return math.max(panel.frame.Size.Y.Offset - chrome.header - chrome.pad - list.Position.Y.Offset, C.h)
	end

	local function mountLook(v: any)
		local card: SlimeDex.Card = v.card
		-- The species mesh may replicate after a fallback was mounted: the look names its source, so the
		-- card switches to the mesh once it is there.
		local species: Model? = nil
		if ctx.buildSpecies then
			local built, model = pcall(ctx.buildSpecies, card.key)
			species = if built then model else nil
		end
		local look = `{card.key}:{card.found}:{species ~= nil}`
		if v.preview:GetAttribute("Look") == look then
			if species then
				species:Destroy()
			end
			return
		end
		local opts = { locked = not card.found }
		local ok = species ~= nil and SlimePreview.mountModel(v.preview, species :: Model, opts)
		if not ok and ctx.buildSlime then
			local built, model = pcall(ctx.buildSlime, SlimeDex.genome(card))
			ok = built and model ~= nil and SlimePreview.mountModel(v.preview, model, opts)
		end
		if not ok then
			ok = SlimePreview.mount(v.preview, card.speciesColor, opts)
		end
		v.preview:SetAttribute("Look", look)
		v.preview.Visible = ok
		v.glyph.Visible = not ok and not card.found
	end

	local function unmountLook(v: any)
		if v.preview:GetAttribute("Look") ~= nil then
			SlimePreview.unmount(v.preview)
			v.preview:SetAttribute("Look", nil)
			v.preview.Visible = false
		end
		v.glyph.Visible = not v.card.found
	end

	local function refreshPreviews()
		if not open then
			return
		end
		local top = list.CanvasPosition.Y - PREVIEW_MARGIN
		local bottom = list.CanvasPosition.Y + viewHeight() + PREVIEW_MARGIN
		local middle = (top + bottom) / 2
		local near: { { v: any, dist: number } } = {}
		for _, v in cardViews do
			local line = v.instance.Parent
			local y = if line and line:IsA("GuiObject") then (line :: GuiObject).Position.Y.Offset else -math.huge
			if line and line.Parent == list and y + C.h > top and y < bottom then
				table.insert(near, { v = v, dist = math.abs(y + C.h / 2 - middle) })
			else
				unmountLook(v)
			end
		end
		table.sort(near, function(a, b)
			if a.dist ~= b.dist then
				return a.dist < b.dist
			end
			return a.v.instance.Position.X.Offset < b.v.instance.Position.X.Offset
		end)
		for i, entry in near do
			if i <= SlimePreview.MAX_LIVE then
				mountLook(entry.v)
			else
				unmountLook(entry.v)
			end
		end
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshPreviews)

	-- Items from the latest update and whether the list is out of date with them (never built counts as
	-- dirty). Rebuilds only happen while open.
	local pendingCards: { SlimeDex.Card } = {}
	local pendingSkins: { SlimeDex.SkinRow } = {}
	local pendingSignature: string? = nil
	local builtSignature: string? = nil
	local dirty = true
	local hasState = false -- nothing to build before the first State
	local builds = 0

	local function signature(): string
		local parts = table.create(#pendingCards + #pendingSkins + 1)
		table.insert(parts, tostring(grid().columns))
		for _, row in pendingSkins do
			table.insert(parts, `{row.key}|{row.locked}|{row.detail}|{row.skin.equipped}`)
		end
		for _, card in pendingCards do
			local on = {}
			for _, stamp in card.stamps do
				table.insert(on, if stamp.on then "1" else "0")
			end
			local slots = {}
			for _, slot in card.slots or {} do
				table.insert(slots, slot.species or "")
			end
			table.insert(
				parts,
				`{card.key}|{card.found}|{card.title}|{card.hint or ""}|{table.concat(on)}|{#card.gold}|{table.concat(
					slots,
					","
				)}`
			)
		end
		return table.concat(parts, "\n")
	end

	local function rebuild()
		if open and dirty and hasState then
			dirty = false
			builtSignature = pendingSignature
			builds += 1
			local items: { Item } = {}
			for _, row in pendingSkins do
				table.insert(items, { key = row.key, skin = row })
			end
			for _, line in SlimeDex.lines(pendingCards, grid().columns, ctx.Config) do
				table.insert(items, { key = line.key, line = line })
			end
			rows.sync(items)
			-- Cards of species that left the State (never in practice) are dropped.
			local shown: { [string]: boolean } = {}
			for _, card in pendingCards do
				shown[card.key] = true
			end
			for key, v in cardViews do
				if not shown[key] then
					v.instance:Destroy()
					cardViews[key] = nil
				end
			end
			refreshPreviews()
		end
	end

	local function markDirty()
		pendingSignature = signature()
		dirty = pendingSignature ~= builtSignature
		rebuild()
	end

	local self = { frame = panel.frame, close = panel.close }

	-- Called by init.client when the menu opens / closes.
	function self.setOpen(isOpen: boolean)
		open = isOpen
		if mile then
			mile.icon.setActive(isOpen)
		end
		for _, r in rows.rows do
			if r.skinIcon then
				r.skinIcon.setActive(isOpen)
			end
		end
		rebuild()
	end

	-- Called by init.client with the panel box (Layout.panelFor).
	function self.layout(r: Layout.Rect)
		local body = Layout.panelBody(r)
		bodyH, bodyW = body.h, body.w
		placeList()
		markDirty() -- the column count may change with the width
	end

	-- Live (mounted) previews now, and a manual refresh (tests).
	function self.liveCount(): number
		local n = 0
		for _, v in cardViews do
			if v.preview:GetAttribute("Look") ~= nil then
				n += 1
			end
		end
		return n
	end
	self.refreshPreviews = refreshPreviews

	-- How many times the list was rebuilt (tests).
	function self.builds(): number
		return builds
	end

	-- The grid the cards use now (tests).
	function self.grid(): SlimeDex.Grid
		return grid()
	end

	function self.update(state: any)
		local summary = SlimeDex.summary(state.dex)
		percent.Text = summary.percent
		count.Text = summary.count
		caption.Text = summary.stamps
		setBar(summary.fraction)
		local rewards = Progress.dexRewards(state)
		hasRewards = rewards.next ~= nil
		if rewards.next then
			local friendLine = FriendBadge.line(state.friends, ctx.Config.FEATURES.FriendBonus == true)
			local bonus = Progress.incomeLine(rewards.dexPercent, friendLine)
			rewardLine.Text = if bonus then `{rewards.next}\n{bonus}` else rewards.next
		end
		placeList()
		local ms = Progress.dexMilestones(state)
		if ms and not mile then
			mile = buildMilestone()
		end
		if mile then
			mile.card.Visible = ms ~= nil
			if ms then
				mile.icon.set(ms.icon)
				mile.label.Text = if ms.next then `Next reward: {ms.label} species` else ms.label
				mile.setFill(ms.fraction)
				mile.ticks.Text = ms.ticksText
			end
		end
		Widgets.restack(list)
		hasState = true
		pendingCards = SlimeDex.cards(state.dex, ctx.Config, lookup)
		pendingSkins = SlimeDex.skinRows(state.plotSkins, ctx.Config)
		markDirty()
	end

	return self
end

return Dex
