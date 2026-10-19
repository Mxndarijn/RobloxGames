--!strict
--[[
	Merge menu (the plot's merge vat, CONTRACT.md §21 / §21.1). Opens from the vat prompt.

	Top: the vat. Three slots (two with FEATURES.MergeVat3 off), an arrow and the result card
	(Shared.MergePreview: "Random <Rarity> slime", the jump chance, the expected size), a reason
	line while the load is not valid, and the buttons: Pick for me (MergePlan.suggest), the hold-to-confirm
	Merge (Request "Merge3" / "Merge") and Auto-merge. Below: rarity filter chips and the slime list grouped
	by rarity (name, size, income; favourite / kept / stolen tags). Each row starts with a round avatar well
	holding the slime's 3D preview in a rarity-coloured ring (SlimePreview; the rows nearest the scroll window,
	at most SlimePreview.MAX_LIVE, the rest show a colour circle); filled slots show the same preview. Each row ends in two squares: Add (puts the
	slime in the vat, a gold tick once it is in, a sunken well while it can't go in) and the keep toggle that
	sends Request "KeepSlime" (gold padlock while kept).
	Auto-merge opens a confirm card: rarity toggles, what MergePlan would merge, and a hold-to-confirm button
	that sends Request("AutoMerge", mask). The client only suggests; the server plans again and decides.
	After a merge the slots fly into the result card, and once State brings the new slime the card reveals it.
	Short screens (landscape phones) put the vat in a column beside the list.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Layout = require(UI.Layout)
local Selection = require(UI.Selection)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MergePlan = require(Shared:WaitForChild("MergePlan") :: any)
local MergePreview = require(Shared:WaitForChild("MergePreview") :: any)

local TweenService = game:GetService("TweenService")

local Theme = Widgets.Theme
local KIT = Widgets.KIT
local create = Widgets.create

local SIZE = table.freeze({
	slot = 70,
	slotSmall = 56,
	slotInset = 8, -- a filled slot's avatar inside its well
	slotGap = 22, -- holds the "+" between two slots
	nameH = 18, -- slot caption under each slot
	arrowW = 26,
	orb = 54,
	orbSmall = 40,
	resultMin = 150,
	reasonH = 22,
	buttonH = Layout.MIN_TOUCH_DESIGN, -- thumb-sized on the smallest UI scale
	gap = 8,
	chipH = 40,
	chipGap = 6,
	headerH = 30,
	headerChipH = 22,
	headerChipSize = 12,
	rowInset = 10, -- row width = list width - inset (room for the scroll bar)
	rowH = Layout.MIN_TOUCH_DESIGN + 12,
	rowPad = 8,
	swatch = 42,
	avatarStroke = 3,
	nameY = 9,
	rowNameH = 22,
	infoY = 35,
	infoH = 18,
	sizeW = 62, -- the size figure; the income follows it
	selectedStroke = 3,
	dim = 0.45, -- text transparency of rows that can't join the picks
	dimSwatch = 0.5,
	keep = Layout.MIN_TOUCH_DESIGN,
	add = Layout.MIN_TOUCH_DESIGN,
	buttonGap = 6,
	tagW = 96,
	sideW = 262, -- vat column beside the list on short screens
	shortBody = 330, -- body heights below this use the side layout
	autoTierH = Layout.MIN_TOUCH_DESIGN,
	textBig = 22,
	textTitle = 16,
	text = 14,
	textSmall = 12,
	celebrate = 0.45, -- seconds the slots take to fly into the result
	reveal = 4, -- seconds the result card shows the new slime
	pendingTimeout = 6, -- seconds to wait for State to bring the new slime
})

-- Secret names: a rainbow over near-white text (a UIGradient multiplies the text colour).
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Bad),
	ColorSequenceKeypoint.new(0.25, Theme.Warn),
	ColorSequenceKeypoint.new(0.5, Theme.Gold),
	ColorSequenceKeypoint.new(0.75, Theme.Good),
	ColorSequenceKeypoint.new(1, Theme.Info),
})

-- A Widgets.button turned into a pill (filter chips).
local function pill(button: TextButton)
	for _, c in button:GetChildren() do
		if c:IsA("UICorner") then
			(c :: UICorner).CornerRadius = UDim.new(1, 0)
		end
	end
end

local Merge = {}

function Merge.new(parent: Instance, ctx: any)
	local Config = ctx.Config
	local Genome = ctx.Genome
	local panel = Widgets.panel(parent, "MergePanel", "Merge Vat", "🧪")
	local body = panel.body

	local function rarity(tier: number): any
		return Config.RARITIES[math.clamp(tier, 1, Config.MAX_TIER)]
	end
	local function rarityName(tier: number): string
		return rarity(tier).name
	end

	-- The 3-slime vat: the flag (or the Studio-only PcwMergeVat shot override); read again on every update.
	local function tripleOn(): boolean
		return ctx.Config.FEATURES.MergeVat3 == true or (ctx.vat3Forced ~= nil and ctx.vat3Forced() == true)
	end

	local state: any = nil
	local slimes: { any } = {}
	local selected: { string } = {}
	local count = if tripleOn() then 3 else 2
	local filter: number? = nil -- rarity chip; nil = all
	local compact = false
	local open = false
	-- The well behind a live preview (a slime without one shows its colour circle).
	local well = Theme.Row:Lerp(Theme.Ink, SlimePreview.WELL_TINT)
	local previewBuilders: SlimePreview.Builders = { species = ctx.buildSpecies, slime = ctx.buildSlime }
	local bodyW, bodyH = Layout.MENU_WIDTH - Layout.PANEL_CHROME.pad * 2, 460
	-- The tallest body this screen allows the card (its full menu height, clamped to the backdrop). The side
	-- layout follows this, not the content-sized body, so a short list never squeezes the vat into a column.
	local roomH = bodyH
	local autoTiers: { [number]: boolean } = { [1] = true, [2] = true }
	local allAutoTiers: { [number]: boolean } = {}
	for tier = 1, MergePlan.MAX_AUTO_TIER do
		allAutoTiers[tier] = true
	end
	local reveal: { title: string, sub: string, tier: number, untilAt: number }? = nil
	local pending: { ids: { string }, at: number, auto: boolean }? = nil
	local knownIds: { [string]: boolean } = {}
	local newIds: { [string]: number } = {} -- id -> os.clock() until it shows NEW
	local refresh: () -> ()
	local place: () -> ()

	---------------------------------------------------------------- the vat
	local vat = create("Frame", { Name = "Vat", BackgroundTransparency = 1, Parent = body })

	type Slot = {
		button: TextButton,
		stroke: UIStroke,
		swatch: Frame,
		preview: ViewportFrame,
		plus: TextLabel,
		name: TextLabel,
		join: TextLabel?,
	}
	local slots: { Slot } = {}
	for i = 1, 3 do
		local button = create("TextButton", {
			Name = `Slot{i}`,
			Text = "",
			AutoButtonColor = true,
			BackgroundColor3 = Theme.Ink,
			Parent = vat,
		}, { Widgets.corner(KIT.radius) }) :: TextButton
		local stroke = Widgets.stroke(Theme.Ink, KIT.stroke)
		stroke.Parent = button
		local swatch = create("Frame", {
			Name = "Swatch",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -SIZE.slotInset * 2, 1, -SIZE.slotInset * 2),
			Visible = false,
			Parent = button,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), Widgets.stroke(Theme.Ink, SIZE.avatarStroke) }) :: Frame
		Widgets.shade(swatch)
		local preview = create("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = swatch,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: ViewportFrame
		local plus = Widgets.label({
			Name = "Plus",
			Text = "+",
			Font = Theme.Font,
			TextSize = SIZE.textBig,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = button,
		})
		local name = Widgets.label({
			Name = `SlotName{i}`,
			Text = "",
			TextSize = SIZE.textSmall,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = vat,
		})
		local join = if i < 3
			then Widgets.label({
				Name = `Join{i}`,
				Text = "+",
				Font = Theme.Font,
				TextSize = SIZE.textBig,
				TextColor3 = Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = vat,
			})
			else nil
		slots[i] = {
			button = button,
			stroke = stroke,
			swatch = swatch,
			preview = preview,
			plus = plus,
			name = name,
			join = join,
		}
		button.Activated:Connect(function()
			local id = selected[i]
			if id then
				selected = Selection.toggle(selected, id, count)
				refresh()
			end
		end)
	end

	local arrow = Widgets.label({
		Name = "Arrow",
		Text = "→",
		Font = Theme.Font,
		TextSize = SIZE.textBig,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = vat,
	})

	local result = Widgets.rowFrame({
		Name = "Result",
		ClipsDescendants = true,
		Parent = vat,
	})
	local orb = create("Frame", {
		Name = "Orb",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Ink,
		Parent = result,
	}, { Widgets.corner(KIT.radius) }) :: Frame
	local orbScale = create("UIScale", { Scale = 1, Parent = orb }) :: UIScale
	local orbMark = Widgets.label({
		Name = "Mark",
		Text = "?",
		Font = Theme.Font,
		TextSize = SIZE.textBig,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = orb,
	})
	local resultTitle = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = SIZE.textTitle,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Parent = result,
	})
	local resultOdds = Widgets.label({
		Name = "Odds",
		TextSize = SIZE.textSmall,
		TextColor3 = Theme.Gold,
		Parent = result,
	})
	local resultKeeps = Widgets.label({
		Name = "Keeps",
		TextSize = SIZE.textSmall,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Parent = result,
	})
	resultTitle.TextYAlignment = Enum.TextYAlignment.Bottom
	resultKeeps.TextYAlignment = Enum.TextYAlignment.Top
	local flash = create("Frame", {
		Name = "Flash",
		BackgroundColor3 = Theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = result,
	}, { Widgets.corner(KIT.rowRadius) })

	local reason = Widgets.label({
		Name = "Reason",
		Text = "",
		TextSize = SIZE.text,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = vat,
	})

	local function sendMerge()
		local ok = Selection.vatLoad(slimes, selected, count, rarityName)
		if not ok then
			return
		end
		local ids = table.clone(selected)
		pending = { ids = ids, at = os.clock(), auto = false }
		if count == 3 then
			ctx.send("Merge3", ids[1], ids[2], ids[3])
		else
			ctx.send("Merge", ids[1], ids[2])
		end
		Merge.celebrate(slots, orbScale, flash)
		selected = {}
		task.delay(SIZE.celebrate, function()
			for _, slot in slots do
				slot.swatch.Size = UDim2.new(1, -SIZE.slotInset * 2, 1, -SIZE.slotInset * 2)
			end
			refresh()
		end)
	end

	local pickBtn = Widgets.button({ Name = "PickButton", TextSize = SIZE.text, Parent = vat }, Theme.Info, function()
		local suggestion = MergePlan.suggest(
			MergePlan.fromViews(slimes, state and state.favoriteId),
			filter or Merge.selectionTier(slimes, selected),
			count
		)
		if suggestion then
			selected = suggestion.ids
			reveal = nil
			refresh()
		end
	end)
	local mergeBtn = Widgets.holdButton(
		{ Name = "MergeButton", Text = "🧪 MERGE", TextSize = SIZE.textTitle + 2 },
		Theme.Good,
		sendMerge,
		Config.HOLD_CONFIRM_SECONDS
	)
	mergeBtn.instance.Parent = vat
	local autoBtn: any -- built below; opens the confirm card

	---------------------------------------------------------------- chips + list
	-- Rarity chips wrap onto more lines when they don't fit (chipsH is their height).
	local chips = create("Frame", { Name = "Chips", BackgroundTransparency = 1, Parent = body })
	local chipsH = SIZE.chipH
	local chipButtons: { [number]: any } = {}
	local function chipFor(tier: number): any
		local btn = chipButtons[tier]
		if btn then
			return btn
		end
		btn = Widgets.button(
			{
				Name = `Chip{tier}`,
				TextSize = SIZE.textSmall + 1,
				Size = UDim2.fromOffset(80, SIZE.chipH),
				Parent = chips,
			},
			Theme.Ink,
			function()
				filter = if tier == 0 then nil else tier
				refresh()
			end
		)
		pill(btn.instance)
		chipButtons[tier] = btn
		return btn
	end

	local list = Widgets.scrollList({ Name = "List", Parent = body }, 4)

	local function makeRow(item: any)
		if item.kind == "header" then
			local label = Widgets.label({
				Name = item.key,
				Font = Theme.Font,
				TextSize = SIZE.textTitle,
				TextTruncate = Enum.TextTruncate.None,
				Size = UDim2.new(1, -SIZE.rowInset, 0, SIZE.headerH),
			})
			local countChip = Widgets.chip({
				Name = "Count",
				Font = Theme.FontBody,
				TextSize = SIZE.headerChipSize,
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.fromOffset(0, SIZE.headerChipH),
				Parent = label,
			}, Theme.Muted)
			return { instance = label, header = true, chip = countChip }
		end
		local id = item.view.slime.id
		local btn = create("TextButton", {
			Name = id,
			Text = "",
			AutoButtonColor = true,
			Size = UDim2.new(1, -SIZE.rowInset, 0, SIZE.rowH),
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(KIT.rowRadius) })
		local stroke = Widgets.stroke(Theme.Ink, KIT.rowStroke)
		stroke.Parent = btn
		local swatch = create("Frame", {
			Name = "Swatch",
			Size = UDim2.fromOffset(SIZE.swatch, SIZE.swatch),
			Position = UDim2.fromOffset(SIZE.rowPad, (SIZE.rowH - SIZE.swatch) // 2),
			Parent = btn,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		Widgets.shade(swatch)
		local ring = Widgets.stroke(Theme.Ink, SIZE.avatarStroke)
		ring.Parent = swatch
		local preview = create("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = swatch,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local textX = SIZE.rowPad + SIZE.swatch + 10
		local rightW = SIZE.rowPad + SIZE.add + SIZE.buttonGap + SIZE.keep + SIZE.buttonGap
		local name = Widgets.label({
			Name = "Name",
			Font = Theme.Font,
			TextSize = SIZE.textTitle + 1,
			Position = UDim2.fromOffset(textX, SIZE.nameY),
			Size = UDim2.new(1, -(textX + rightW), 0, SIZE.rowNameH),
			Parent = btn,
		})
		local rainbow = create("UIGradient", { Name = "Rainbow", Color = RAINBOW, Enabled = false, Parent = name })
		local info = Widgets.label({
			Name = "Info",
			TextSize = SIZE.textSmall + 1,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(textX, SIZE.infoY),
			Size = UDim2.fromOffset(SIZE.sizeW, SIZE.infoH),
			Parent = btn,
		})
		local income = Widgets.label({
			Name = "Income",
			TextSize = SIZE.textSmall + 1,
			TextColor3 = Theme.Gold,
			Position = UDim2.fromOffset(textX + SIZE.sizeW, SIZE.infoY),
			Size = UDim2.new(1, -(textX + SIZE.sizeW + rightW), 0, SIZE.infoH),
			Parent = btn,
		})
		local tag = Widgets.label({
			Name = "Tag",
			Font = Theme.Font,
			TextSize = SIZE.textSmall,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -rightW, 0, SIZE.nameY),
			Size = UDim2.fromOffset(SIZE.tagW, SIZE.rowNameH),
			Parent = btn,
		})
		local row: any = {
			instance = btn,
			stroke = stroke,
			swatch = swatch,
			preview = preview,
			ring = ring,
			name = name,
			rainbow = rainbow,
			info = info,
			income = income,
			nameW = -(textX + rightW),
		}
		row.tag = tag
		local function pick()
			local view = row.view
			if view == nil then
				return
			end
			local blocked = Selection.blocked(view)
			if blocked then
				reason.Text = blocked
				reason.TextColor3 = Theme.Warn
				return
			end
			selected = Selection.pick(selected, id, slimes, count)
			reveal = nil
			refresh()
		end
		row.add = Widgets.button({
			Name = "Add",
			Text = "+",
			TextSize = SIZE.textBig,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -SIZE.rowPad, 0.5, 0),
			Size = UDim2.fromOffset(SIZE.add, SIZE.add),
			Parent = btn,
		}, Theme.Info, pick)
		row.keep = Widgets.button(
			{
				Name = "Keep",
				Text = "🔓",
				TextSize = SIZE.textTitle,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(SIZE.rowPad + SIZE.add + SIZE.buttonGap), 0.5, 0),
				Size = UDim2.fromOffset(SIZE.keep, SIZE.keep),
				Parent = btn,
			},
			Theme.Ink,
			function()
				if row.view then
					ctx.send("KeepSlime", id, not (row.view.slime.keep == true))
				end
			end
		)
		btn.Activated:Connect(pick)
		return row
	end

	-- A row's avatar: the well while its preview is live, else the slime's colour circle; faded with the row.
	local function paintAvatar(row: any)
		row.swatch.BackgroundColor3 = if row.preview.Visible then well else Widgets.color3(row.slime.color)
		local fade = if row.dim then SIZE.dimSwatch else 0
		row.swatch.BackgroundTransparency = fade
		row.preview.ImageTransparency = fade
	end

	local function updateRow(row: any, item: any)
		if row.header then
			local r = rarity(item.tier)
			local secret = item.tier == Config.SECRET_TIER
			local ready = if item.groups > 0
				then ` · {item.groups} merge{if item.groups == 1 then "" else "s"} ready`
				else ""
			row.instance.Text = `{r.name}{ready}`
			row.instance.TextColor3 = if secret then Theme.Text else Widgets.color3(r.color)
			if secret and row.rainbow == nil then
				row.rainbow = create("UIGradient", { Name = "Rainbow", Color = RAINBOW, Parent = row.instance })
			end
			row.chip.Text = `{item.count} slime{if item.count == 1 then "" else "s"}`
			local textW = Layout.textSize(row.instance.Text, SIZE.textTitle, true)
			row.chip.Position = UDim2.new(0, math.ceil(textW) + SIZE.gap, 0.5, 0)
			return
		end
		local view = item.view
		local slime = view.slime
		row.view = view
		local r = rarity(slime.tier)
		local secret = slime.tier == Config.SECRET_TIER
		local slot = table.find(selected, slime.id)
		local blocked = Selection.blocked(view)
		local otherTier = #selected > 0 and slot == nil and Merge.selectionTier(slimes, selected) ~= slime.tier
		local favourite = state and state.favoriteId == slime.id
		row.slime = slime
		row.ring.Color = Widgets.color3(r.color)
		row.name.Text = (if favourite then "⭐ " else "") .. tostring(slime.name)
		row.name.TextColor3 = if secret then Theme.Text else Widgets.color3(r.color)
		row.rainbow.Enabled = secret
		row.info.Text = `📏 {string.format("%.2f", slime.size or 1)}`
		row.income.Text = Format.formatRate(view.income or 0)
		local isNew = newIds[slime.id] ~= nil and newIds[slime.id] > os.clock()
		if slot then
			row.tag.Text, row.tag.TextColor3 = `IN SLOT {slot}`, Theme.Gold
		elseif view.stolenBy ~= nil then
			row.tag.Text, row.tag.TextColor3 = "🏃 being stolen", Theme.Bad
		elseif slime.keep then
			row.tag.Text, row.tag.TextColor3 = "kept", Theme.Muted
		elseif isNew then
			row.tag.Text, row.tag.TextColor3 = "✨ NEW", Theme.Gold
		else
			row.tag.Text = ""
		end
		row.name.Size = UDim2.new(1, row.nameW - (if row.tag.Text ~= "" then SIZE.tagW else 0), 0, SIZE.rowNameH)
		-- Add: lilac "+", a gold tick once in a slot, a sunken well while the slime can't go in.
		row.add.setEnabled(blocked == nil)
		if blocked then
			row.add.setText(if view.stolenBy ~= nil then "🏃" else "🔒")
		elseif slot then
			row.add.setColor(Theme.Gold)
			row.add.setText("✅")
		else
			row.add.setColor(Theme.Info)
			row.add.setText("+")
		end
		-- Keep: a gold padlock while kept, a sunken well with a muted open padlock when free (still pressable).
		row.keep.setText(if slime.keep then "🔒" else "🔓")
		row.keep.setColor(if slime.keep then Theme.Gold else Theme.Ink)
		if not slime.keep then
			row.keep.instance.TextColor3 = Theme.Muted
			row.keep.instance.TextStrokeTransparency = 1
		end
		row.stroke.Color = if slot then Theme.Gold else Theme.Ink
		row.stroke.Thickness = if slot then SIZE.selectedStroke else KIT.rowStroke
		local dim = blocked ~= nil or otherTier
		row.instance.BackgroundColor3 = if slot then Theme.BgLight elseif dim then Theme.Bg else Theme.Row
		local fade = if dim then SIZE.dim else 0
		row.name.TextTransparency = fade
		row.info.TextTransparency = fade
		row.income.TextTransparency = fade
		row.dim = dim
		paintAvatar(row)
	end

	local rows = Widgets.keyedList(list, function(item: any)
		return item.key
	end, makeRow, updateRow)

	-- Live previews for the slime rows nearest the middle of the scroll window (only while the card is open).
	local function refreshPreviews()
		if not open then
			return
		end
		local viewH = math.max(bodyH - list.Position.Y.Offset, 0)
		local entries: { SlimePreview.ListEntry } = {}
		for _, row in rows.rows do
			if not row.header then
				table.insert(entries, {
					viewport = row.preview,
					slime = row.slime,
					y = row.instance.Position.Y.Offset,
					h = row.instance.Size.Y.Offset,
				})
			end
		end
		SlimePreview.syncNearest(entries, list.CanvasPosition.Y + viewH / 2, previewBuilders)
		for _, row in rows.rows do
			if not row.header then
				paintAvatar(row)
			end
		end
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshPreviews)

	---------------------------------------------------------------- auto-merge confirm card
	local auto = create("Frame", {
		Name = "AutoCard",
		Visible = false,
		BackgroundColor3 = Theme.Bg,
		Active = true,
		Parent = body,
	}, { Widgets.corner(KIT.rowRadius), Widgets.stroke(Theme.Ink, KIT.rowStroke) })
	local autoTitle = Widgets.label({
		Name = "Title",
		Text = "⚡ Auto-merge",
		Font = Theme.Font,
		TextSize = SIZE.textBig - 2,
		TextColor3 = Theme.Info,
		Parent = auto,
	})
	local autoInfo = Widgets.label({
		Name = "Info",
		Text = "Merges your lowest-income slimes in groups of 3. Never uses ⭐ favourite or 🔒 kept slimes.",
		TextSize = SIZE.textSmall + 1,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Parent = auto,
	})
	autoInfo.TextYAlignment = Enum.TextYAlignment.Top
	local tierButtons: { [number]: any } = {}
	for tier = 1, MergePlan.MAX_AUTO_TIER do
		tierButtons[tier] = Widgets.button(
			{
				Name = `Tier{tier}`,
				TextSize = SIZE.textSmall + 1,
				Parent = auto,
			},
			Theme.Ink,
			function()
				autoTiers[tier] = not autoTiers[tier] or nil
				refresh()
			end
		)
	end
	local autoSummary = Widgets.label({
		Name = "Summary",
		TextSize = SIZE.text,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Parent = auto,
	})
	autoSummary.TextYAlignment = Enum.TextYAlignment.Top
	local function closeAuto()
		auto.Visible = false
		refresh()
	end
	local autoCancel = Widgets.button({ Name = "Cancel", Text = "Cancel", Parent = auto }, Theme.Bad, closeAuto)
	local autoConfirm = Widgets.holdButton(
		{ Name = "AutoConfirm", TextSize = SIZE.text, Text = "" },
		Theme.Good,
		function()
			local mask = MergePlan.maskOf(autoTiers)
			if mask > 0 then
				pending = { ids = {}, at = os.clock(), auto = true }
				ctx.send("AutoMerge", mask)
				Merge.celebrate(slots, orbScale, flash)
				selected = {}
				closeAuto()
			end
		end,
		Config.HOLD_CONFIRM_SECONDS
	)
	autoConfirm.instance.Parent = auto

	autoBtn = Widgets.button({ Name = "AutoButton", TextSize = SIZE.text, Parent = vat }, Theme.Info, function()
		auto.Visible = true
		refresh()
	end)

	---------------------------------------------------------------- layout
	function place()
		local w = bodyW
		compact = roomH < SIZE.shortBody
		local gap = SIZE.gap
		local vatW = if compact then math.min(SIZE.sideW, math.floor(w * 0.5)) else w
		local slotSize = if compact then SIZE.slotSmall else SIZE.slot
		local slotsW = count * slotSize + (count - 1) * SIZE.slotGap
		local orbSize = if compact then SIZE.orbSmall else SIZE.orb
		-- Stacked: slots, arrow and the result card in one row. Compact: slots on top, the card under them.
		local slotsY = 0
		local x = 0
		for i, slot in slots do
			local on = i <= count
			slot.button.Visible = on
			slot.name.Visible = on and not compact
			if slot.join then
				slot.join.Visible = i < count
			end
			if on then
				slot.button.Size = UDim2.fromOffset(slotSize, slotSize)
				slot.button.Position = UDim2.fromOffset(x, slotsY)
				slot.name.Size = UDim2.fromOffset(slotSize + SIZE.slotGap, SIZE.nameH)
				slot.name.Position = UDim2.fromOffset(x - SIZE.slotGap // 2, slotsY + slotSize + 2)
				if slot.join then
					slot.join.Size = UDim2.fromOffset(SIZE.slotGap, slotSize)
					slot.join.Position = UDim2.fromOffset(x + slotSize, slotsY)
				end
				x += slotSize + SIZE.slotGap
			end
		end
		local rowH = slotSize + (if compact then 0 else SIZE.nameH + 2)
		local resultX, resultY, resultW, resultH
		if compact then
			arrow.Visible = false
			resultX, resultY, resultW, resultH = 0, slotSize + gap, vatW, orbSize + 12
		else
			arrow.Visible = true
			arrow.Size = UDim2.fromOffset(SIZE.arrowW, slotSize)
			arrow.Position = UDim2.fromOffset(slotsW + 4, slotsY)
			resultX = slotsW + SIZE.arrowW + 8
			resultW = math.max(SIZE.resultMin, w - resultX)
			resultY, resultH = 0, rowH
		end
		result.Position = UDim2.fromOffset(resultX, resultY)
		result.Size = UDim2.fromOffset(resultW, resultH)
		orb.Size = UDim2.fromOffset(orbSize, orbSize)
		orb.Position = UDim2.new(0, 8, 0.5, 0)
		local textX = orbSize + 16
		resultTitle.Position = UDim2.fromOffset(textX, 4)
		resultTitle.Size = UDim2.new(1, -textX - 6, 0.42, -4)
		resultOdds.Position = UDim2.new(0, textX, 0.42, 0)
		resultOdds.Size = UDim2.new(1, -textX - 6, 0, 16)
		resultKeeps.Position = UDim2.new(0, textX, 0.42, 16)
		resultKeeps.Size = UDim2.new(1, -textX - 6, 0.58, -18)
		resultKeeps.Visible = not compact

		local reasonY = resultY + resultH + 4
		reason.Position = UDim2.fromOffset(0, reasonY)
		reason.Size = UDim2.fromOffset(vatW, SIZE.reasonH)
		local buttonsY = reasonY + SIZE.reasonH + 4
		local showAuto = count == 3
		autoBtn.instance.Visible = showAuto
		local mergeW = math.floor(vatW * (if showAuto then 0.44 else 0.6))
		local sideBtnW = math.floor((vatW - mergeW - gap * (if showAuto then 2 else 1)) / (if showAuto then 2 else 1))
		pickBtn.instance.Size = UDim2.fromOffset(sideBtnW, SIZE.buttonH)
		pickBtn.instance.Position = UDim2.fromOffset(0, buttonsY)
		mergeBtn.instance.Size = UDim2.fromOffset(mergeW, SIZE.buttonH)
		mergeBtn.instance.Position = UDim2.fromOffset(sideBtnW + gap, buttonsY)
		autoBtn.instance.Size = UDim2.fromOffset(sideBtnW, SIZE.buttonH)
		autoBtn.instance.Position = UDim2.fromOffset(sideBtnW + mergeW + gap * 2, buttonsY)
		pickBtn.setText(if compact then "🎲 Pick" else "🎲 Pick for me")
		autoBtn.setText(if compact then "⚡ Auto" else "⚡ Auto-merge")
		local vatH = buttonsY + SIZE.buttonH
		vat.Position = UDim2.fromOffset(0, 0)
		vat.Size = UDim2.fromOffset(vatW, vatH)

		-- Chips and list: under the vat (stacked) or right of it (compact).
		local listX = if compact then vatW + gap * 2 else 0
		local listW = w - listX
		local chipsY = if compact then 0 else vatH + gap * 2
		chips.Position = UDim2.fromOffset(listX, chipsY)
		chips.Size = UDim2.fromOffset(listW, chipsH)
		local listY = chipsY + chipsH + 6
		list.Position = UDim2.fromOffset(listX, listY)
		list.Size = UDim2.new(0, listW, 1, -listY)

		-- Auto card: over the whole body. Compact: tiers on the left, summary and buttons on the right.
		auto.Position = UDim2.fromOffset(0, 0)
		auto.Size = UDim2.fromScale(1, 1)
		local cw = w - 24
		autoTitle.Position = UDim2.fromOffset(12, 6)
		autoTitle.Size = UDim2.fromOffset(cw, 26)
		autoInfo.Visible = not compact
		autoInfo.Position = UDim2.fromOffset(12, 34)
		autoInfo.Size = UDim2.fromOffset(cw, 36)
		local tiersW = if compact then math.floor(cw * 0.6) else cw
		local perRow = if compact or cw >= 420 then 3 else 2
		local tierH = SIZE.autoTierH
		local tw = math.floor((tiersW - (perRow - 1) * gap) / perRow)
		local ty = if compact then 36 else 78
		local n = 0
		for tier = 1, MergePlan.MAX_AUTO_TIER do
			local col, line = n % perRow, n // perRow
			tierButtons[tier].instance.Size = UDim2.fromOffset(tw, tierH)
			tierButtons[tier].instance.Position = UDim2.fromOffset(12 + col * (tw + gap), ty + line * (tierH + gap))
			n += 1
		end
		local tiersBottom = ty + math.ceil(n / perRow) * (tierH + gap)
		local sx = if compact then 12 + tiersW + gap else 12
		local sw = if compact then cw - tiersW - gap else cw
		local sy = if compact then ty else tiersBottom + 2
		local summaryH = if compact then 40 else 54
		autoSummary.Position = UDim2.fromOffset(sx, sy)
		autoSummary.Size = UDim2.fromOffset(sw, summaryH)
		local by = sy + summaryH + 4
		local cancelW = math.floor(sw * 0.3)
		local bh = SIZE.buttonH
		autoCancel.instance.Size = UDim2.fromOffset(cancelW, bh)
		autoCancel.instance.Position = UDim2.fromOffset(sx, by)
		autoConfirm.instance.Size = UDim2.fromOffset(sw - cancelW - gap, bh)
		autoConfirm.instance.Position = UDim2.fromOffset(sx + cancelW + gap, by)
	end

	---------------------------------------------------------------- refresh
	local function slimeOf(id: string): any
		local view = Selection.findSlime(slimes, id)
		return view and view.slime
	end

	local function showResult()
		local now = os.clock()
		if reveal and #selected == 0 and reveal.untilAt > now then
			local r = rarity(reveal.tier)
			orb.BackgroundColor3 = Widgets.color3(r.color)
			orbMark.Text = "✨"
			Widgets.inkOn(orbMark, orb.BackgroundColor3)
			resultTitle.Text = reveal.title
			resultTitle.TextColor3 = Widgets.color3(r.color)
			resultOdds.Text = reveal.sub
			resultKeeps.Text = "Check your plot!"
			return
		end
		local picks = {}
		for _, id in selected do
			local s = slimeOf(id)
			if s then
				table.insert(picks, s)
			end
		end
		local sameTier = #picks > 0
		for _, s in picks do
			sameTier = sameTier and s.tier == picks[1].tier
		end
		if not sameTier then
			orb.BackgroundColor3 = Theme.Ink
			orbMark.Text = "?"
			orbMark.TextColor3 = Theme.Muted
			orbMark.TextStrokeTransparency = 1
			resultTitle.Text = "Result"
			resultTitle.TextColor3 = Theme.Text
			resultOdds.Text = `{count} same-rarity slimes → 1 rarer`
			resultKeeps.Text = "Size follows the average of the slimes"
			return
		end
		local preview = MergePreview.forSlimes(picks, state, nil, count)
		local color = Widgets.color3(preview.color)
		orb.BackgroundColor3 = color
		orbMark.Text = if preview.kind == "recipe" then "★" else "?"
		Widgets.inkOn(orbMark, color)
		resultTitle.Text = preview.title
		resultTitle.TextColor3 = color
		resultOdds.Text = if preview.jumpRarity
			then `⚡ {math.floor(preview.jumpChance * 100 + 0.5)}% chance: {preview.jumpRarity}!`
			else `🎲 A random {preview.rarity} species`
		resultKeeps.Text = `Size ~{string.format("%.2f", preview.size)}`
	end

	local function updateSlots()
		for i, slot in slots do
			local s = if selected[i] then slimeOf(selected[i]) else nil
			slot.swatch.Visible = s ~= nil
			slot.plus.Visible = s == nil
			if s then
				SlimePreview.mountSlime(slot.preview, s, previewBuilders)
				slot.swatch.BackgroundColor3 = if slot.preview.Visible then well else Widgets.color3(s.color)
				slot.name.Text = tostring(s.name)
				slot.name.TextColor3 = Widgets.color3(rarity(s.tier).color)
				slot.stroke.Color = Widgets.color3(rarity(s.tier).color)
			else
				SlimePreview.unmountSlime(slot.preview)
				slot.name.Text = ""
				slot.stroke.Color = Theme.Ink
			end
		end
	end

	local function updateChips(counts: { [number]: number }, total: number)
		local x, y = 0, 0
		local maxW = chips.Size.X.Offset
		local order = { 0 }
		for tier = 1, Config.MAX_TIER do
			if (counts[tier] or 0) > 0 or filter == tier then
				table.insert(order, tier)
			end
		end
		for _, btn in chipButtons do
			btn.instance.Visible = false
		end
		for _, tier in order do
			local btn = chipFor(tier)
			local label = if tier == 0 then `All {total}` else `{rarityName(tier)} {counts[tier] or 0}`
			local width = math.max(56, math.ceil((Layout.textSize(label, SIZE.textSmall + 1, true))) + 20)
			if x > 0 and x + width > maxW then
				x, y = 0, y + SIZE.chipH + SIZE.chipGap
			end
			btn.instance.Visible = true
			btn.instance.Text = label
			btn.instance.Size = UDim2.fromOffset(width, SIZE.chipH)
			btn.instance.Position = UDim2.fromOffset(x, y)
			local active = (tier == 0 and filter == nil) or tier == filter
			btn.setColor(if active then Theme.Good else Theme.Ink)
			if not active then
				btn.instance.TextColor3 = if tier == 0 then Theme.Text else Widgets.color3(rarity(tier).color)
				btn.instance.TextStrokeTransparency = 1
			end
			x += width + SIZE.chipGap
		end
		local h = y + SIZE.chipH
		if h ~= chipsH then
			chipsH = h
			place()
		end
	end

	local function updateAuto(candidates: { any })
		if not auto.Visible then
			return
		end
		local possible = MergePlan.countByTier(MergePlan.plan(candidates, { tiers = allAutoTiers }))
		for tier, btn in tierButtons do
			local on = autoTiers[tier] == true
			local n = possible[tier] or 0
			btn.instance.Text = if compact
				then `{if on then "✅" else ""}{rarityName(tier)} {n}`
				else `{if on then "✅ " else ""}{rarityName(tier)} ({n})`
			btn.setColor(if on then Widgets.color3(rarity(tier).color) else Theme.Ink)
			if not on then
				btn.instance.TextColor3 = Theme.Muted
				btn.instance.TextStrokeTransparency = 1
			end
		end
		local groups = MergePlan.plan(candidates, { tiers = autoTiers })
		local byTier = MergePlan.countByTier(groups)
		local lines = {}
		for tier = 1, MergePlan.MAX_AUTO_TIER do
			local n = byTier[tier]
			if n then
				table.insert(lines, `{n}x {rarityName(tier)} → {rarityName(tier + 1)}`)
			end
		end
		if #groups == 0 then
			autoSummary.Text = "Nothing to merge in the picked rarities."
			autoSummary.TextColor3 = Theme.Muted
			autoConfirm.setText("Nothing to merge")
		else
			autoSummary.Text = `Uses {#groups * 3} slimes: {table.concat(lines, ", ")}`
			autoSummary.TextColor3 = Theme.Text
			autoConfirm.setText(`⚡ Hold: merge {#groups} group{if #groups == 1 then "" else "s"}`)
		end
		autoConfirm.setEnabled(#groups > 0)
	end

	function refresh()
		local now = os.clock()
		selected = Selection.prune(selected, slimes)
		local candidates = MergePlan.fromViews(slimes, state and state.favoriteId)

		-- Chips, then the list grouped by rarity (lowest first, cheapest first inside a rarity).
		local counts: { [number]: number } = {}
		for _, view in slimes do
			counts[view.slime.tier] = (counts[view.slime.tier] or 0) + 1
		end
		if filter and (counts[filter] or 0) == 0 then
			filter = nil
		end
		updateChips(counts, #slimes)
		local sorted = table.clone(slimes)
		table.sort(sorted, function(x: any, y: any)
			if x.slime.tier ~= y.slime.tier then
				return x.slime.tier < y.slime.tier
			end
			if (x.income or 0) ~= (y.income or 0) then
				return (x.income or 0) < (y.income or 0)
			end
			return x.slime.id < y.slime.id
		end)
		local items = {}
		local lastTier = nil
		for _, view in sorted do
			local tier = view.slime.tier
			if filter == nil or filter == tier then
				if tier ~= lastTier then
					lastTier = tier
					local pool = #MergePlan.pool(candidates, tier)
					table.insert(items, {
						kind = "header",
						key = `~header{tier}`,
						tier = tier,
						count = counts[tier],
						groups = pool // count,
					})
				end
				table.insert(items, { kind = "slime", key = view.slime.id, view = view })
			end
		end
		rows.sync(items)
		refreshPreviews()

		updateSlots()
		showResult()
		local ok, why = Selection.vatLoad(slimes, selected, count, rarityName)
		mergeBtn.setEnabled(ok)
		if ok then
			reason.Text = "Hold MERGE to brew!"
			reason.TextColor3 = Theme.Good
		elseif reveal and #selected == 0 and reveal.untilAt > now then
			reason.Text = "Merged! Pick more slimes to go again"
			reason.TextColor3 = Theme.Gold
		elseif #slimes < count then
			reason.Text = `You need {count} slimes of one rarity`
			reason.TextColor3 = Theme.Muted
		else
			reason.Text = why or ""
			reason.TextColor3 = if why
					and (string.find(why, "stolen", 1, true) or string.find(why, "kept", 1, true))
				then Theme.Warn
				else Theme.Muted
		end
		local suggestion = MergePlan.suggest(candidates, filter or Merge.selectionTier(slimes, selected), count)
		pickBtn.setEnabled(suggestion ~= nil)
		autoBtn.setEnabled(#MergePlan.plan(candidates, { tiers = allAutoTiers, limit = 1 }) > 0)
		updateAuto(candidates)
	end

	---------------------------------------------------------------- after a merge
	local function watchPending(newState: any)
		local fresh = {}
		for _, view in newState.slimes do
			if not knownIds[view.slime.id] then
				table.insert(fresh, view.slime)
			end
		end
		local p = pending
		if p then
			local gone = true
			for _, id in p.ids do
				if Selection.findSlime(newState.slimes, id) then
					gone = false
				end
			end
			if #fresh > 0 and gone then
				local best = fresh[1]
				for _, s in fresh do
					if s.tier > best.tier then
						best = s
					end
				end
				local sub = if #fresh > 1 then `+{#fresh} new slimes` else "Fresh from the vat"
				reveal = {
					title = `✨ {Genome.displayName(best)}`,
					sub = sub,
					tier = best.tier,
					untilAt = os.clock() + SIZE.reveal,
				}
				for _, s in fresh do
					newIds[s.id] = os.clock() + SIZE.reveal * 2
				end
				pending = nil
				Merge.pop(orbScale)
			elseif os.clock() - p.at > SIZE.pendingTimeout then
				pending = nil
			end
		end
		knownIds = {}
		for _, view in newState.slimes do
			knownIds[view.slime.id] = true
		end
	end

	local self = { frame = panel.frame, close = panel.close }

	function self.setOpen(isOpen: boolean)
		open = isOpen
		refreshPreviews()
	end

	-- Called by init.client with the panel box (Layout.panelFor) and the screen it was placed on.
	function self.layout(r: any, screen: any?)
		local b = Layout.panelBody(r)
		bodyW, bodyH = math.floor(b.w), math.floor(b.h)
		roomH = if screen then math.floor(Layout.panelBody(Layout.panelFor(screen, "Merge")).h) else bodyH
		place()
	end

	function self.update(newState: any)
		local want = if tripleOn() then 3 else 2
		if want ~= count then
			count = want
			while #selected > count do
				table.remove(selected)
			end
			place()
		end
		watchPending(newState)
		state = newState
		slimes = newState.slimes or {}
		refresh()
	end

	place()
	return self
end

-- The rarity of the current picks (the first one's), or nil when nothing is picked.
function Merge.selectionTier(slimes: { any }, selected: { string }): number?
	local first = Selection.findSlime(slimes, selected[1])
	return if first then first.slime.tier else nil
end

-- The slots fly into the result card: their swatches shrink away and the card flashes.
function Merge.celebrate(slots: { any }, orbScale: UIScale, flash: Frame)
	local info = TweenInfo.new(SIZE.celebrate, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, slot in slots do
		if slot.swatch.Visible then
			TweenService:Create(slot.swatch, info, { Size = UDim2.fromScale(0, 0) }):Play()
		end
	end
	flash.BackgroundTransparency = 0.15
	TweenService:Create(flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
	Merge.pop(orbScale)
end

-- A springy pop of the result orb.
function Merge.pop(orbScale: UIScale)
	orbScale.Scale = 1.35
	TweenService:Create(orbScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

return Merge
