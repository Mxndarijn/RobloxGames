--!strict
--[[
	Slimedex panel: completion up top (big percent, bar, discovered/dexTotal,
	per-rarity counts; see Progress.dex), the v13 next dex reward + income
	bonus when the server sends them, and a scrollable list of the
	discovered Genome.dexKey values.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Progress = require(UI.Progress)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Dex = {}

local HEADER = 108

function Dex.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "DexPanel", "Slimedex", UDim2.fromOffset(420, 480), UDim2.new(0, 96, 0.5, -240))

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
	local _, setBar = Widgets.bar(panel.body, Theme.Accent, UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 46))

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
	}, 2)

	local rows = Widgets.keyedList(list, function(key: string)
		return key
	end, function(key: string)
		local tier = tonumber(string.match(key, "^(%d+):"))
		local rarity = tier and ctx.Config.RARITIES[tier]
		local label = Widgets.label({
			Name = key,
			Text = Format.dexLabel(key, tierNames),
			TextSize = 14,
			TextColor3 = if rarity then Widgets.color3(rarity.color) else Theme.Text,
			Size = UDim2.new(1, -10, 0, 22),
			BackgroundTransparency = 0.4,
			BackgroundColor3 = Theme.Row,
		})
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = label })
		return { instance = label }
	end, function() end)

	local self = { frame = panel.frame }

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
		rewardLine.Visible = rewards.next ~= nil
		if rewards.next then
			rewardLine.Text = if rewards.bonus then `{rewards.next}\n{rewards.bonus}` else rewards.next
		end
		local top = HEADER + 4 + (if rewards.next then 36 else 0)
		list.Position = UDim2.fromOffset(0, top)
		list.Size = UDim2.new(1, 0, 1, -top)
		rows.sync(state.dex or {})
	end

	return self
end

return Dex
