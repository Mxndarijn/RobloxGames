--!strict
--[[
	SlimeDex panel (Nav key "Dex"): completion up top (big percent, bar,
	discovered/dexTotal, per-rarity counts; see Progress.dex), the v13 next
	dex reward + income bonus when the server sends them, and a scrollable
	list with a ViewportFrame preview (or image / colour swatch) per
	discovered slime and silhouettes for the rest (SlimeDex.rows).

	The list (and its previews) is only rebuilt while the panel is open:
	update() while closed just marks it dirty, and setOpen(true) rebuilds
	if dirty or never built. layout(rect) gets the panel box: on a short
	body the header drops rows (SlimeDex.header) so the list keeps room.
]]

local UI = script.Parent.Parent
local Layout = require(UI.Layout)
local Progress = require(UI.Progress)
local SlimeDex = require(UI.SlimeDex)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Dex = {}

local HEADER = SlimeDex.HEADER.tiers
local ROW = 64 -- row height
local IMAGE = 56 -- square picture / silhouette at the left of a row

function Dex.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "DexPanel", "SlimeDex")

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

	-- Per-rarity counts: one small cell per tier, two rows of three.
	local grid = create("Frame", {
		Name = "Tiers",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 66),
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
	-- are capped (SlimePreview.MAX_LIVE); further rows keep the swatch.
	local rows = Widgets.keyedList(list, function(row: SlimeDex.Row)
		return row.key
	end, function(row: SlimeDex.Row)
		local frame = create("Frame", {
			Name = row.key,
			Size = UDim2.new(1, -10, 0, ROW),
			BackgroundTransparency = 0.4,
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(8) })
		local image = create("Frame", {
			Name = "Image",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(IMAGE, IMAGE),
			Parent = frame,
		}, { Widgets.corner(18) })
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
			TextSize = 15,
			Position = UDim2.fromOffset(IMAGE + 12, 10),
			Size = UDim2.new(1, -(IMAGE + 20), 0, 22),
			Parent = frame,
		})
		local detail = Widgets.label({
			Name = "Detail",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(IMAGE + 12, 34),
			Size = UDim2.new(1, -(IMAGE + 20), 0, 18),
			Parent = frame,
		})
		return {
			instance = frame,
			image = image,
			picture = picture,
			preview = preview,
			glyph = glyph,
			title = title,
			detail = detail,
		}
	end, function(r: any, row: SlimeDex.Row, index: number)
		r.instance:SetAttribute("Locked", row.locked)
		r.image.BackgroundColor3 = Widgets.color3(row.color)
		r.picture.Image = row.image or ""
		local hasImage = row.image ~= nil
		r.picture.Visible = hasImage
		r.glyph.Visible = row.locked and not hasImage
		-- Prefer an uploaded picture; else a ViewportFrame preview while under
		-- the live cap; else (or if the mount fails) the colour swatch. The
		-- row's viewport is reused and only remounted when its look changes.
		if not hasImage and index <= SlimePreview.MAX_LIVE then
			local look = `{row.locked}:{row.mutation or ""}:{table.concat(row.color, ",")}`
			if r.preview:GetAttribute("Look") ~= look then
				local ok = SlimePreview.mount(r.preview, row.color, { locked = row.locked, mutation = row.mutation })
				r.preview:SetAttribute("Look", look) -- a failed look is not retried
				r.preview.Visible = ok
			end
		elseif r.preview:GetAttribute("Look") ~= nil then
			SlimePreview.unmount(r.preview)
			r.preview:SetAttribute("Look", nil)
			r.preview.Visible = false
		end
		r.title.Text = row.title
		local rarity = ctx.Config.RARITIES[row.tier]
		r.title.TextColor3 = if row.locked or not rarity then Theme.Muted else Widgets.color3(rarity.color)
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

	local function rebuild()
		if open and dirty and pending then
			dirty = false
			builtSignature = pendingSignature
			builds += 1
			rows.sync(pending)
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
			rewardLine.Text = if rewards.bonus then `{rewards.next}\n{rewards.bonus}` else rewards.next
		end
		placeList()
		local items = SlimeDex.rows(state.dex, state.dexTotal, ctx.Config)
		pending = items
		pendingSignature = signature(items)
		dirty = pendingSignature ~= builtSignature
		rebuild()
	end

	return self
end

return Dex
