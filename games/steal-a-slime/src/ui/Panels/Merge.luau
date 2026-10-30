--!strict
--[[
	Merge vat menu (CONTRACT.md §21). Opens from the vat's "Manage vat" prompt.

	Slimes only get into the vat through Move mode (SlimeMove places them on the vat); this card manages the load:
	  * chips: the vat's rarity, how many are in (or Brewing / Ready), the brew time;
	  * three slots with the slimes' 3D previews (SlimePreview); each has an X that sends VatRemove (the slime is
	    back on its own pad), a padlock instead while brewing, and an empty slot says how to fill it;
	  * the result card (Shared.MergePreview): "Random slime" with the rarity it will be and the jump chance, or a
	    found recipe's hybrid by name; after Collect it reveals the new slime and the pad it went to;
	  * a goo bar with the time left while brewing, and under it the "Finish now · R$N"
    quick-buy (ExclusiveShopView.brewQuickBuy: priced by the time left) or "Use credit" with a saved brew credit;
	  * one main button: a well saying what is missing, Start merge (VatStart), Hold to cancel (VatCancel) or
	    Collect (VatCollect). A load the player's rank can't merge yet (Shared.MergeGate) may wait in the vat: a
	    Warn chip and a padlock on the result orb say so, and the well reads "Rebirth <n> to unlock".
	The main button is pinned to the bottom of the card; everything above it scrolls when the screen clamps the
	card (a landscape phone while brewing).
	`describe` is the pure part (tests/ui/MergeMenu.spec.luau); `new` builds and fills the card.
]]

local UI = script.Parent.Parent
local ExclusiveShopView = require(UI.ExclusiveShopView)
local Format = require(UI.Format)
local Layout = require(UI.Layout)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MergeGate = require(Shared:WaitForChild("MergeGate") :: any)
local MergePreview = require(Shared:WaitForChild("MergePreview") :: any)

local TweenService = game:GetService("TweenService")

local Theme = Widgets.Theme
local KIT = Widgets.KIT
local create = Widgets.create

local SIZE = table.freeze({
	chipH = 26,
	gap = 10,
	slot = 76,
	slotGap = 10,
	slotTop = 6, -- px from the top of the load row to the slots
	nameH = 18,
	rarityH = 16,
	x = Layout.MIN_TOUCH_DESIGN, -- a slot's X: the tap area (invisible) around its badge
	badge = 26, -- the X and padlock badge drawn on a slot's top-right edge
	badgeText = 14, -- the X on its badge
	lockText = 12, -- the padlock emoji on its badge
	badgeInset = 10, -- px from the slot's top-right corner box to the badge's centre
	arrowW = 30,
	orb = 72,
	resultMin = 170,
	reasonH = 40,
	timerH = 44,
	barH = 14,
	buttonW = 260,
	buttonH = Layout.MIN_TOUCH_DESIGN,
	buttonFoot = 4, -- space under the main button
	revealSeconds = 5, -- how long the result card shows a collected slime
	pendingTimeout = 6, -- seconds to wait for State to bring the collected slime
	textTitle = 17,
	text = 15,
	textSmall = Layout.MIN_TEXT,
	textBig = 30,
})

local SLOTS = 3

export type Slot = {
	id: string?, -- nil = empty
	slime: any?, -- the genome, for the preview
	name: string,
	rarity: string?,
	color: { number }?, -- rarity colour
	canRemove: boolean, -- the X is live
	locked: boolean, -- brewing: a padlock instead of the X
}

export type View = {
	tier: number?,
	rarityName: string?,
	countText: string, -- "2/3 in", "Brewing", "Ready"
	brewText: string?, -- "Brew time 30s"
	slots: { Slot },
	preview: any?, -- MergePreview.forSlimes, nil while empty
	reason: string,
	gate: { chip: string, line: string }?, -- the rank can't merge this load yet: "Rebirth 3", "Epic merges open at Rebirth 3"
	main: { kind: "well" | "start" | "cancel" | "collect", text: string },
	timeLeft: number?, -- brewing: seconds left
	progress: number?, -- brewing: 0..1
}

local Merge = {}

-- A brew length for a chip or button: "30s", "1m", "2m 30s", "1h 5m".
function Merge.brewText(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	if s < 60 then
		return `{s}s`
	elseif s < 3600 then
		local m, rest = s // 60, s % 60
		return if rest == 0 then `{m}m` else `{m}m {rest}s`
	end
	local h, m = s // 3600, (s % 3600) // 60
	return if m == 0 then `{h}h` else `{h}h {m}m`
end

-- "a Rare", "an Epic".
function Merge.withArticle(word: string): string
	return if string.match(string.lower(word), "^[aeiou]") then `an {word}` else `a {word}`
end

-- "20% chance of an Epic".
function Merge.jumpText(chance: number, rarity: string): string
	return `{math.floor(chance * 100 + 0.5)}% chance of {Merge.withArticle(rarity)}`
end

local function findSlime(state: any, id: string): any?
	for _, view in (if type(state.slimes) == "table" then state.slimes else {}) do
		if type(view.slime) == "table" and view.slime.id == id then
			return view.slime
		end
	end
	return nil
end

-- Everything the card shows for `state` at server time `now`. `rarityOf(tier)` = Config.RARITIES[tier],
-- `nameOf(slime)` = the name under a slot (the slime's own name; the rarity has its own line).
function Merge.describe(state: any, now: number, rarityOf: (number) -> any, nameOf: (any) -> string): View
	local vat = if type(state) == "table" and type(state.vat) == "table" then state.vat else { ids = {} }
	local rebirths = if type(state) == "table" and type(state.rebirths) == "number" then state.rebirths else 0
	local slimes = {}
	for _, id in (if type(vat.ids) == "table" then vat.ids else {}) do
		local slime = findSlime(state, id)
		if slime then
			table.insert(slimes, slime)
		end
	end
	local tier = if slimes[1] then slimes[1].tier else nil
	local rarity = if tier then rarityOf(tier) else nil
	local endsAt = if type(vat.endsAt) == "number" then vat.endsAt else nil
	local brewing = endsAt ~= nil
	local ready = endsAt ~= nil and now >= endsAt

	local slots: { Slot } = {}
	for i = 1, SLOTS do
		local slime = slimes[i]
		if slime then
			slots[i] = {
				id = slime.id,
				slime = slime,
				name = nameOf(slime),
				rarity = rarity and rarity.name,
				color = rarity and rarity.color,
				canRemove = not brewing,
				locked = brewing,
			}
		else
			slots[i] = {
				id = nil,
				slime = nil,
				name = if rarity then `Move {Merge.withArticle(rarity.name)} here` else "Move a slime here",
				rarity = nil,
				color = nil,
				canRemove = false,
				locked = false,
			}
		end
	end

	local seconds = if type(vat.seconds) == "number" then vat.seconds else nil
	local missing = SLOTS - #slimes
	local view: View = {
		tier = tier,
		rarityName = rarity and rarity.name,
		countText = if ready then "Ready" elseif brewing then "Brewing" else `{#slimes}/{SLOTS} in`,
		brewText = if seconds and not brewing then `Brew time {Merge.brewText(seconds)}` else nil,
		slots = slots,
		preview = if #slimes > 0 then MergePreview.forSlimes(slimes, state) else nil,
		reason = "",
		gate = nil,
		main = { kind = "well", text = "" },
		timeLeft = nil,
		progress = nil,
	}
	if ready then
		view.reason = "Done. Collect puts it on a pad."
		view.main = { kind = "collect", text = "Collect" }
	elseif brewing then
		local startedAt = if type(vat.startedAt) == "number" then vat.startedAt else endsAt
		view.timeLeft = math.max(0, (endsAt :: number) - now)
		view.progress = Format.progress(startedAt :: number, endsAt :: number, now)
		view.reason = "Safe while it brews: no stealing, and no income until you collect."
		view.main = { kind = "cancel", text = "Hold to cancel" }
	elseif tier and not MergeGate.allows(tier, rebirths) then
		local need = MergeGate.rebirthsFor(tier)
		local more = if need then need - rebirths else 0
		view.gate = { chip = if need then `Rebirth {need}` else "Locked", line = MergeGate.opensText(tier) }
		view.main = { kind = "well", text = MergeGate.lockText(tier) }
		view.reason = if missing > 0
			then `You can fill the vat now and start it once you reach Rebirth {need or "?"}.`
			else `Rebirth {more} more time{if more == 1 then "" else "s"} to merge {(rarity :: any).name}s. Until you start, these still earn on their pads.`
	elseif #slimes == 0 then
		view.reason = "Use Move on one of your pad slimes and place it in the vat."
		view.main = { kind = "well", text = "Add 3 slimes of one rarity" }
	elseif missing > 0 then
		view.reason = "Until you start, these still earn and can be stolen from their pads."
		view.main = { kind = "well", text = `Add {missing} more {(rarity :: any).name}` }
	else
		view.reason = "You can take slimes out until you start."
		view.main = {
			kind = "start",
			text = if seconds then `Start merge · {Merge.brewText(seconds)}` else "Start merge",
		}
	end
	return view
end

local function rgb(c: { number }?): Color3
	return if c then Color3.fromRGB(c[1], c[2], c[3]) else Theme.Muted
end

function Merge.new(parent: Instance, ctx: any)
	local Config = ctx.Config
	local Genome = ctx.Genome
	local panel = Widgets.panel(parent, "MergePanel", "Merge vat", "🧪")
	local body = panel.body
	-- Everything above the main button; place() sets its canvas.
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 1, -(SIZE.buttonH + SIZE.buttonFoot)),
		Parent = body,
	})
	local builders: SlimePreview.Builders = { species = ctx.buildSpecies, slime = ctx.buildSlime }
	local wellColor = Theme.Row:Lerp(Theme.Ink, SlimePreview.WELL_TINT)

	local state: any = nil
	local open = false
	local bodyW = Layout.MENU_WIDTH - Layout.PANEL_CHROME.pad * 2
	local reveal: { title: string, sub: string, slime: any, tier: number, untilAt: number }? = nil
	local pending: { at: number, known: { [string]: boolean } }? = nil
	local view: View? = nil

	local function rarityOf(tier: number): any
		return Config.RARITIES[math.clamp(tier, 1, Config.MAX_TIER)]
	end
	local function slimeName(slime: any): string
		return if type(slime.name) == "string" then slime.name else Genome.displayName(slime)
	end

	---------------------------------------------------------------- chips
	local chipRow = create("Frame", { Name = "Chips", BackgroundTransparency = 1, Parent = content }, {
		Widgets.list(Enum.FillDirection.Horizontal, 8),
	})
	local rarityChip = Widgets.chip({ Name = "RarityChip", Parent = chipRow })
	local countChip = Widgets.chip({ Name = "CountChip", Parent = chipRow })
	local timeChip = Widgets.chip({ Name = "TimeChip", Parent = chipRow })
	local gateChip = Widgets.chip({ Name = "GateChip", TextColor3 = Theme.Warn, Visible = false, Parent = chipRow })

	---------------------------------------------------------------- slots
	local load = create("Frame", { Name = "Load", BackgroundTransparency = 1, Parent = content })
	type SlotUi = {
		well: Frame,
		ring: UIStroke,
		preview: ViewportFrame,
		empty: TextLabel,
		name: TextLabel,
		rarity: TextLabel,
		x: TextButton,
		lock: TextLabel,
	}
	local slotUis: { SlotUi } = {}
	for i = 1, SLOTS do
		local well = create("Frame", {
			Name = `Slot{i}`,
			BackgroundColor3 = wellColor,
			Size = UDim2.fromOffset(SIZE.slot, SIZE.slot),
			Parent = load,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame
		local ring = Widgets.stroke(Theme.Ink, KIT.stroke + 1)
		ring.Parent = well
		local preview = create("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = well,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: ViewportFrame
		local empty = Widgets.label({
			Name = "Empty",
			Text = "",
			TextSize = SIZE.textSmall,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -12, 1, -12),
			Position = UDim2.fromOffset(6, 6),
			Parent = well,
		})
		local name = Widgets.label({
			Name = `SlotName{i}`,
			Font = Theme.Font,
			TextSize = SIZE.text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = load,
		})
		local rarity = Widgets.label({
			Name = `SlotRarity{i}`,
			Font = Theme.Font,
			TextSize = SIZE.textSmall,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = load,
		})
		-- The X: a thumb-sized invisible button with a small red badge in its middle.
		local x = create("TextButton", {
			Name = `Remove{i}`,
			Text = "",
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(SIZE.x, SIZE.x),
			ZIndex = 3,
			Parent = load,
		}) :: TextButton
		local badge = Widgets.label({
			Name = "Badge",
			Text = "X",
			Font = Theme.Font,
			TextSize = SIZE.badgeText,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Bad,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(SIZE.badge, SIZE.badge),
			Parent = x,
		})
		Widgets.pill().Parent = badge
		Widgets.stroke(Theme.Ink, KIT.rowStroke).Parent = badge
		Widgets.inkOn(badge, Theme.Bad)
		x.Activated:Connect(function()
			local slot = view and view.slots[i]
			if slot and slot.id and slot.canRemove then
				ctx.send("VatRemove", slot.id)
			end
		end)
		local lock = Widgets.status({
			Name = `Lock{i}`,
			Text = "🔒",
			TextSize = SIZE.lockText,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(SIZE.badge, SIZE.badge),
			ZIndex = 3,
			Visible = false,
			Parent = load,
		})
		slotUis[i] = {
			well = well,
			ring = ring,
			preview = preview,
			empty = empty,
			name = name,
			rarity = rarity,
			x = x,
			lock = lock,
		}
	end

	local arrow = Widgets.label({
		Name = "Arrow",
		Text = "→",
		Font = Theme.Font,
		TextSize = SIZE.textBig,
		TextColor3 = Theme.Good,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = load,
	})

	---------------------------------------------------------------- result
	local result = Widgets.rowFrame({ Name = "Result", ClipsDescendants = true, Parent = load })
	local orb = create("Frame", {
		Name = "Orb",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = wellColor,
		Size = UDim2.fromOffset(SIZE.orb, SIZE.orb),
		Parent = result,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame
	local orbRing = Widgets.stroke(Theme.Gold, KIT.stroke + 1)
	orbRing.Parent = orb
	local orbScale = create("UIScale", { Scale = 1, Parent = orb }) :: UIScale
	local orbPreview = create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = orb,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: ViewportFrame
	local orbMark = Widgets.label({
		Name = "Mark",
		Text = "?",
		Font = Theme.Font,
		TextSize = SIZE.textBig,
		TextColor3 = Theme.Gold,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = orb,
	})
	local resultTitle = Widgets.label({ Name = "Title", Font = Theme.Font, TextSize = SIZE.textTitle, Parent = result })
	local resultChip = Widgets.chip({ Name = "RarityPill", Parent = result })
	local resultOdds = Widgets.label({
		Name = "Odds",
		TextSize = SIZE.textSmall,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Parent = result,
	})

	---------------------------------------------------------------- reason, timer, button
	local reason = Widgets.label({
		Name = "Reason",
		Text = "",
		TextSize = SIZE.text,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
	local timer = Widgets.rowFrame({ Name = "Timer", Visible = false, Parent = content })
	Widgets.label({
		Name = "Label",
		Text = "Brewing",
		Font = Theme.Font,
		TextSize = SIZE.text,
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(0.5, -12, 0, 18),
		Parent = timer,
	})
	local timeLeft = Widgets.label({
		Name = "TimeLeft",
		Font = Theme.Font,
		TextSize = SIZE.text,
		TextColor3 = Theme.Good,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(0.5, -12, 0, 18),
		Parent = timer,
	})
	local _, setBar = Widgets.bar(timer, Theme.Good, UDim2.new(1, -24, 0, SIZE.barH), UDim2.fromOffset(12, 24))

	-- The Robux skip under the timer, built the first time a brew can be finished (never with the shop off).
	local quick: Widgets.Button? = nil
	local quickBuy: ExclusiveShopView.QuickBuy? = nil
	local function quickButton(): Widgets.Button
		if quick then
			return quick
		end
		local made = Widgets.button(
			{ Name = "FinishNow", Text = "", TextSize = SIZE.textTitle, Visible = false, Parent = content },
			Theme.Accent,
			function()
				local q = quickBuy
				if q == nil then
					return
				elseif q.mode == "credit" then
					ctx.send("UseCredit", "brew")
				elseif q.mode == "buy" and q.purchase and ctx.purchase then
					ctx.purchase.prompt(q.purchase)
				end
			end
		)
		made.instance.Parent = content
		quick = made
		return made
	end

	local well = Widgets.status({ Name = "Missing", Text = "", TextSize = SIZE.textTitle, Parent = body })
	local startBtn = Widgets.button(
		{ Name = "StartButton", Text = "Start merge", TextSize = SIZE.textTitle, Parent = body },
		Theme.Accent,
		function()
			ctx.send("VatStart")
		end
	)
	local collectBtn = Widgets.button(
		{ Name = "CollectButton", Text = "Collect", TextSize = SIZE.textTitle, Parent = body },
		Theme.Gold,
		function()
			local known = {}
			for _, v in (if state and type(state.slimes) == "table" then state.slimes else {}) do
				known[v.slime.id] = true
			end
			pending = { at = os.clock(), known = known }
			ctx.send("VatCollect")
		end
	)
	local cancelBtn = Widgets.holdButton(
		{ Name = "CancelButton", Text = "Hold to cancel", TextSize = SIZE.textTitle, Parent = body },
		Theme.Bad,
		function()
			ctx.send("VatCancel")
		end,
		Config.HOLD_CONFIRM_SECONDS
	)

	---------------------------------------------------------------- layout
	local function place()
		local y = 0
		chipRow.Size = UDim2.fromOffset(bodyW, SIZE.chipH)
		y += SIZE.chipH + SIZE.gap + 8

		local slotsW = SLOTS * SIZE.slot + (SLOTS - 1) * SIZE.slotGap
		local resultW = math.max(SIZE.resultMin, bodyW - slotsW - SIZE.arrowW - SIZE.gap * 2)
		local stacked = slotsW + SIZE.arrowW + SIZE.resultMin + SIZE.gap * 2 > bodyW
		local slotsX = if stacked then math.floor((bodyW - slotsW) / 2) else 0
		local loadH = SIZE.slot + SIZE.nameH + SIZE.rarityH + 6
		for i, ui in slotUis do
			local x = slotsX + (i - 1) * (SIZE.slot + SIZE.slotGap)
			ui.well.Position = UDim2.fromOffset(x, SIZE.slotTop)
			ui.name.Position = UDim2.fromOffset(x - 8, SIZE.slot + 10)
			ui.name.Size = UDim2.fromOffset(SIZE.slot + 16, SIZE.nameH)
			ui.rarity.Position = UDim2.fromOffset(x - 8, SIZE.slot + 10 + SIZE.nameH)
			ui.rarity.Size = UDim2.fromOffset(SIZE.slot + 16, SIZE.rarityH)
			-- Both badges centred on the same spot, near the slot's top-right edge.
			local corner = UDim2.fromOffset(x + SIZE.slot - SIZE.badgeInset, SIZE.slotTop + SIZE.badgeInset)
			ui.x.Position = corner
			ui.lock.Position = corner
		end
		local resultH = SIZE.orb + 30
		if stacked then
			arrow.Visible = false
			result.Position = UDim2.fromOffset(0, loadH + SIZE.gap)
			result.Size = UDim2.fromOffset(bodyW, resultH)
			loadH += SIZE.gap + resultH
		else
			arrow.Visible = true
			arrow.Position = UDim2.fromOffset(slotsW + SIZE.gap, SIZE.slotTop)
			arrow.Size = UDim2.fromOffset(SIZE.arrowW, SIZE.slot)
			result.Position = UDim2.fromOffset(slotsW + SIZE.arrowW + SIZE.gap * 2, 0)
			result.Size = UDim2.fromOffset(resultW, math.max(resultH, SIZE.slot + 12))
		end
		local textX = SIZE.orb + 22
		local textW = result.Size.X.Offset - textX - 10
		orb.Position = UDim2.new(0, 10, 0.5, 0)
		resultTitle.Position = UDim2.fromOffset(textX, 10)
		resultTitle.Size = UDim2.fromOffset(textW, 22)
		resultChip.Position = UDim2.fromOffset(textX, 34)
		resultOdds.Position = UDim2.fromOffset(textX, 62)
		resultOdds.Size = UDim2.fromOffset(textW, 34)
		resultOdds.TextYAlignment = Enum.TextYAlignment.Top
		load.Position = UDim2.fromOffset(0, y)
		load.Size = UDim2.fromOffset(bodyW, loadH)
		y += loadH + SIZE.gap

		reason.Position = UDim2.fromOffset(0, y)
		reason.Size = UDim2.fromOffset(bodyW, SIZE.reasonH)
		y += SIZE.reasonH + SIZE.gap
		if timer.Visible then
			timer.Position = UDim2.fromOffset(0, y)
			timer.Size = UDim2.fromOffset(bodyW, SIZE.timerH)
			y += SIZE.timerH + SIZE.gap
		end
		if quick and quick.instance.Visible then
			quick.instance.Position = UDim2.fromOffset(math.floor((bodyW - SIZE.buttonW) / 2), y)
			quick.instance.Size = UDim2.fromOffset(SIZE.buttonW, SIZE.buttonH)
			y += SIZE.buttonH + SIZE.gap
		end
		content.CanvasSize = UDim2.fromOffset(0, y)
		local bx = math.floor((bodyW - SIZE.buttonW) / 2)
		for _, inst in { well, startBtn.instance, collectBtn.instance, cancelBtn.instance } do
			inst.Position = UDim2.new(0, bx, 1, -(SIZE.buttonH + SIZE.buttonFoot))
			inst.Size = UDim2.fromOffset(SIZE.buttonW, SIZE.buttonH)
		end
	end

	local function showPreview(viewport: ViewportFrame, slime: any?)
		if slime and open then
			SlimePreview.mountSlime(viewport, slime, builders)
		else
			SlimePreview.unmountSlime(viewport)
		end
	end

	---------------------------------------------------------------- fill
	local function refresh()
		local now = ctx.serverNow()
		local v = Merge.describe(state, now, rarityOf, slimeName)
		view = v
		rarityChip.Visible = v.rarityName ~= nil
		rarityChip.Text = if v.rarityName then `{v.rarityName} vat` else ""
		rarityChip.TextColor3 = if v.tier then rgb(rarityOf(v.tier).color) else Theme.Text
		countChip.Text = v.countText
		countChip.TextColor3 = if v.countText == "Ready" then Theme.Gold else Theme.Text
		timeChip.Visible = v.brewText ~= nil
		timeChip.Text = v.brewText or ""
		gateChip.Visible = v.gate ~= nil
		gateChip.Text = if v.gate then `🔒 {v.gate.chip}` else ""

		for i, ui in slotUis do
			local slot = v.slots[i]
			local filled = slot.id ~= nil
			ui.ring.Color = if filled then rgb(slot.color) else Theme.Ink
			ui.well.BackgroundColor3 = if filled then wellColor else Theme.Ink
			ui.empty.Visible = not filled
			ui.empty.Text = if filled then "" else slot.name
			showPreview(ui.preview, slot.slime)
			ui.name.Text = if filled then slot.name else ""
			ui.rarity.Text = slot.rarity or ""
			ui.rarity.TextColor3 = rgb(slot.color)
			ui.x.Visible = slot.canRemove
			ui.lock.Visible = slot.locked
		end

		local r = reveal
		if r and os.clock() < r.untilAt then
			resultTitle.Text = r.title
			resultChip.Visible = true
			resultChip.Text = Genome.rarity(r.tier).name
			resultChip.TextColor3 = rgb(rarityOf(r.tier).color)
			resultOdds.Text = r.sub
			resultOdds.TextColor3 = Theme.Muted
			orbMark.Visible = false
			orbRing.Color = rgb(rarityOf(r.tier).color)
			showPreview(orbPreview, r.slime)
		else
			reveal = nil
			local p = v.preview
			orbPreview.Visible = false
			SlimePreview.unmountSlime(orbPreview)
			orbRing.Color = if v.gate then Theme.Warn else Theme.Gold
			resultOdds.TextColor3 = if v.gate then Theme.Warn else Theme.Muted
			if p then
				resultTitle.Text = p.title
				resultChip.Visible = true
				resultChip.Text = p.rarity
				resultChip.TextColor3 = rgb(p.color)
				resultOdds.Text = if v.gate
					then v.gate.line
					elseif p.kind == "recipe" then "Always this slime"
					elseif p.jumpRarity then Merge.jumpText(p.jumpChance, p.jumpRarity)
					elseif
						p.jumpOpensAt
					then `No jump: {Genome.rarity(p.tier + 1).name} opens at Rebirth {p.jumpOpensAt}`
					else "No jump past this rarity"
				orbMark.Visible = v.gate ~= nil or p.kind ~= "recipe"
				orbMark.Text = if v.gate then "🔒" else "?"
			else
				resultTitle.Text = "Three of one rarity"
				resultChip.Visible = false
				resultOdds.Text = "make one rarer slime"
				orbMark.Visible = true
			end
		end

		reason.Text = v.reason
		local wasTimer = timer.Visible
		timer.Visible = v.timeLeft ~= nil
		if v.timeLeft then
			timeLeft.Text = `{Format.formatDuration(v.timeLeft)} left`
			setBar(v.progress or 0)
		end
		local q =
			ExclusiveShopView.brewQuickBuy(state, now, Config, ctx.actions ~= nil and ctx.actions.UseCredit ~= nil)
		quickBuy = q
		local wasQuick = quick ~= nil and quick.instance.Visible
		if q then
			local b = quickButton()
			b.instance.Visible = true
			b.setText(q.text)
			b.setEnabled(q.mode == "credit" or (q.mode == "buy" and ctx.purchase ~= nil))
		elseif quick then
			quick.instance.Visible = false
		end
		well.Visible = v.main.kind == "well"
		well.Text = v.main.text
		startBtn.instance.Visible = v.main.kind == "start"
		startBtn.setText(v.main.text)
		collectBtn.instance.Visible = v.main.kind == "collect"
		cancelBtn.instance.Visible = v.main.kind == "cancel"
		if wasTimer ~= timer.Visible or wasQuick ~= (q ~= nil) then
			place()
		end
	end

	-- After Collect: the new slime (an id State didn't have before) shows in the result card.
	local function watchPending(newState: any)
		local p = pending
		if not p then
			return
		end
		for _, v in (if type(newState.slimes) == "table" then newState.slimes else {}) do
			if not p.known[v.slime.id] then
				local slime = v.slime
				reveal = {
					title = slimeName(slime),
					sub = if type(slime.pad) == "number" then `On pad {slime.pad}` else "Fresh from the vat",
					slime = slime,
					tier = slime.tier,
					untilAt = os.clock() + SIZE.revealSeconds,
				}
				pending = nil
				orbScale.Scale = 1.35
				TweenService
					:Create(
						orbScale,
						TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Scale = 1 }
					)
					:Play()
				return
			end
		end
		if os.clock() - p.at > SIZE.pendingTimeout then
			pending = nil
		end
	end

	local self = { frame = panel.frame, close = panel.close }

	function self.setOpen(isOpen: boolean)
		open = isOpen
		refresh()
	end

	-- Called by init.client with the panel box (Layout.panelFor) and the screen it was placed on.
	function self.layout(r: any, _screen: any?)
		bodyW = math.floor(Layout.panelBody(r).w)
		place()
	end

	function self.update(newState: any)
		watchPending(newState)
		state = newState
		refresh()
		place()
	end

	-- The client's 10 Hz loop: the countdown, the switch to Ready and the end of a reveal.
	function self.tick(_now: number)
		local brewing = type(state) == "table" and type(state.vat) == "table" and type(state.vat.endsAt) == "number"
		if open and (brewing or reveal ~= nil) then
			refresh()
		end
	end

	place()
	return self
end

return Merge
