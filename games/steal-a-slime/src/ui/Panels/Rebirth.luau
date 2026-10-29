--!strict
--[[
	Rebirth panel: only the NEXT rebirth, its number in the title.

	Top to bottom:
	  * Hero: the income multiplier now and after the rebirth ("x3.5 → x4"), in an Ink well.
	  * Perk chips: the lock time it adds, and the rank's income bonus when this rebirth earns a rank.
	  * Rank row: a Gold-ringed "New rank: Goo Tycoon" when this rebirth reaches one (what that rank does),
	    else a quiet "Next rank at Rebirth 30". Hidden past the last rank.
	  * "Bring these" checklist with an "x of y ready" count: a cash row (cost, a Gold bar, what you have) and
	    one row per slime (Config.REBIRTH_SLIMES; greyed preview and a "Missing" chip until you have it).
	    A met row ends in a mint tick.
	  * "You keep" / "Resets" wells side by side.
	  * The hold-to-confirm Rebirth button (state.canRebirth), else a sunken well saying what is missing.
	At max rebirths only the crown card shows: your rank, totals and "All rebirths done".
	Progress.nextRebirth has the numbers; `rank` and `plan` are the pure parts.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Layout = require(UI.Layout)
local Progress = require(UI.Progress)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FountainTiers = require(Shared:WaitForChild("FountainTiers") :: any)
local MergeGate = require(Shared:WaitForChild("MergeGate") :: any)
local Perks = require(Shared:WaitForChild("Perks") :: any)

local Theme = Widgets.Theme
local create = Widgets.create

local Rebirth = {}

Rebirth.SLIME_IMAGE = 48

-- Vertical rhythm of the body (design px).
Rebirth.ROWS = table.freeze({
	gap = 10, -- between sections
	hero = 74,
	perks = 28,
	rank = 70,
	head = 24, -- "Bring these" and the count
	row = 62, -- one checklist row
	rowGap = 6,
	keep = 64,
})

-- Inside the hero, the rows and the wells (design px).
Rebirth.CARD = table.freeze({
	pad = 10,
	arrowW = 40,
	heroLabelY = 10,
	heroLabelH = 18,
	heroValueY = 30,
	heroValueH = 38,
	heroValueSize = 32,
	arrowSize = 34,
	labelSize = Layout.MIN_TEXT,
	textGap = 10, -- picture to text
	nameY = 8,
	nameSize = 19,
	nameH = 24,
	subY = 33,
	subH = 18,
	barY = 38,
	barH = 12,
	rightW = 112, -- the chip or tick at the row's right end
	tick = 32,
	tickSize = 26,
	chipH = 28,
	stateSize = 15,
	badge = 40,
	rankTitleSize = 17,
	rankTitleY = 8,
	rankTitleH = 22,
	rankDescH = 34, -- two lines
	keepTitleY = 8,
	keepTitleH = 18,
	keepTitleSize = 15,
	keepBodyY = 27,
	keepBodyH = 34, -- two lines
	missingFade = 0.3, -- the greyed preview of a slime you don't have
})

-- Head line, chips, status, button and the crown card (design px).
Rebirth.TEXT = table.freeze({
	headSize = 17,
	countSize = 15,
	chipSize = 15,
	statusSize = 18,
	buttonSize = 22,
	crownSize = 54,
	crownH = 62,
	crownTitleSize = 26,
	crownTitleH = 32,
	crownSubH = 20,
	statH = 62,
	statValueSize = 22,
})

Rebirth.COPY = table.freeze({
	head = "Bring these",
	button = "Hold to rebirth",
	usedUp = "Used up on rebirth",
	getOne = "Catch or merge one",
	missing = "Missing",
	nowLabel = "Income now",
	nextLabel = "After rebirth",
	keepTitle = "You keep",
	resetTitle = "Resets",
	keep = "Other slimes, pads, upgrades, rank",
	keepAll = "Your slimes, pads, upgrades, rank",
	reset = "Your cash and the slimes above",
	resetCash = "Your cash",
	resetPads = "Your cash and %s on your pads", -- %s = State.padCash
	resetPadsSlimes = "Cash, %s on pads, the slimes above",
	lockMax = "Lock time is maxed",
	newTitle = "A new title",
	crownSub = "You finished every rebirth.",
	maxed = "All rebirths done",
})

-- "1 of 3 ready": the cash counts as one need, each slime as one more.
function Rebirth.countText(ready: number, total: number): string
	return `{ready} of {total} ready`
end

-- The two wells under the checklist: what stays and what the rebirth resets. `padCash` (State.padCash,
-- FEATURES.CashPads): cash still waiting on the cash pads, which the rebirth clears too.
function Rebirth.keepText(slimes: number, padCash: number?): (string, string)
	local keep = if slimes == 0 then Rebirth.COPY.keepAll else Rebirth.COPY.keep
	if padCash and padCash >= 1 then
		local pads = Format.formatCash(padCash)
		return keep, string.format(if slimes == 0 then Rebirth.COPY.resetPads else Rebirth.COPY.resetPadsSlimes, pads)
	end
	return keep, if slimes == 0 then Rebirth.COPY.resetCash else Rebirth.COPY.reset
end

local function capitalise(text: string): string
	return (string.gsub(text, "^%l", string.upper))
end

local function percent(value: number): string
	return `+{math.floor(value * 100 + 0.5)}%`
end

export type RankView = {
	up: boolean, -- this rebirth reaches the rank
	title: string,
	desc: string,
	income: string?, -- "+5% income": the rank's income bonus, only when `up`
}

-- The rank row for a player at `rebirths` (pure): the rank the next rebirth reaches, else the next one
-- ahead; nil past the last rank.
function Rebirth.rank(rebirths: number, tiers: { any }): RankView?
	local reached = nil
	for _, tier in tiers do
		if tier.rebirths == rebirths + 1 then
			reached = tier
		end
	end
	if reached then
		local parts = {}
		if reached.unlock then
			local def = Perks.upgradeDef(reached.unlock)
			table.insert(parts, `unlocks the {if def then def.name else reached.unlock} upgrade`)
		end
		local merges = MergeGate.opensAt(reached)
		if merges then
			table.insert(parts, `opens {merges} merges`)
		end
		local family = FountainTiers.family(reached.family)
		if family then
			local look = FountainTiers.LOOKS[family.tier]
			table.insert(parts, `grows the {if look then look.name else family.name}`)
		end
		return {
			up = true,
			title = `New rank: {reached.title}`,
			desc = if #parts > 0 then capitalise(table.concat(parts, ", ")) else Rebirth.COPY.newTitle,
			income = if reached.income then `{percent(reached.income)} income` else nil,
		}
	end
	local ahead = Perks.nextTier(rebirths)
	if not ahead then
		return nil
	end
	local what = Perks.tierText(ahead)
	return {
		up = false,
		title = `Next rank at Rebirth {ahead.rebirths}`,
		desc = if what ~= "" then `{ahead.title}: {what}` else ahead.title,
		income = nil,
	}
end

export type Plan = {
	heroY: number,
	perksY: number,
	rankY: number?, -- nil without a rank row
	headY: number,
	rows: { number }, -- y of the cash row, then one per slime
	keepY: number,
	buttonY: number,
	height: number,
}

-- Where everything goes for a rebirth that needs `slimes` slimes, with or without the rank row (pure).
function Rebirth.plan(slimes: number, withRank: boolean): Plan
	local r = Rebirth.ROWS
	local y = 0
	local heroY = y
	y += r.hero + r.gap
	local perksY = y
	y += r.perks + r.gap
	local rankY = nil
	if withRank then
		rankY = y
		y += r.rank + r.gap
	end
	local headY = y
	y += r.head + r.rowGap
	local rows = {}
	for i = 1, slimes + 1 do
		rows[i] = y
		y += r.row + (if i <= slimes then r.rowGap else 0)
	end
	y += r.gap
	local keepY = y
	y += r.keep + r.gap
	return {
		heroY = heroY,
		perksY = perksY,
		rankY = rankY,
		headY = headY,
		rows = rows,
		keepY = keepY,
		buttonY = y,
		height = y + Layout.BUTTON,
	}
end

function Rebirth.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "RebirthPanel", "Rebirth", "♻️")
	local R = Rebirth.ROWS
	local C = Rebirth.CARD
	local T = Rebirth.TEXT
	local COPY = Rebirth.COPY
	-- Scrolls only when the card is shorter than the content (landscape phones); a fixed canvas per layout.
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		Parent = panel.body,
	})

	local function well(name: string, h: number): Frame
		return create("Frame", {
			Name = name,
			BackgroundColor3 = Theme.Ink,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, h),
			Parent = content,
		}, { Widgets.corner(Widgets.KIT.rowRadius) }) :: Frame
	end

	local function text(props: { [string]: any }): TextLabel
		return Widgets.label(props)
	end

	-- The check mark emoji at a met row's right end.
	local function tick(parentRow: Instance): TextLabel
		local t = text({
			Name = "Tick",
			Text = "✅",
			TextSize = C.tickSize,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -C.pad, 0.5, 0),
			Size = UDim2.fromOffset(C.tick, C.tick),
			Parent = parentRow,
		})
		Widgets.centreEmoji(t)
		return t
	end

	-- A state chip at a row's right end ("Missing", what you have).
	local function stateChip(parentRow: Instance): TextLabel
		return Widgets.chip({
			Name = "State",
			TextSize = C.stateSize,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -C.pad, 0.5, 0),
			Size = UDim2.fromOffset(0, C.chipH),
			Parent = parentRow,
		})
	end

	-- Hero: income now → after the rebirth.
	local hero = well("Hero", R.hero)
	local function heroSide(name: string, label: string, x: UDim, color: Color3): TextLabel
		local side = create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.new(x, UDim.new(0, 0)),
			Size = UDim2.new(0.5, -C.arrowW / 2, 1, 0),
			Parent = hero,
		})
		text({
			Name = "Label",
			Text = label,
			TextSize = C.labelSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, C.heroLabelY),
			Size = UDim2.new(1, 0, 0, C.heroLabelH),
			Parent = side,
		})
		return text({
			Name = "Value",
			Font = Theme.Font,
			TextSize = C.heroValueSize,
			TextColor3 = color,
			TextStrokeColor3 = Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, C.heroValueY),
			Size = UDim2.new(1, 0, 0, C.heroValueH),
			Parent = side,
		})
	end
	local nowValue = heroSide("Now", COPY.nowLabel, UDim.new(0, 0), Theme.Muted)
	local nextValue = heroSide("Next", COPY.nextLabel, UDim.new(0.5, C.arrowW / 2), Theme.Good)
	text({
		Name = "Arrow",
		Text = "→",
		Font = Theme.Font,
		TextSize = C.arrowSize,
		TextColor3 = Theme.Good,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, C.heroValueY),
		Size = UDim2.fromOffset(C.arrowW, C.heroValueH),
		Parent = hero,
	})

	-- Perk chips, centred under the hero.
	local perks = create("Frame", {
		Name = "Perks",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, R.perks),
		Parent = content,
	}, { Widgets.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	local lockChip =
		Widgets.chip({ Name = "LockTime", TextSize = T.chipSize, Size = UDim2.fromOffset(0, R.perks), Parent = perks })
	local rankChip = Widgets.chip(
		{ Name = "RankIncome", TextSize = T.chipSize, Size = UDim2.fromOffset(0, R.perks), Parent = perks },
		Theme.Good
	)

	-- Rank row: Gold ring when this rebirth reaches it, a plain row when it is further ahead.
	local rankRow = Widgets.rowFrame({ Name = "Rank", Size = UDim2.new(1, 0, 0, R.rank), Parent = content })
	local rankStroke = rankRow:FindFirstChildOfClass("UIStroke") :: UIStroke
	local rankBadge = Widgets.iconBadge({
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, C.pad, 0.5, 0),
		Parent = rankRow,
	}, "🏅", Theme.Gold, C.badge)
	local rankTextX = C.pad + C.badge + C.textGap
	local rankTitle = text({
		Name = "RankTitle",
		Font = Theme.Font,
		TextSize = C.rankTitleSize,
		Position = UDim2.fromOffset(rankTextX, C.rankTitleY),
		Size = UDim2.new(1, -(rankTextX + C.pad), 0, C.rankTitleH),
		Parent = rankRow,
	})
	local rankDesc = text({
		Name = "RankDesc",
		TextSize = C.labelSize,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(rankTextX, C.rankTitleY + C.rankTitleH),
		Size = UDim2.new(1, -(rankTextX + C.pad), 0, C.rankDescH),
		Parent = rankRow,
	})

	-- Checklist head.
	local head = text({
		Name = "Head",
		Text = COPY.head,
		Font = Theme.Font,
		TextSize = T.headSize,
		Size = UDim2.new(0.5, 0, 0, R.head),
		Parent = content,
	})
	local count = Widgets.chip({
		Name = "Count",
		TextSize = T.countSize,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(0, R.head),
		Parent = content,
	})

	local textX = C.pad + Rebirth.SLIME_IMAGE + C.textGap
	local function rowName(row: Instance): TextLabel
		return text({
			Name = "Name",
			Font = Theme.Font,
			TextSize = C.nameSize,
			Position = UDim2.fromOffset(textX, C.nameY),
			Size = UDim2.new(1, -(textX + C.rightW), 0, C.nameH),
			Parent = row,
		})
	end

	-- Cash row: a coin, the cost, a Gold bar, and what you have (a tick once you can pay).
	local cashRow = Widgets.rowFrame({ Name = "Need", Size = UDim2.new(1, 0, 0, R.row), Parent = content })
	local coinWell = create("Frame", {
		Name = "Image",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, C.pad, 0.5, 0),
		Size = UDim2.fromOffset(Rebirth.SLIME_IMAGE, Rebirth.SLIME_IMAGE),
		BackgroundColor3 = Theme.Ink,
		Parent = cashRow,
	}, { Widgets.corner(Widgets.KIT.radius) })
	local coin = text({
		Name = "Coin",
		Text = "$",
		Font = Theme.Font,
		TextSize = 18,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Gold,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(32, 32),
		Parent = coinWell,
	})
	Widgets.pill().Parent = coin
	Widgets.stroke(Theme.GoldDeep, Widgets.KIT.stroke).Parent = coin
	local cost = rowName(cashRow)
	cost.Name = "Cost"
	local _, setBar =
		Widgets.bar(cashRow, Theme.Gold, UDim2.new(1, -(textX + C.rightW), 0, C.barH), UDim2.fromOffset(textX, C.barY))
	local have = stateChip(cashRow)
	have.Name = "Have"
	have.TextColor3 = Theme.Gold
	local cashTick = tick(cashRow)

	-- A slime row: the slime (greyed out while you don't have it), its name, a line on what happens to it,
	-- and Missing or a tick. The first is built now, the others the first time a rebirth needs them.
	type SlimeRow = {
		frame: Frame,
		image: Frame,
		view: ViewportFrame,
		name: TextLabel,
		desc: TextLabel,
		state: TextLabel,
		tick: TextLabel,
	}
	local slimeRows: { SlimeRow } = {}
	local function slimeRow(i: number): SlimeRow
		if slimeRows[i] then
			return slimeRows[i]
		end
		local frame = Widgets.rowFrame({
			Name = if i == 1 then "SlimeNeed" else `SlimeNeed{i}`,
			Size = UDim2.new(1, 0, 0, R.row),
			Parent = content,
		})
		local image = create("Frame", {
			Name = "Image",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, C.pad, 0.5, 0),
			Size = UDim2.fromOffset(Rebirth.SLIME_IMAGE, Rebirth.SLIME_IMAGE),
			BackgroundTransparency = 0.55,
			Parent = frame,
		}, { Widgets.corner(Widgets.KIT.radius), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
		local view = create("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = image,
		})
		local name = rowName(frame)
		name.Name = "SlimeName"
		local desc = text({
			Name = "SlimeDesc",
			TextSize = C.labelSize,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(textX, C.subY),
			Size = UDim2.new(1, -(textX + C.rightW), 0, C.subH),
			Parent = frame,
		})
		local state = stateChip(frame)
		state.Name = "SlimeState"
		state.Text = COPY.missing
		state.TextColor3 = Theme.Bad
		slimeRows[i] = {
			frame = frame,
			image = image,
			view = view,
			name = name,
			desc = desc,
			state = state,
			tick = tick(frame),
		}
		return slimeRows[i]
	end
	slimeRow(1)

	-- A "?" over a slime row's picture, made only if neither preview could be built.
	local function fallbackGlyph(row: SlimeRow): TextLabel
		local existing = row.image:FindFirstChild("Glyph")
		if existing then
			return existing :: TextLabel
		end
		return text({
			Name = "Glyph",
			Text = "?",
			Font = Theme.Font,
			TextSize = 24,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = row.image,
		})
	end

	-- Puts `slime` into the row's view: the real model (else a coloured blob), washed grey while missing.
	local function showSlime(row: SlimeRow, slime: Progress.SlimeNeed)
		local view = row.view
		local look = `{slime.id}:{slime.owned}`
		if view:GetAttribute("Look") ~= look then
			local opts = { greyed = not slime.owned }
			local ok = false
			if ctx.buildSlime then
				local genome = {
					id = `Rebirth_{slime.id}`,
					name = slime.name,
					tier = slime.tier,
					color = slime.color,
					size = 1,
					pattern = "Plain",
					eyes = "Round",
					mouth = "Smile",
					species = slime.id,
				}
				local built, model = pcall(ctx.buildSlime, genome)
				ok = built and model ~= nil and SlimePreview.mountModel(view, model, opts)
			end
			if not ok then
				ok = SlimePreview.mount(view, slime.color, opts)
			end
			view:SetAttribute("Look", look)
			view.Visible = ok
		end
		view.ImageTransparency = if slime.owned then 0 else C.missingFade
		if not view.Visible then
			fallbackGlyph(row).Visible = true
		elseif row.image:FindFirstChild("Glyph") then
			(row.image:FindFirstChild("Glyph") :: TextLabel).Visible = false
		end
		row.image.BackgroundColor3 = if slime.owned then Widgets.color3(slime.color) else Theme.Ink
	end

	local function paintSlime(row: SlimeRow, slime: Progress.SlimeNeed, y: number)
		row.frame.Visible = true
		row.frame.Position = UDim2.fromOffset(0, y)
		row.frame.BackgroundColor3 = if slime.owned then Theme.BgLight else Theme.Row
		row.name.Text = slime.name
		row.name.TextColor3 = if slime.owned then Theme.Text else Theme.Muted
		row.desc.Text = if slime.owned then COPY.usedUp else COPY.getOne
		row.state.Visible = not slime.owned
		row.tick.Visible = slime.owned
		showSlime(row, slime)
	end

	-- You keep / Resets.
	local keepWrap = create("Frame", {
		Name = "Keep",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, R.keep),
		Parent = content,
	})
	local function keepWell(name: string, title: string, color: Color3, x: UDim): TextLabel
		local box = create("Frame", {
			Name = name,
			BackgroundColor3 = Theme.Ink,
			Position = UDim2.new(x, UDim.new(0, 0)),
			Size = UDim2.new(0.5, -4, 1, 0),
			Parent = keepWrap,
		}, { Widgets.corner(Widgets.KIT.rowRadius) })
		text({
			Name = "Title",
			Text = title,
			Font = Theme.Font,
			TextSize = C.keepTitleSize,
			TextColor3 = color,
			Position = UDim2.fromOffset(C.pad + 2, C.keepTitleY),
			Size = UDim2.new(1, -(C.pad + 2) * 2, 0, C.keepTitleH),
			Parent = box,
		})
		return text({
			Name = "Body",
			TextSize = C.labelSize,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(C.pad + 2, C.keepBodyY),
			Size = UDim2.new(1, -(C.pad + 2) * 2, 0, C.keepBodyH),
			Parent = box,
		})
	end
	local keepBody = keepWell("Kept", COPY.keepTitle, Theme.Good, UDim.new(0, 0))
	local resetBody = keepWell("Reset", COPY.resetTitle, Theme.Bad, UDim.new(0.5, 4))

	-- Until every need is met: a sunken well saying what is missing, no button.
	local reasonLine = Widgets.status({
		Name = "Reason",
		TextSize = T.statusSize,
		Size = UDim2.new(1, 0, 0, Layout.BUTTON),
		Parent = content,
	})
	local btn = Widgets.holdButton(
		{
			Name = "RebirthButton",
			Text = COPY.button,
			Visible = false,
			Size = UDim2.new(1, 0, 0, Layout.BUTTON),
			TextSize = T.buttonSize,
		},
		Theme.Accent,
		function()
			ctx.send("Rebirth")
		end,
		ctx.Config.HOLD_CONFIRM_SECONDS
	)
	btn.instance.Parent = content

	-- At max rebirths: the crown card, built the first time it shows (few players get there).
	local CROWN_H = T.crownH + T.crownTitleH + T.crownSubH + R.gap + T.statH
	type Crown = { frame: Frame, title: TextLabel, rebirths: TextLabel, income: TextLabel, rank: TextLabel }
	local crownCard: Crown? = nil
	local function buildCrown(): Crown
		local crown = create("Frame", {
			Name = "Crown",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, CROWN_H),
			Parent = content,
		})
		text({
			Name = "Icon",
			Text = "👑",
			TextSize = T.crownSize,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, T.crownH),
			Parent = crown,
		})
		local crownTitle = text({
			Name = "CrownTitle",
			Font = Theme.Font,
			TextSize = T.crownTitleSize,
			TextColor3 = Theme.Gold,
			TextStrokeColor3 = Theme.Ink,
			TextStrokeTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, T.crownH),
			Size = UDim2.new(1, 0, 0, T.crownTitleH),
			Parent = crown,
		})
		text({
			Name = "CrownSub",
			Text = COPY.crownSub,
			TextSize = 15,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, T.crownH + T.crownTitleH),
			Size = UDim2.new(1, 0, 0, T.crownSubH),
			Parent = crown,
		})
		local statY = T.crownH + T.crownTitleH + T.crownSubH + R.gap
		local function stat(name: string, word: string, i: number): TextLabel
			local tile = create("Frame", {
				Name = name,
				BackgroundColor3 = Theme.Ink,
				Position = UDim2.new((i - 1) / 3, (i - 1) * 3, 0, statY),
				Size = UDim2.new(1 / 3, -6, 0, T.statH),
				Parent = crown,
			}, { Widgets.corner(Widgets.KIT.rowRadius) })
			text({
				Name = "Word",
				Text = word,
				TextSize = C.labelSize,
				TextColor3 = Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 36),
				Size = UDim2.new(1, 0, 0, 18),
				Parent = tile,
			})
			return text({
				Name = "Value",
				Font = Theme.Font,
				TextSize = T.statValueSize,
				TextColor3 = Theme.Good,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.new(1, 0, 0, 28),
				Parent = tile,
			})
		end
		return {
			frame = crown,
			title = crownTitle,
			rebirths = stat("Rebirths", "rebirths", 1),
			income = stat("Income", "income", 2),
			rank = stat("RankBonus", "rank bonus", 3),
		}
	end

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		local nextUp = Progress.nextRebirth(state, ctx.Config)
		local needs = nextUp.slimes
		local maxed = nextUp.maxed
		local rebirths = nextUp.rebirth - 1
		local cashMet = maxed or nextUp.have >= nextUp.cost
		panel.title.Text = if maxed then "Rebirth" else `Rebirth {nextUp.rebirth}`

		local rank = if maxed then nil else Rebirth.rank(rebirths, ctx.Config.REBIRTH_TIERS)
		local plan = Rebirth.plan(#needs, rank ~= nil)

		for _, inst in { hero, perks, head, count, cashRow, keepWrap } :: { GuiObject } do
			inst.Visible = not maxed
		end
		if crownCard then
			crownCard.frame.Visible = maxed
		end

		-- Hero and chips.
		hero.Position = UDim2.fromOffset(0, plan.heroY)
		nowValue.Text = Format.formatMultiplier(nextUp.current)
		nextValue.Text = Format.formatMultiplier(nextUp.multiplier)
		nextValue.TextStrokeTransparency = 0
		perks.Position = UDim2.fromOffset(0, plan.perksY)
		lockChip.Text = if nextUp.lockGain > 0 then `+{nextUp.lockGain}s lock time` else COPY.lockMax
		lockChip.TextColor3 = if nextUp.lockGain > 0 then Theme.Good else Theme.Muted
		rankChip.Visible = rank ~= nil and rank.income ~= nil
		rankChip.Text = if rank and rank.income then `Rank bonus {rank.income}` else ""

		-- Rank row.
		rankRow.Visible = rank ~= nil
		if rank and plan.rankY then
			rankRow.Position = UDim2.fromOffset(0, plan.rankY)
			rankRow.BackgroundColor3 = if rank.up then Theme.Ink else Theme.Row
			rankStroke.Color = if rank.up then Theme.Gold else Theme.Ink
			rankStroke.Thickness = if rank.up then Widgets.KIT.stroke else Widgets.KIT.rowStroke
			rankBadge.BackgroundColor3 = if rank.up then Theme.Gold else Theme.Ink
			rankTitle.Text = rank.title
			rankTitle.TextColor3 = if rank.up then Theme.Gold else Theme.Text
			rankDesc.Text = rank.desc
		end

		-- Checklist.
		local readyCount = (if cashMet then 1 else 0) + (#needs - #nextUp.missing)
		local total = #needs + 1
		head.Position = UDim2.fromOffset(0, plan.headY)
		count.Position = UDim2.new(1, 0, 0, plan.headY)
		count.Text = Rebirth.countText(readyCount, total)
		count.TextColor3 = if readyCount == total then Theme.Good else Theme.Muted

		cashRow.Position = UDim2.fromOffset(0, plan.rows[1])
		cashRow.BackgroundColor3 = if cashMet then Theme.BgLight else Theme.Row
		cost.Text = Format.formatCash(nextUp.cost)
		cost.TextColor3 = if cashMet then Theme.Gold else Theme.Muted
		cost.TextStrokeColor3 = Theme.Ink
		cost.TextStrokeTransparency = if cashMet then 0 else 1
		setBar(nextUp.fraction)
		have.Text = Format.formatCash(nextUp.have)
		have.Visible = not cashMet
		cashTick.Visible = cashMet

		for i = 1, math.max(#needs, #slimeRows) do
			local slime = needs[i]
			if slime and not maxed then
				paintSlime(slimeRow(i), slime, plan.rows[i + 1])
			elseif slimeRows[i] then
				slimeRows[i].frame.Visible = false
			end
		end

		keepWrap.Position = UDim2.fromOffset(0, plan.keepY)
		keepBody.Text, resetBody.Text = Rebirth.keepText(#needs, state.padCash)

		-- Button or what is missing.
		local buttonY = if maxed then CROWN_H + R.gap else plan.buttonY
		reasonLine.Position = UDim2.fromOffset(0, buttonY)
		btn.instance.Position = UDim2.fromOffset(0, buttonY)
		reasonLine.Text = Progress.rebirthReason(nextUp)
		reasonLine.Visible = not nextUp.ready
		btn.instance.Visible = nextUp.ready
		btn.setEnabled(nextUp.ready)

		if maxed then
			local card = crownCard or buildCrown()
			crownCard = card
			card.frame.Visible = true
			card.title.Text = Perks.title(rebirths)
			card.rebirths.Text = tostring(rebirths)
			card.income.Text = Format.formatMultiplier(nextUp.current)
			card.rank.Text = percent(Perks.rankIncomeBonus(rebirths))
		end
		content.CanvasSize = UDim2.fromOffset(0, if maxed then buttonY + Layout.BUTTON else plan.height)
	end

	-- init.client's card layout calls this; the panel has nothing that depends on the card width.
	function self.layout(_r: Layout.Rect) end

	return self
end

return Rebirth
