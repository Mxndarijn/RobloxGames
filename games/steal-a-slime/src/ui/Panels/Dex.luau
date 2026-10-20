--!strict
--[[
	SlimeDex panel (Nav key "Dex", CONTRACT.md §36.5). Up top: the big green completion percent and Ink chips
	("Species n/50", "Secrets n/7" when the server has event Secrets), wrapping onto a second row on a narrow
	body. Then a scroll list:
	  * the reward card: the next species milestone and what it pays, one bar from 0 to the last milestone with
	    every milestone marked to scale and numbered under it (the next one in gold), and the current income
	    bonus as a muted line;
	  * "Plot skins": one row per skin with its picture and name; the equipped one carries a green Equipped
	    stamp, an unlocked one an Equip button, a locked one what unlocks it and a thin progress bar;
	  * one card per species grouped by rarity (SlimeDex.lines; a header in the rarity colour with a
	    "n/m found" chip), the event Secrets last. A card shows the species mesh (`ctx.buildSpecies`, a
	    ViewportFrame) in full colour when found and as a flat black silhouette when not, its name or "???",
	    the hint and three ingredient slots for hybrids. Cards sit in a grid that fits the panel width (one
	    column on a narrow phone).

	The list (and its previews) is only rebuilt while the panel is open: update() while closed just marks it
	dirty, and setOpen(true) rebuilds if dirty or never built. Previews are virtualised: only cards in or near
	the scroll window hold a ViewportFrame, at most SlimePreview.MAX_LIVE at once. layout(rect) gets the panel
	box: the grid and the chips follow its width, and on a short body the header turns compact (SlimeDex.header).
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
	percent = 56,
	compactPercent = SlimeDex.HEADER.chip, -- fills the compact percent box
	chip = 15,
	chipPad = 20, -- chip width beyond its text
	chipGap = 10, -- percent to the first chip
	heading = 17,
	headingH = 30,
	softChip = 12,
	softChipH = 24,
	cardTitle = 15,
	cardHint = 11,
	badge = 11,
	glyph = 30,
	slot = 24,
	slotText = 11,
	pad = 6,
	wellRadius = 11,
	listGap = 8,
	scrollBar = 10, -- list width kept free for the scroll bar
})

-- The reward card (first list row).
local REWARD = table.freeze({
	pad = 12,
	title = 17,
	reward = 15,
	rewardH = 18,
	bar = 14,
	mark = 2, -- milestone mark on the bar
	tick = 12,
	tickH = 14,
	note = 12,
	gap = 6,
})

-- Plot skin rows.
local SKIN = table.freeze({
	h = 78,
	image = 58,
	pad = 10,
	gap = 12,
	title = 17,
	titleH = 20,
	detail = 12,
	detailH = 16,
	bar = 10,
	lock = 14,
	lockBox = 22,
	equipW = 84,
	equipH = 40,
	equipText = 16,
	stamp = 13,
	stampW = 86,
	stampH = 26,
	stampRadius = 8,
})

local C = SlimeDex.CARD
local H = SlimeDex.HEADER
local PREVIEW_MARGIN = C.h * 2 -- cards this far past the scroll window keep their preview

-- A section heading row in the list: title left, an optional soft chip right.
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
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.new(0.6, 0, 0, STYLE.heading + 4),
		Parent = frame,
	})
	local detail = Widgets.chip({
		Name = "Detail",
		Font = Theme.FontBody,
		TextSize = STYLE.softChip,
		BackgroundColor3 = Theme.Row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, STYLE.softChipH),
		Parent = frame,
	}, Theme.Muted)
	return { instance = frame, title = title, detail = detail }
end

function Dex.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "DexPanel", "SlimeDex", "📖")

	local percent = Widgets.label({
		Name = "Percent",
		Font = Theme.Font,
		TextSize = STYLE.percent,
		TextColor3 = Theme.Good,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromOffset(0, H.percent),
		Parent = panel.body,
	})
	local function chip(name: string, color: Color3): TextLabel
		return Widgets.chip({
			Name = name,
			TextSize = STYLE.chip,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(0, H.chip),
			Parent = panel.body,
		}, color)
	end
	-- Header chips, left to right.
	local chips = {
		chip("Count", Theme.Text),
		chip("Secrets", Theme.Text),
	}

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, H.percent + H.gap),
		Size = UDim2.new(1, 0, 1, -(H.percent + H.gap)),
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

	-- Body box from layout(); nil = tall and wide enough for everything.
	local bodyH: number? = nil
	local bodyW: number? = nil

	-- Percent and chips (SlimeDex.chipRows), then the list under them.
	local function placeHeader()
		local width = bodyW or 1000
		local shown: { TextLabel } = {}
		local widths: { number } = {}
		for _, c in chips do
			c.Visible = c.Text ~= ""
			if c.Visible then
				local w = math.ceil(Layout.lineWidth(c.Text, STYLE.chip, true)) + STYLE.chipPad
				c.Size = UDim2.fromOffset(w, H.chip)
				table.insert(shown, c)
				table.insert(widths, w)
			end
		end
		-- The chips start right after the percent text, so a low percent keeps them close.
		local percentW = SlimeDex.percentWidth(percent.Text, STYLE.percent)
		local spots, rows = SlimeDex.chipRows(widths, percentW + STYLE.chipGap, width, math.huge)
		local header = SlimeDex.header(bodyH or math.huge, rows)
		local chipY = 0
		if header.compact then
			local compactW = SlimeDex.percentWidth(percent.Text, STYLE.compactPercent)
			spots = SlimeDex.chipRows(widths, compactW + STYLE.chipGap, width, 1)
			percent.TextSize = STYLE.compactPercent
			percent.Size = UDim2.fromOffset(compactW, H.chip)
			percent.Position = UDim2.fromOffset(0, 0)
		else
			percent.TextSize = STYLE.percent
			percent.Size = UDim2.fromOffset(percentW, H.percent)
			percent.Position = UDim2.fromOffset(0, (header.height - H.percent) // 2)
			chipY = math.max(0, (header.height - (rows * H.chip + (rows - 1) * H.chipGap)) // 2)
		end
		for i, c in shown do
			local spot = spots[i]
			c.Visible = spot.visible
			c.Position = UDim2.fromOffset(spot.x, chipY + spot.y)
		end
		list.Position = UDim2.fromOffset(0, header.listTop)
		list.Size = if bodyH and bodyH < header.listTop
			then UDim2.fromScale(1, 0)
			else UDim2.new(1, 0, 1, -header.listTop)
	end

	-- First list row: the reward card (SlimeDex.rewardCard); hidden on a server without dex rewards. Built on
	-- the first update that carries them.
	local mile: any = nil
	local function buildMilestone()
		local card = Widgets.rowFrame({
			Name = "Milestones",
			LayoutOrder = -1,
			Size = UDim2.new(1, -STYLE.scrollBar, 0, 0),
			Parent = list,
		})
		local function line(name: string, size: number, color: Color3, font: Enum.Font): TextLabel
			return Widgets.label({
				Name = name,
				Font = font,
				TextSize = size,
				TextColor3 = color,
				TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None,
				TextYAlignment = Enum.TextYAlignment.Top,
				Position = UDim2.fromOffset(REWARD.pad, 0),
				Size = UDim2.new(1, -REWARD.pad * 2, 0, size),
				Parent = card,
			})
		end
		local title = line("MilestoneCount", REWARD.title, Theme.Text, Theme.Font)
		local reward = line("MilestoneReward", REWARD.reward, Theme.Gold, Theme.Font)
		local back, setFill = Widgets.bar(card, Theme.Good, UDim2.new(1, -REWARD.pad * 2, 0, REWARD.bar))
		back.Name = "MilestoneBar"
		local ticks = create("Frame", {
			Name = "MilestoneTicks",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -REWARD.pad * 2, 0, REWARD.tickH),
			Parent = card,
		})
		local bonus = line("MilestoneBonus", REWARD.note, Theme.Muted, Theme.FontBody)
		return {
			card = card,
			title = title,
			reward = reward,
			back = back,
			setFill = setFill,
			ticks = ticks,
			marks = {} :: { [number]: Frame },
			labels = {} :: { [number]: TextLabel },
			bonus = bonus,
		}
	end

	-- Stacks the reward card's lines for the list width (the title wraps, never truncates).
	local function placeMilestone()
		if not mile then
			return
		end
		local inner = (bodyW or 1000) - STYLE.scrollBar - REWARD.pad * 2
		local y = REWARD.pad
		local function put(label: TextLabel, size: number)
			if label.Visible then
				local h = math.ceil(Layout.wrappedHeight(label.Text, size, inner, true))
				label.Position = UDim2.fromOffset(REWARD.pad, y)
				label.Size = UDim2.new(1, -REWARD.pad * 2, 0, h)
				y += h + 2
			end
		end
		put(mile.title, REWARD.title)
		put(mile.reward, REWARD.reward)
		y += REWARD.gap - 2
		mile.back.Position = UDim2.fromOffset(REWARD.pad, y)
		y += REWARD.bar + 4
		mile.ticks.Position = UDim2.fromOffset(REWARD.pad, y)
		y += REWARD.tickH + REWARD.gap
		put(mile.bonus, REWARD.note)
		mile.card.Size = UDim2.new(1, -STYLE.scrollBar, 0, y - 2 + REWARD.pad)
	end

	local function paintMilestone(rc: SlimeDex.RewardCard, bonusLine: string?)
		mile.title.Text = rc.title
		mile.reward.Visible = rc.reward ~= nil
		mile.reward.Text = rc.reward or ""
		mile.setFill(rc.fraction)
		local seen: { [number]: boolean } = {}
		for _, t in rc.ticks do
			seen[t.count] = true
			local mark = mile.marks[t.count]
			if mark == nil then
				-- Created after the fill, so it draws over it.
				mark = create("Frame", {
					Name = `Mark{t.count}`,
					BorderSizePixel = 0,
					BackgroundColor3 = Theme.BgLight,
					AnchorPoint = Vector2.new(0.5, 0),
					Size = UDim2.new(0, REWARD.mark, 1, 0),
					Parent = mile.back,
				})
				mile.marks[t.count] = mark
			end
			mark.Position = UDim2.fromScale(t.at, 0)
			mark.Visible = t.at < 1
			local label = mile.labels[t.count]
			if label == nil then
				label = Widgets.label({
					Name = `Tick{t.count}`,
					Font = Theme.Font,
					TextSize = REWARD.tick,
					TextTruncate = Enum.TextTruncate.None,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					Parent = mile.ticks,
				})
				mile.labels[t.count] = label
			end
			label.Text = tostring(t.count)
			label.AnchorPoint = Vector2.new(if t.at >= 1 then 1 elseif t.at <= 0 then 0 else 0.5, 0)
			label.Position = UDim2.fromScale(t.at, 0)
			label.TextColor3 = if t.isNext then Theme.Gold elseif t.claimed then Theme.Good else Theme.Muted
			label:SetAttribute("Claimed", t.claimed)
			label:SetAttribute("Next", t.isNext)
		end
		for count, mark in mile.marks do
			if not seen[count] then
				mark:Destroy()
				mile.marks[count] = nil
				mile.labels[count]:Destroy()
				mile.labels[count] = nil
			end
		end
		mile.bonus.Visible = bonusLine ~= nil
		mile.bonus.Text = bonusLine or ""
		placeMilestone()
	end

	local function grid(): SlimeDex.Grid
		return SlimeDex.grid((bodyW or 1000) - STYLE.scrollBar)
	end

	-- One card per species, kept across rebuilds (keyed by species id) and moved between lines.
	local cardViews: { [string]: any } = {}

	local function makeCard(card: SlimeDex.Card): any
		local frame = Widgets.rowFrame({ Name = card.key })
		local image = create("Frame", {
			Name = "Image",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, STYLE.pad),
			Size = UDim2.fromOffset(C.preview, C.preview),
			BackgroundColor3 = Theme.BgLight,
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
			TextSize = STYLE.glyph,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = image,
		})
		local badge = Widgets.label({
			Name = "Badge",
			Font = Theme.Font,
			TextSize = STYLE.badge,
			TextColor3 = Theme.Ink,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Warn,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(STYLE.pad, STYLE.pad),
			Size = UDim2.fromOffset(70, 16),
			Visible = false,
			Parent = frame,
		})
		Widgets.corner(STYLE.pad).Parent = badge
		Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke).Parent = badge
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
			Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke).Parent = slot
			slots[i] = slot
		end
		return {
			instance = frame,
			image = image,
			preview = preview,
			glyph = glyph,
			badge = badge,
			title = title,
			hint = hint,
			slotRow = slotRow,
			slots = slots,
			card = card,
		}
	end

	local function updateCard(v: any, card: SlimeDex.Card)
		v.card = card
		local frame = v.instance
		frame:SetAttribute("Found", card.found)
		frame:SetAttribute("Kind", card.kind)
		v.glyph.Visible = not card.found and v.preview:GetAttribute("Look") == nil
		v.title.Text = card.title
		v.title.TextColor3 = if card.found then Widgets.color3(card.color) else Theme.Muted
		v.hint.Text = card.hint or ""
		v.badge.Visible = card.badge ~= nil
		v.badge.Text = card.badge or ""
		local slots = card.slots
		v.slotRow.Visible = slots ~= nil
		if slots then
			for i, slot in v.slots do
				local s = slots[i]
				slot.Text = if s and s.species then string.upper(string.sub(s.label, 1, 2)) else "?"
				slot.BackgroundColor3 = if s and s.species then Widgets.color3(s.color) else Theme.Ink
				slot.TextColor3 = if s and s.species then Theme.Ink else Theme.Muted
				slot:SetAttribute("Species", if s then s.species else nil)
			end
		end
	end

	local function sizeCard(v: any, g: SlimeDex.Grid, column: number)
		v.instance.Size = UDim2.fromOffset(g.cardW, g.cardH)
		v.instance.Position = UDim2.fromOffset((column - 1) * (g.cardW + g.gap), 0)
	end

	-- Plot skin rows (SlimeDex.skinRows): picture, name, the set or what unlocks it, and Equip / Equipped.
	local function makeSkin(row: SlimeDex.SkinRow): any
		local frame = Widgets.rowFrame({
			Name = row.key,
			Size = UDim2.new(1, -STYLE.scrollBar, 0, SKIN.h),
		})
		local image = create("Frame", {
			Name = "Image",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, SKIN.pad, 0.5, 0),
			Size = UDim2.fromOffset(SKIN.image, SKIN.image),
			Parent = frame,
		}, { Widgets.corner(Widgets.KIT.radius), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
		local skinIcon = ItemIconView.new({
			Name = "SkinIcon",
			Id = `PlotSkin_{row.skin.id}`,
			Size = SKIN.image,
			Parent = image,
		}, icons)
		local lock = Widgets.label({
			Name = "Glyph",
			Text = "🔒",
			TextSize = SKIN.lock,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Ink,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 1, -4),
			Size = UDim2.fromOffset(SKIN.lockBox, SKIN.lockBox),
			Parent = image,
		})
		Widgets.corner(SKIN.stampRadius).Parent = lock
		local textX = SKIN.pad + SKIN.image + SKIN.gap
		local title = Widgets.label({
			Name = "Title",
			Font = Theme.Font,
			TextSize = SKIN.title,
			Position = UDim2.fromOffset(textX, 0),
			Size = UDim2.new(1, -(textX + SKIN.pad), 0, SKIN.titleH),
			Parent = frame,
		})
		local detail = Widgets.label({
			Name = "Detail",
			TextSize = SKIN.detail,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(textX, 0),
			Size = UDim2.new(1, -(textX + SKIN.pad), 0, SKIN.detailH),
			Parent = frame,
		})
		local progress, setProgress =
			Widgets.bar(frame, Theme.Good, UDim2.new(1, -(textX + SKIN.pad), 0, SKIN.bar), UDim2.fromOffset(textX, 0))
		progress.Name = "Progress"
		local equip = Widgets.button(
			{
				Name = "Equip",
				Text = "Equip",
				TextSize = SKIN.equipText,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -SKIN.pad, 0.5, 0),
				Size = UDim2.fromOffset(SKIN.equipW, SKIN.equipH),
				Parent = frame,
			},
			Theme.Good,
			function()
				local id = frame:GetAttribute("SkinId")
				if type(id) == "string" and ctx.request then
					ctx.request("EquipPlotSkin", function() end, id)
				end
			end
		)
		local equipped = Widgets.label({
			Name = "Equipped",
			Text = "Equipped",
			Font = Theme.Font,
			TextSize = SKIN.stamp,
			TextColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Good,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -SKIN.pad, 0.5, 0),
			Size = UDim2.fromOffset(SKIN.stampW, SKIN.stampH),
			Visible = false,
			Parent = frame,
		})
		Widgets.corner(SKIN.stampRadius).Parent = equipped
		Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke).Parent = equipped
		return {
			instance = frame,
			image = image,
			skinIcon = skinIcon,
			lock = lock,
			textX = textX,
			title = title,
			detail = detail,
			progress = progress,
			setProgress = setProgress,
			equip = equip,
			equipped = equipped,
		}
	end

	local function updateSkin(r: any, row: SlimeDex.SkinRow)
		local skin = row.skin
		r.instance:SetAttribute("Locked", row.locked)
		r.instance:SetAttribute("SkinId", skin.id)
		r.equip.instance.Visible = skin.unlocked and not skin.equipped
		r.equipped.Visible = skin.equipped
		r.image.BackgroundColor3 = Widgets.color3(row.color)
		r.lock.Visible = not skin.unlocked
		r.skinIcon.setFrame(if skin.unlocked then nil else Theme.Muted)
		r.skinIcon.setActive(open)
		r.title.Text = row.title
		r.title.TextColor3 = if skin.unlocked then Theme.Text else Theme.Muted
		r.detail.Text = row.detail
		r.progress.Visible = row.locked
		r.setProgress(row.fraction)
		-- Locked: name, unlock text and bar; otherwise name and set centred beside the button / stamp.
		local right = if skin.equipped then SKIN.stampW elseif skin.unlocked then SKIN.equipW else 0
		local textW = -(r.textX + SKIN.pad + (if right > 0 then right + SKIN.gap else 0))
		local blockH = SKIN.titleH + 2 + SKIN.detailH + (if row.locked then 6 + SKIN.bar else 0)
		local y = (SKIN.h - blockH) // 2
		r.title.Position = UDim2.fromOffset(r.textX, y)
		r.title.Size = UDim2.new(1, textW, 0, SKIN.titleH)
		r.detail.Position = UDim2.fromOffset(r.textX, y + SKIN.titleH + 2)
		r.detail.Size = UDim2.new(1, textW, 0, SKIN.detailH)
		r.progress.Position = UDim2.fromOffset(r.textX, y + SKIN.titleH + 2 + SKIN.detailH + 6)
	end

	-- List rows: the plot skins heading and rows, rarity headers and card lines (SlimeDex.lines).
	type Item = { key: string, heading: string?, skin: SlimeDex.SkinRow?, line: SlimeDex.Line? }

	local rows = Widgets.keyedList(list, function(item: Item)
		return item.key
	end, function(item: Item)
		if item.skin then
			return makeSkin(item.skin)
		end
		if item.heading or (item.line and item.line.kind == "header") then
			return headingRow(item.key)
		end
		local line = item.line :: SlimeDex.Line
		local frame = create("Frame", {
			Name = line.key,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -STYLE.scrollBar, 0, C.h),
		})
		return { instance = frame }
	end, function(r: any, item: Item)
		r.item = item
		if item.skin then
			updateSkin(r, item.skin)
			return
		end
		if item.heading then
			r.title.Text = item.heading
			r.title.TextColor3 = Theme.Text
			r.detail.Visible = false
			return
		end
		local line = item.line :: SlimeDex.Line
		if line.kind == "header" then
			local rarity = ctx.Config.RARITIES[line.tier]
			r.title.Text = line.title or ""
			r.title.TextColor3 = if rarity then Widgets.color3(rarity.color) else Theme.Gold
			r.detail.Text = line.detail or ""
			r.detail.Visible = line.detail ~= nil
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
			table.insert(parts, `{row.key}|{row.locked}|{row.detail}|{row.fraction}|{row.skin.equipped}`)
		end
		for _, card in pendingCards do
			local slots = {}
			for _, slot in card.slots or {} do
				table.insert(slots, slot.species or "")
			end
			table.insert(parts, `{card.key}|{card.found}|{card.title}|{card.hint or ""}|{table.concat(slots, ",")}`)
		end
		return table.concat(parts, "\n")
	end

	local function rebuild()
		if open and dirty and hasState then
			dirty = false
			builtSignature = pendingSignature
			builds += 1
			local items: { Item } = {}
			if #pendingSkins > 0 then
				table.insert(items, { key = "skins:header", heading = "Plot skins" })
			end
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
		placeHeader()
		placeMilestone()
		Widgets.restack(list)
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
		chips[1].Text = summary.count
		chips[2].Text = summary.secrets or ""
		placeHeader()
		local rc = SlimeDex.rewardCard(state)
		if rc and not mile then
			mile = buildMilestone()
		end
		if mile then
			mile.card.Visible = rc ~= nil
			if rc then
				local rewards = Progress.dexRewards(state)
				local friendLine = FriendBadge.line(state.friends, ctx.Config.FEATURES.FriendBonus == true)
				paintMilestone(rc, Progress.incomeLine(rewards.dexPercent, friendLine))
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
