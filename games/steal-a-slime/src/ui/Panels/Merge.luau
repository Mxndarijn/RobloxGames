--!strict
--[[
	Merge panel: tap two slimes of the same tier, then Merge ->
	Request("Merge", a, b). The button is disabled while the pair is invalid
	(Selection.canMergePair); the server makes the final call.
	FEATURES.MergeVat3: a "2 slimes / 3 slimes" switch on top. In 3-slime mode three slimes of one tier
	-> Request("Merge3", a, b, c); the status line shows the odds (TripleMerge.odds). Off = the panel
	is exactly the two-slime one (no switch, nothing moves).
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

	-- The 3-slime vat: the flag (or the Studio-only PcwMergeVat shot override); read again on every update.
	local function tripleOn(): boolean
		return ctx.TripleMerge ~= nil
			and (ctx.Config.FEATURES.MergeVat3 == true or (ctx.vat3Forced ~= nil and ctx.vat3Forced() == true))
	end
	local triple = false
	local mode = 2 -- slimes the vat takes (3 only while the vat is on)
	local top = 0 -- room for the 2 / 3 switch
	local setMode: (number) -> ()

	local hint = Widgets.label({
		Name = "Hint",
		Text = "Pick 2 of the same rarity → 1 rarer slime",
		TextColor3 = Theme.Muted,
		TextSize = 13,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = panel.body,
	})
	hint.TextYAlignment = Enum.TextYAlignment.Top

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, top + 36),
		Size = UDim2.new(1, 0, 1, -116 - top),
		Parent = panel.body,
	}, 4)

	local modeButtons: { [number]: any } = {}
	do
		for i, count in { 2, 3 } do
			local btn = Widgets.button(
				{
					Name = `Mode{count}`,
					Text = `{count} slimes`,
					Size = UDim2.new(0.5, -3, 0, 30),
					Position = UDim2.new(if i == 1 then 0 else 0.5, if i == 1 then 0 else 3, 0, 0),
					Parent = panel.body,
				},
				Theme.Row,
				function()
					setMode(count)
				end
			)
			modeButtons[count] = btn
		end
	end

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
			if mode == 3 then
				local ids = { selected[1], selected[2], selected[3] }
				if Selection.canMergeTriple(slimes, ids) then
					selected = {}
					ctx.send("Merge3", ids[1], ids[2], ids[3])
					refresh()
				end
				return
			end
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
				selected = Selection.toggle(selected, id, mode)
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
		local ok = if mode == 3
			then Selection.canMergeTriple(slimes, selected)
			else Selection.canMergePair(slimes, selected[1], selected[2])
		mergeBtn.setEnabled(ok)
		if ok then
			local a = Selection.findSlime(slimes, selected[1])
			local tier = if a then a.slime.tier else 1
			local nextTier = math.min(tier + 1, ctx.Config.MAX_TIER)
			local rarity = ctx.Config.RARITIES[nextTier]
			status.Text = `✨ You get: {if rarity then rarity.name else "?"}`
			if mode == 3 then
				local odds = ctx.TripleMerge.odds(tier)
				local jump = if odds.jumpTier then ctx.Config.RARITIES[odds.jumpTier] else nil
				if jump then
					status.Text ..= ` · {math.floor(odds.jumpChance * 100 + 0.5)}% {jump.name}`
				end
			end
			status.TextColor3 = Theme.Accent
		else
			status.Text = `{#selected}/{mode} picked`
			status.TextColor3 = Theme.Muted
		end
	end

	function setMode(count: number)
		mode = count
		while #selected > mode do
			table.remove(selected, 1)
		end
		hint.Text = if count == 3
			then "Pick 3 of the same rarity → 1 rarer slime (maybe 2 up), keeps every mutation"
			else "Pick 2 of the same rarity → 1 rarer slime"
		mergeBtn.setText(if count == 3 then "🧪 Merge 3" else "🧪 Merge")
		for n, btn in modeButtons do
			btn.instance.BackgroundColor3 = if n == count then Theme.Accent else Theme.Row
			btn.instance.TextColor3 = if n == count then Color3.fromRGB(20, 40, 25) else Theme.Text
		end
		refresh()
	end

	local self = { frame = panel.frame, close = panel.close }

	-- Shows / hides the 2 / 3 switch and moves hint and list under it (once per change of the flag state).
	local function layout()
		local on = tripleOn()
		if on == triple then
			return
		end
		triple = on
		top = if on then 34 else 0
		hint.Position = UDim2.fromOffset(0, top)
		list.Position = UDim2.fromOffset(0, top + 36)
		list.Size = UDim2.new(1, 0, 1, -116 - top)
		for _, btn in modeButtons do
			btn.instance.Visible = on
		end
		-- Forced for a shot: open in 3-slime mode so the picture shows the new panel.
		setMode(if on and ctx.vat3Forced ~= nil and ctx.vat3Forced() == true then 3 else 2)
	end

	function self.update(state: any)
		slimes = state.slimes
		layout()
		refresh()
	end

	return self
end

return Merge
