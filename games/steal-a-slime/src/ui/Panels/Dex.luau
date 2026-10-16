--!strict
--[[
	SlimeDex panel (Nav key "Dex"): completion up top (big percent, bar,
	discovered/dexTotal, per-rarity counts; see Progress.dex), the v13 next
	dex reward + income bonus when the server sends them, and a scrollable
	list with a picture per discovered slime and silhouettes for the rest
	(SlimeDex.rows). v28 pictures: an uploaded image when SlimeDex.IMAGES
	has one, else a ViewportFrame of the real in-world slime model
	(`ctx.buildSlime` = Visuals.ModelFactory.build, init.client), else the
	SlimePreview blob, else the colour swatch.

	The list (and its previews) is only rebuilt while the panel is open:
	update() while closed just marks it dirty, and setOpen(true) rebuilds
	if dirty or never built. layout(rect) gets the panel box: on a short
	body the header drops rows (SlimeDex.header) so the list keeps room.
]]

local UI = script.Parent.Parent
local FriendBadge = require(UI.FriendBadge)
local Layout = require(UI.Layout)
local Progress = require(UI.Progress)
local SlimeDex = require(UI.SlimeDex)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Dex = {}

local HEADER = SlimeDex.HEADER.tiers
local ROW = 72 -- row height (SlimeDex.MIN_LIST)
local TIER_ROWS_H = SlimeDex.HEADER.tiers - SlimeDex.HEADER.bar - 2 -- three rows of 18 + 4 gaps (7 rarities, 3 per row)
local PREVIEW_MARGIN = ROW * 3 -- rows this far past the scroll window keep their preview
local IMAGE = 64 -- square picture / silhouette at the left of a row

function Dex.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "DexPanel", "SlimeDex", "📖", Color3.fromRGB(150, 90, 220))

	local percent = Widgets.label({
		Name = "Percent",
		Font = Theme.Font,
		TextSize = 34,
		TextColor3 = Theme.Accent,
		Size = UDim2.fromOffset(110, 40),
		Parent = panel.body,
	})
	local count = Widgets.label({
		Name = "Count",
		Font = Theme.Font,
		TextSize = 16,
		Size = UDim2.new(1, -116, 0, 20),
		Position = UDim2.fromOffset(116, 2),
		Parent = panel.body,
	})
	Widgets.label({
		Name = "Caption",
		Text = "complete",
		TextSize = 13,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, -116, 0, 16),
		Position = UDim2.fromOffset(116, 22),
		Parent = panel.body,
	})
	local bar, setBar = Widgets.bar(panel.body, Theme.Accent, UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 46))

	local tierNames: { string } = {}
	for i, rarity in ctx.Config.RARITIES do
		tierNames[i] = rarity.name
	end

	-- Per-rarity counts: one small cell per tier, three per row.
	local grid = create("Frame", {
		Name = "Tiers",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, TIER_ROWS_H),
		Position = UDim2.fromOffset(0, SlimeDex.HEADER.bar + 2),
		Parent = panel.body,
	}, {
		create("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -4, 0, 18),
			CellPadding = UDim2.fromOffset(4, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local tierCells: { TextLabel } = {}
	for i, name in tierNames do
		local rarity = ctx.Config.RARITIES[i]
		tierCells[i] = Widgets.label({
			Name = name,
			LayoutOrder = i,
			TextSize = 13,
			TextColor3 = Widgets.color3(rarity.color),
			Parent = grid,
		})
	end

	local rewardLine = Widgets.label({
		Name = "Rewards",
		Visible = false,
		TextSize = 13,
		TextColor3 = Theme.Gold,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, HEADER),
		Parent = panel.body,
	})

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, HEADER + 4),
		Size = UDim2.new(1, 0, 1, -(HEADER + 4)),
		Parent = panel.body,
	}, 4)

	local hasRewards = false
	-- Body height from layout(); nil = tall enough for the full header.
	local bodyH: number? = nil
	local function placeList()
		local header = SlimeDex.header(bodyH or math.huge, hasRewards)
		bar.Visible = header.bar
		grid.Visible = header.tiers
		rewardLine.Visible = header.rewards
		rewardLine.Position = UDim2.fromOffset(0, header.rewardsY)
		list.Position = UDim2.fromOffset(0, header.listTop)
		list.Size = if bodyH and bodyH < header.listTop
			then UDim2.fromScale(1, 0)
			else UDim2.new(1, 0, 1, -header.listTop)
	end

	-- One row per discovered slime (preview / image + name) and one
	-- silhouette row per tier for the rest (SlimeDex.rows). ViewportFrames
	-- are virtualised (refreshPreviews): only rows in or near the scroll
	-- window are mounted, at most SlimePreview.MAX_LIVE at once.
	local rows = Widgets.keyedList(list, function(row: SlimeDex.Row)
		return row.key
	end, function(row: SlimeDex.Row)
		local frame = create("Frame", {
			Name = row.key,
			Size = UDim2.new(1, -10, 0, ROW),
			BackgroundTransparency = 0.2,
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(12) })
		local image = create("Frame", {
			Name = "Image",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(IMAGE, IMAGE),
			Parent = frame,
		}, { Widgets.corner(14) })
		local picture = create("ImageLabel", {
			Name = "Picture",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
			Parent = image,
		})
		local preview = create("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Visible = false,
			Parent = image,
		})
		local glyph = Widgets.label({
			Name = "Glyph",
			Text = "?",
			Font = Theme.Font,
			TextSize = 28,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
			Size = UDim2.fromScale(1, 1),
			Parent = image,
		})
		local title = Widgets.label({
			Name = "Title",
			Font = Theme.Font,
			TextSize = 16,
			Position = UDim2.fromOffset(IMAGE + 12, 14),
			Size = UDim2.new(1, -(IMAGE + 20), 0, 22),
			Parent = frame,
		})
		local detail = Widgets.label({
			Name = "Detail",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(IMAGE + 12, 40),
			Size = UDim2.new(1, -(IMAGE + 20), 0, 18),
			Parent = frame,
		})
		-- Plot skin cards only (SlimeDex.skinRows): Equip / Equipped / locked.
		local equip = Widgets.button(
			{
				Name = "Equip",
				Text = "Equip",
				TextSize = 14,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(78, 32),
				Visible = false,
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
			equip = equip,
			image = image,
			picture = picture,
			preview = preview,
			glyph = glyph,
			title = title,
			detail = detail,
		}
	end, function(r: any, row: SlimeDex.Row)
		r.instance:SetAttribute("Locked", row.locked)
		r.instance:SetAttribute("SkinId", if row.skin then row.skin.id else nil)
		local skin = row.skin
		r.equip.instance.Visible = skin ~= nil
		r.title.Size = UDim2.new(1, -(IMAGE + 20 + if skin then 84 else 0), 0, 22)
		r.detail.Size = UDim2.new(1, -(IMAGE + 20 + if skin then 84 else 0), 0, 18)
		if skin then
			r.equip.setText(if skin.equipped then "Equipped" elseif skin.unlocked then "Equip" else "Locked")
			r.equip.setEnabled(skin.unlocked and not skin.equipped)
		end
		r.image.BackgroundColor3 = Widgets.color3(row.color)
		r.picture.Image = row.image or ""
		local hasImage = row.image ~= nil
		r.picture.Visible = hasImage
		r.glyph.Visible = row.locked and not hasImage
		-- An uploaded picture wins; else refreshPreviews mounts a ViewportFrame
		-- (the real slime model, or the blob if that fails) while the row is in
		-- the scroll window; else (or if both fail) the colour swatch.
		if skin then
			if r.preview:GetAttribute("Look") ~= nil then
				SlimePreview.unmount(r.preview)
				r.preview:SetAttribute("Look", nil)
				r.preview.Visible = false
			end
			r.glyph.Visible = true
			r.glyph.Text = if skin.unlocked then "🏡" else "🔒"
			r.image.BackgroundTransparency = 0
		end
		r.row = row
		r.title.Text = row.title
		local rarity = ctx.Config.RARITIES[row.tier]
		r.title.TextColor3 = if skin
			then (if skin.unlocked then Theme.Text else Theme.Muted)
			elseif row.locked or not rarity then Theme.Muted
			else Widgets.color3(rarity.color)
		r.detail.Text = row.detail
	end)

	-- Rows from the latest update and whether the list is out of date with
	-- them (never built counts as dirty). Rebuilds only happen while open.
	local open = false
	local pending: { SlimeDex.Row }? = nil
	local pendingSignature: string? = nil
	local builtSignature: string? = nil
	local dirty = true
	local builds = 0

	local function signature(items: { SlimeDex.Row }): string
		local parts = table.create(#items)
		for i, row in items do
			parts[i] =
				`{row.key}|{row.locked}|{row.title}|{row.detail}|{row.image or ""}|{table.concat(row.color, ",")}`
		end
		return table.concat(parts, "\n")
	end

	-- Mounts the ViewportFrame of every row in or near the scroll window
	-- (nearest the window centre first, at most SlimePreview.MAX_LIVE) and
	-- unmounts the rest, so a row at any index shows its live slime once
	-- scrolled to. A row's viewport is reused and only remounted when its look
	-- changes (a failed look is not retried).
	local function viewHeight(): number
		-- From the card (init.client sizes its frame in offsets), not
		-- AbsoluteSize: that is 0 until the first layout pass.
		local c = Layout.PANEL_CHROME
		return math.max(panel.frame.Size.Y.Offset - c.header - c.pad - list.Position.Y.Offset, ROW)
	end

	local function mountLook(r: any, row: SlimeDex.Row)
		local look = `{row.key}:{row.locked}:{table.concat(row.color, ",")}`
		if r.preview:GetAttribute("Look") == look then
			return
		end
		local opts = { locked = row.locked, mutation = row.mutation }
		local ok = false
		local genome = SlimeDex.genome(row)
		if ctx.buildSlime and genome then
			local built, model = pcall(ctx.buildSlime, genome)
			ok = built and model ~= nil and SlimePreview.mountModel(r.preview, model, opts)
		end
		if not ok then
			ok = SlimePreview.mount(r.preview, row.color, opts)
		end
		r.preview:SetAttribute("Look", look)
		r.preview.Visible = ok
		-- A rendered slime sits on a soft tile, not a flat colour block.
		r.image.BackgroundTransparency = if ok then 0.55 else 0
	end

	local function unmountLook(r: any)
		if r.preview:GetAttribute("Look") ~= nil then
			SlimePreview.unmount(r.preview)
			r.preview:SetAttribute("Look", nil)
			r.preview.Visible = false
		end
		r.image.BackgroundTransparency = 0
	end

	local function refreshPreviews()
		if not open then
			return
		end
		local top = list.CanvasPosition.Y - PREVIEW_MARGIN
		local bottom = list.CanvasPosition.Y + viewHeight() + PREVIEW_MARGIN
		local middle = (top + bottom) / 2
		local near: { { r: any, dist: number } } = {}
		for _, r in rows.rows do
			local y = r.instance.Position.Y.Offset
			local mine: SlimeDex.Row = r.row
			if mine and mine.skin == nil and not mine.image and y + ROW > top and y < bottom then
				table.insert(near, { r = r, dist = math.abs(y + ROW / 2 - middle) })
			else
				unmountLook(r)
			end
		end
		table.sort(near, function(a, b)
			return a.dist < b.dist
		end)
		for i, entry in near do
			if i <= SlimePreview.MAX_LIVE then
				mountLook(entry.r, entry.r.row)
			else
				unmountLook(entry.r)
			end
		end
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshPreviews)

	local function rebuild()
		if open and dirty and pending then
			dirty = false
			builtSignature = pendingSignature
			builds += 1
			rows.sync(pending)
			refreshPreviews()
		end
	end

	local self = { frame = panel.frame, close = panel.close }

	-- Called by init.client when the menu opens / closes.
	function self.setOpen(isOpen: boolean)
		open = isOpen
		rebuild()
	end

	-- Called by init.client with the panel box (Layout.panelFor).
	function self.layout(r: Layout.Rect)
		bodyH = Layout.panelBody(r).h
		placeList()
	end

	-- Live (mounted) slime previews now, and a manual refresh (tests).
	function self.liveCount(): number
		local n = 0
		for _, r in rows.rows do
			if r.preview:GetAttribute("Look") ~= nil then
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

	function self.update(state: any)
		local progress = Progress.dex(state.dex, state.dexTotal, tierNames)
		percent.Text = progress.percent
		count.Text = `Discovered {progress.count} / {progress.total}`
		setBar(progress.fraction)
		for i, cell in tierCells do
			local t = progress.byTier[i]
			cell.Text = if t.total then `{t.name} {t.count}/{t.total}` else `{t.name} {t.count}`
		end
		local rewards = Progress.dexRewards(state)
		hasRewards = rewards.next ~= nil
		if rewards.next then
			local friendLine = FriendBadge.line(state.friends, ctx.Config.FEATURES.FriendBonus == true)
			local bonus = Progress.incomeLine(rewards.dexPercent, friendLine)
			rewardLine.Text = if bonus then `{rewards.next}\n{bonus}` else rewards.next
		end
		placeList()
		local items = SlimeDex.rows(state.dex, state.dexTotal, ctx.Config)
		local skins = SlimeDex.skinRows(state.plotSkins, ctx.Config)
		if #skins > 0 then
			table.move(items, 1, #items, #skins + 1)
			table.move(skins, 1, #skins, 1, items)
		end
		pending = items
		pendingSignature = signature(items)
		dirty = pendingSignature ~= builtSignature
		rebuild()
	end

	return self
end

return Dex
