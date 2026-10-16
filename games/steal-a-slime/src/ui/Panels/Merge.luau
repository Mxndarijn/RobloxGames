--!strict
--[[
	Merge panel: tap two slimes of the same tier, then Merge ->
	Request("Merge", a, b). The button is disabled while the pair is invalid
	(Selection.canMergePair); the server makes the final call.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Selection = require(UI.Selection)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Merge = {}

function Merge.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "MergePanel", "Merge Vat", "🧪", Color3.fromRGB(60, 170, 150))

	local hint = Widgets.label({
		Name = "Hint",
		Text = "Pick 2 of the same rarity → 1 rarer slime",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 32),
		Parent = panel.body,
	})
	hint.TextYAlignment = Enum.TextYAlignment.Top

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -116),
		Parent = panel.body,
	}, 4)

	local status = Widgets.label({
		Name = "Status",
		Text = "",
		TextColor3 = Theme.Muted,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -48),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = panel.body,
	})

	local selected: { string } = {}
	local slimes: { any } = {}
	local refresh: () -> ()

	local mergeBtn = Widgets.holdButton(
		{
			Name = "MergeButton",
			Text = "🧪 Merge",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 40),
			TextSize = 18,
		},
		Theme.Accent,
		function()
			local a, b = selected[1], selected[2]
			if Selection.canMergePair(slimes, a, b) then
				selected = {}
				ctx.send("Merge", a, b)
				refresh()
			end
		end,
		ctx.Config.HOLD_CONFIRM_SECONDS
	)
	mergeBtn.instance.TextColor3 = Color3.fromRGB(20, 40, 25)
	mergeBtn.instance.Parent = panel.body

	local function makeRow(view: any)
		local id = view.slime.id
		local btn = create("TextButton", {
			Name = id,
			Text = "",
			AutoButtonColor = true,
			Size = UDim2.new(1, -10, 0, 40),
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(8) })
		local swatch = create("Frame", {
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.fromOffset(8, 7),
			Parent = btn,
		}, { Widgets.corner(13) })
		local name = Widgets.label({
			Size = UDim2.new(1, -150, 1, 0),
			Position = UDim2.fromOffset(42, 0),
			Font = Theme.Font,
			Parent = btn,
		})
		local info = Widgets.label({
			TextColor3 = Theme.Muted,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 110, 1, 0),
			Parent = btn,
		})
		local row = { instance = btn, swatch = swatch, name = name, info = info, stolen = false }
		btn.Activated:Connect(function()
			if not row.stolen then
				selected = Selection.toggle(selected, id, 2)
				refresh()
			end
		end)
		return row
	end

	local function updateRow(row: any, view: any)
		local slime = view.slime
		local rarity = ctx.Config.RARITIES[slime.tier]
		local isSelected = table.find(selected, slime.id) ~= nil
		row.stolen = view.stolenBy ~= nil
		row.swatch.BackgroundColor3 = Widgets.color3(slime.color)
		row.name.Text = (if isSelected then "✅ " else "") .. ctx.Genome.displayName(slime)
		row.name.TextColor3 = if rarity then Widgets.color3(rarity.color) else Theme.Text
		row.info.Text = if row.stolen then "being stolen" else `T{slime.tier} · {Format.formatRate(view.income)}`
		row.instance.BackgroundColor3 = if isSelected
			then Color3.fromRGB(60, 120, 80)
			elseif row.stolen then Theme.Disabled
			else Theme.Row
	end

	local rows = Widgets.keyedList(list, function(view: any)
		return view.slime.id
	end, makeRow, updateRow)

	function refresh()
		selected = Selection.prune(selected, slimes)
		local sorted = Selection.sorted(slimes, nil)
		rows.sync(sorted)
		local ok = Selection.canMergePair(slimes, selected[1], selected[2])
		mergeBtn.setEnabled(ok)
		if ok then
			local a = Selection.findSlime(slimes, selected[1])
			local tier = if a then a.slime.tier else 1
			local nextTier = math.min(tier + 1, ctx.Config.MAX_TIER)
			local rarity = ctx.Config.RARITIES[nextTier]
			status.Text = `✨ You get: {if rarity then rarity.name else "?"}`
			status.TextColor3 = Theme.Accent
		else
			status.Text = `{#selected}/2 picked`
			status.TextColor3 = Theme.Muted
		end
	end

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		slimes = state.slimes
		refresh()
	end

	return self
end

return Merge
