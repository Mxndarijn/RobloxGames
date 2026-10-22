--!strict
--[[
	Rebirth panel: only the NEXT rebirth, its number in the title.

	One slime (or none): the cash card (cost, a progress bar, what you have) and the slime card side by side.
	Several slimes (Config.REBIRTH_SLIMES): the cash card runs full width on top, then one card per slime,
	two to a row. A slime card shows the slime (greyed out while you don't have it), its name, "Owned" or
	"Missing" and a line on what happens to it. The cost is muted until you can pay it, then gold.

	Under them: what it gives (income multiplier, lock time), a plain "Keeps your other slimes" line with a
	tick, then either a sunken well saying what is missing ("Need $15.5M and a Flan") or the hold-to-confirm
	Rebirth button (state.canRebirth), and the fine print. Progress.nextRebirth has the numbers.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Layout = require(UI.Layout)
local Progress = require(UI.Progress)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Rebirth = {}

Rebirth.SLIME_IMAGE = 52

-- Vertical rhythm of the body (design px).
Rebirth.ROWS = table.freeze({
	sub = { y = 0, h = 18 }, -- "You need both:"
	needY = 24, -- the requirement cards start here
	gap = 8, -- between cards, and between the cards and "You get:"
	gets = 20, -- "You get:" and the keeper line
	gives = 50, -- reward tiles
	givesGap = 4,
	buttonGap = 10,
	noteGap = 8,
})

-- Inside a requirement card (design px).
Rebirth.CARD = table.freeze({
	h = 128, -- cash and slime card side by side
	cashH = 92, -- the full-width cash card over several slime cards
	slimeH = 104, -- a slime card when there are several
	pad = 12,
	labelY = 10,
	labelH = 18,
	labelSize = Layout.MIN_TEXT,
	amountY = 32,
	amountH = 34,
	amountSize = 28,
	barY = 72,
	barH = 12,
	haveY = 98,
	haveH = 18,
	textGap = 10, -- picture to text
	nameSize = 19,
	nameH = 24,
	stateSize = 15,
	stateH = 20,
	descSize = Layout.MIN_TEXT,
	descH = 36, -- two lines
	missingFade = 0.3, -- the greyed preview of a slime you don't have
})

-- Reward tiles, keeper line, status, footer (design px).
Rebirth.TEXT = table.freeze({
	subSize = Layout.MIN_TEXT,
	gainSize = 22,
	gainY = 3,
	gainH = 26,
	gainLabelSize = Layout.MIN_TEXT,
	gainLabelY = 29,
	gainLabelH = 18,
	keeperSize = 15,
	statusSize = 18,
	buttonSize = 22,
	noteSize = Layout.MIN_TEXT,
})

Rebirth.COPY = table.freeze({
	keeper = "✅ Keeps your other slimes",
	button = "Hold to rebirth",
	owned = "✅ Owned",
	missing = "Missing",
	usedUp = "Used up on rebirth",
	getOne = "Catch one or merge one first",
	keep = "You keep your other slimes, your pads and your upgrades.",
	keepAll = "You keep your slimes, your pads and your upgrades.",
})

local COUNT_WORDS = { [3] = "three", [4] = "four", [5] = "five", [6] = "six" }

-- The line over the cards: how many things the rebirth needs (the cash and each slime).
function Rebirth.subText(slimes: number, maxed: boolean): string
	if maxed then
		return "All rebirths done"
	end
	local things = slimes + 1
	if things == 1 then
		return "You need:"
	elseif things == 2 then
		return "You need both:"
	end
	return `You need all {COUNT_WORDS[things] or tostring(things)}:`
end

-- The fine print: what the rebirth uses up and what you keep.
function Rebirth.noteText(needs: { Progress.SlimeNeed }): string
	if #needs == 0 then
		return `Rebirth resets your cash. {Rebirth.COPY.keepAll}`
	end
	local which = if #needs == 1 then "the slime above" else "the slimes above"
	return `Rebirth uses up {which} and resets your cash. {Rebirth.COPY.keep}`
end

export type Box = { position: UDim2, size: UDim2 }
export type Plan = {
	multi: boolean,
	cash: Box,
	cards: { Box }, -- one per slime
	getsY: number,
	givesY: number,
	buttonY: number,
	noteY: number,
	height: number, -- the content height with a `noteH` tall fine print
}

-- Where everything goes for a rebirth that needs `slimes` slimes (pure).
function Rebirth.plan(slimes: number, noteH: number): Plan
	local rows, c = Rebirth.ROWS, Rebirth.CARD
	local gap = rows.gap
	local y = rows.needY
	local half = UDim.new(0.5, -gap / 2)
	local right = UDim.new(0.5, gap / 2)
	local cash: Box
	local cards: { Box } = {}
	local multi = slimes > 1
	if not multi then
		cash = {
			position = UDim2.fromOffset(0, y),
			size = UDim2.new(if slimes == 1 then half else UDim.new(1, 0), UDim.new(0, c.h)),
		}
		if slimes == 1 then
			cards[1] = { position = UDim2.new(right, UDim.new(0, y)), size = UDim2.new(half, UDim.new(0, c.h)) }
		end
		y += c.h
	else
		cash = { position = UDim2.fromOffset(0, y), size = UDim2.new(1, 0, 0, c.cashH) }
		y += c.cashH + gap
		for i = 1, slimes do
			local row = (i - 1) // 2
			cards[i] = {
				position = UDim2.new(
					if i % 2 == 1 then UDim.new(0, 0) else right,
					UDim.new(0, y + row * (c.slimeH + gap))
				),
				size = UDim2.new(half, UDim.new(0, c.slimeH)),
			}
		end
		local cardRows = (slimes + 1) // 2
		y += cardRows * c.slimeH + (cardRows - 1) * gap
	end
	local getsY = y + gap
	local givesY = getsY + rows.gets + rows.givesGap
	local buttonY = givesY + rows.gives + rows.buttonGap
	local noteY = buttonY + Layout.BUTTON + rows.noteGap
	return {
		multi = multi,
		cash = cash,
		cards = cards,
		getsY = getsY,
		givesY = givesY,
		buttonY = buttonY,
		noteY = noteY,
		height = noteY + noteH,
	}
end

function Rebirth.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "RebirthPanel", "Rebirth", "♻️")
	local rows = Rebirth.ROWS
	local C = Rebirth.CARD
	local T = Rebirth.TEXT
	local COPY = Rebirth.COPY
	-- Scrolls only when the card is shorter than the content (landscape phones); a fixed canvas per layout.
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, -- a showing bar narrows the content, never covers it
		Parent = panel.body,
	})
	-- The body width the fine print wraps in: the last card layout's, a menu's width before the first one.
	local bodyW = Layout.MENU_WIDTH - Layout.PANEL_CHROME.pad * 2

	local sub = Widgets.label({
		Name = "Sub",
		TextSize = T.subSize,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(0, rows.sub.y),
		Size = UDim2.new(1, 0, 0, rows.sub.h),
		Parent = content,
	})

	local function cardLabel(name: string, text: string, card: Frame): TextLabel
		return Widgets.label({
			Name = name,
			Text = text,
			TextSize = C.labelSize,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(C.pad, C.labelY),
			Size = UDim2.new(1, -C.pad * 2, 0, C.labelH),
			Parent = card,
		})
	end

	-- Cash card: the cost (muted until you can pay it, then gold), a bar and what you have.
	local need = Widgets.rowFrame({ Name = "Need", Parent = content })
	cardLabel("Label", "Cash", need)
	local cost = Widgets.label({
		Name = "Cost",
		Font = Theme.Font,
		TextSize = C.amountSize,
		TextStrokeColor3 = Theme.Ink,
		Position = UDim2.fromOffset(C.pad, C.amountY),
		Size = UDim2.new(1, -C.pad * 2, 0, C.amountH),
		Parent = need,
	})
	local _, setBar =
		Widgets.bar(need, Theme.Gold, UDim2.new(1, -C.pad * 2, 0, C.barH), UDim2.fromOffset(C.pad, C.barY))
	local have = Widgets.label({
		Name = "Have",
		TextSize = C.descSize,
		TextColor3 = Theme.Muted,
		Parent = need,
	})

	-- A slime card: the slime (greyed out while you don't have it), its name, Owned / Missing and a line on
	-- what happens to it. The first is built now, the others the first time a rebirth needs them.
	type SlimeCard = {
		frame: Frame,
		label: TextLabel,
		image: Frame,
		view: ViewportFrame,
		name: TextLabel,
		state: TextLabel,
		desc: TextLabel,
	}
	local cards: { SlimeCard } = {}
	local function slimeCard(i: number): SlimeCard
		if cards[i] then
			return cards[i]
		end
		local frame = Widgets.rowFrame({
			Name = if i == 1 then "SlimeNeed" else `SlimeNeed{i}`,
			Parent = content,
		})
		local textX = C.pad + Rebirth.SLIME_IMAGE + C.textGap
		local function text(name: string, size: number, font: boolean, color: Color3, h: number): TextLabel
			return Widgets.label({
				Name = name,
				Font = if font then Theme.Font else nil,
				TextSize = size,
				TextColor3 = color,
				Position = UDim2.fromOffset(textX, 0),
				Size = UDim2.new(1, -(textX + C.pad), 0, h),
				Parent = frame,
			})
		end
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
		local label = text("Label", C.labelSize, false, Theme.Muted, C.labelH)
		label.Text = "This slime"
		local desc = text("SlimeDesc", C.descSize, false, Theme.Muted, C.descH)
		desc.TextWrapped = true
		desc.TextTruncate = Enum.TextTruncate.None
		desc.TextYAlignment = Enum.TextYAlignment.Top
		cards[i] = {
			frame = frame,
			label = label,
			image = image,
			view = view,
			name = text("SlimeName", C.nameSize, true, Theme.Text, C.nameH),
			state = text("SlimeState", C.stateSize, true, Theme.Bad, C.stateH),
			desc = desc,
		}
		return cards[i]
	end
	slimeCard(1)

	-- A "?" over a slime card's picture, made only if neither preview could be built.
	local function fallbackGlyph(card: SlimeCard): TextLabel
		local existing = card.image:FindFirstChild("Glyph")
		if existing then
			return existing :: TextLabel
		end
		return Widgets.label({
			Name = "Glyph",
			Text = "?",
			Font = Theme.Font,
			TextSize = C.amountSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = card.image,
		})
	end

	-- Puts `slime` into `view` the way the SlimeDex shows it: the species mesh, else the generated model, else a
	-- coloured blob, washed grey while missing. The look names whether the mesh was there, so a card that fell
	-- back switches to the mesh once it replicates.
	local function showSlime(card: SlimeCard, slime: Progress.SlimeNeed)
		local view = card.view
		local species: Model? = nil
		if ctx.buildSpecies then
			local built, model = pcall(ctx.buildSpecies, slime.id)
			species = if built then model else nil
		end
		local look = `{slime.id}:{slime.owned}:{species ~= nil}`
		if view:GetAttribute("Look") == look then
			if species then
				species:Destroy()
			end
		else
			local opts = { greyed = not slime.owned }
			local ok = species ~= nil and SlimePreview.mountModel(view, species :: Model, opts)
			if not ok and ctx.buildSlime then
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
			fallbackGlyph(card).Visible = true
		elseif card.image:FindFirstChild("Glyph") then
			(card.image:FindFirstChild("Glyph") :: TextLabel).Visible = false
		end
		card.image.BackgroundColor3 = if slime.owned then Widgets.color3(slime.color) else Theme.Ink
	end

	-- One slime card's text, stacked from the top: the label (one slime only), name, state, line.
	local function paintCard(card: SlimeCard, slime: Progress.SlimeNeed, box: Box, withLabel: boolean)
		card.frame.Visible = true
		card.frame.Position = box.position
		card.frame.Size = box.size
		card.label.Visible = withLabel
		local y = C.labelY + (if withLabel then C.labelH + 2 else 0)
		card.name.Position = UDim2.fromOffset(card.name.Position.X.Offset, y)
		card.name.Text = slime.name
		card.name.TextColor3 = if slime.owned then Theme.Text else Theme.Muted
		y += C.nameH + 2
		card.state.Position = UDim2.fromOffset(card.state.Position.X.Offset, y)
		card.state.Text = if slime.owned then COPY.owned else COPY.missing
		card.state.TextColor3 = if slime.owned then Theme.Good else Theme.Bad
		y += C.stateH + 4
		card.desc.Position = UDim2.fromOffset(card.desc.Position.X.Offset, y)
		card.desc.Text = if slime.owned then COPY.usedUp else COPY.getOne
		showSlime(card, slime)
	end

	-- What the next rebirth gives: two Ink tiles, a green number over a muted word.
	local gets = Widgets.label({
		Name = "Gets",
		Text = "You get:",
		TextSize = T.subSize,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(0.4, 0, 0, rows.gets),
		Parent = content,
	})
	local keepLine = Widgets.label({
		Name = "Keeper",
		Text = COPY.keeper,
		Font = Theme.Font,
		TextSize = T.keeperSize,
		TextColor3 = Theme.Good,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.new(0.6, 0, 0, rows.gets),
		Parent = content,
	})
	local function gainTile(name: string, word: string, x: UDim): (Frame, TextLabel)
		local tile = create("Frame", {
			Name = name,
			BackgroundColor3 = Theme.Ink,
			Position = UDim2.new(x, UDim.new(0, 0)),
			Size = UDim2.new(0.5, -rows.gap / 2, 0, rows.gives),
			Parent = content,
		}, { Widgets.corner(Widgets.KIT.radius) })
		local value = Widgets.label({
			Name = "Value",
			Font = Theme.Font,
			TextSize = T.gainSize,
			TextColor3 = Theme.Good,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, T.gainY),
			Size = UDim2.new(1, 0, 0, T.gainH),
			Parent = tile,
		})
		Widgets.label({
			Name = "Word",
			Text = word,
			TextSize = T.gainLabelSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, T.gainLabelY),
			Size = UDim2.new(1, 0, 0, T.gainLabelH),
			Parent = tile,
		})
		return tile, value
	end
	local incomeTile, incomeValue = gainTile("Income", "income", UDim.new(0, 0))
	local lockTile, lockValue = gainTile("LockTime", "lock time", UDim.new(0.5, rows.gap / 2))

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

	local note = Widgets.label({
		Name = "Note",
		TextSize = T.noteSize,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 0),
		Parent = content,
	})

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		local nextUp = Progress.nextRebirth(state, ctx.Config)
		local needs = nextUp.slimes
		local maxed = nextUp.maxed
		local cashMet = maxed or nextUp.have >= nextUp.cost
		panel.title.Text = if maxed then "Rebirth" else `Rebirth {nextUp.rebirth}`
		sub.Text = Rebirth.subText(#needs, maxed)

		note.Text = Rebirth.noteText(needs)
		local noteH = if maxed then 0 else math.ceil(Layout.wrappedHeight(note.Text, T.noteSize, bodyW))
		local plan = Rebirth.plan(#needs, noteH)

		need.Visible = not maxed
		need.Position = plan.cash.position
		need.Size = plan.cash.size
		cost.Text = Format.formatCash(nextUp.cost)
		cost.TextColor3 = if cashMet then Theme.Gold else Theme.Muted
		cost.TextStrokeTransparency = if cashMet then 0 else 1
		setBar(nextUp.fraction)
		have.Text = `You have {Format.formatCash(nextUp.have)}`
		if plan.multi then -- on the label line, right
			have.TextXAlignment = Enum.TextXAlignment.Right
			have.Position = UDim2.fromOffset(C.pad, C.labelY)
			have.Size = UDim2.new(1, -C.pad * 2, 0, C.labelH)
		else
			have.TextXAlignment = Enum.TextXAlignment.Left
			have.Position = UDim2.fromOffset(C.pad, C.haveY)
			have.Size = UDim2.new(1, -C.pad * 2, 0, C.haveH)
		end

		for i = 1, math.max(#needs, #cards) do
			local slime = needs[i]
			if slime and not maxed then
				paintCard(slimeCard(i), slime, plan.cards[i], not plan.multi)
			elseif cards[i] then
				cards[i].frame.Visible = false
			end
		end

		gets.Visible = not maxed
		gets.Position = UDim2.fromOffset(0, plan.getsY)
		keepLine.Visible = not maxed
		keepLine.Position = UDim2.new(1, 0, 0, plan.getsY)
		incomeTile.Visible = not maxed
		lockTile.Visible = not maxed
		incomeTile.Position = UDim2.fromOffset(0, plan.givesY)
		lockTile.Position = UDim2.new(0.5, rows.gap / 2, 0, plan.givesY)
		incomeValue.Text = Format.formatMultiplier(nextUp.multiplier)
		lockValue.Text = if nextUp.lockGain > 0 then `+{nextUp.lockGain}s` else "Max"

		local buttonY = if maxed then rows.needY else plan.buttonY
		reasonLine.Position = UDim2.fromOffset(0, buttonY)
		btn.instance.Position = UDim2.fromOffset(0, buttonY)
		reasonLine.Text = Progress.rebirthReason(nextUp)
		reasonLine.Visible = not nextUp.ready
		btn.instance.Visible = nextUp.ready
		btn.setEnabled(nextUp.ready)

		note.Visible = not maxed
		note.Position = UDim2.fromOffset(0, plan.noteY)
		note.Size = UDim2.new(1, 0, 0, noteH)
		content.CanvasSize = UDim2.fromOffset(0, if maxed then buttonY + Layout.BUTTON else plan.height)
	end

	-- init.client's card layout: remember the body width the fine print wraps in.
	function self.layout(r: Layout.Rect)
		bodyW = Layout.panelBody(r).w
	end

	return self
end

return Rebirth
