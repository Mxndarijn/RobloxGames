--!strict
--[[
	SlimeKeyCard

	One card over your nearest pad slime instead of three Roblox prompt bubbles stacked on the same spot. The
	SlimeKeys prompts (Move, Favorite, Sell) use ProximityPromptStyle.Custom, so Roblox draws nothing for them;
	this card shows the ones ProximityPromptService has shown:

	  * title: the slime's name (its GrabPrompt's ObjectText), and the favourite's perk under it;
	  * one glass row per shown prompt, in ORDER: a jelly key chip (E mint, R gold, X pink, or the gamepad
	    button) and the action text, with "Hold" on the right of a hold prompt;
	  * a hold prompt (Sell, Hatch) fills its row in its chip's colour while the key is held
	    (PromptButtonHoldBegan / Ended).

	The card is Goo glass (canvas GooWorldLabels "Slime key card"): deep teal with an Ink outline.

	The plot's LockButton gets the same card (FEATURES.FriendsInBase): the server gives its LockPrompt and
	FriendsPrompt the Custom style, so the owner sees one card titled with the lock status ("LOCKED 1:42" / "OPEN"),
	the friends switch's state under it, and a row each: E lock (hold) and G friends (instant). The card picks the
	part most shown prompts sit on, so a slime card and the lock card never mix.

	Hatch: the server's owner-only HatchPrompt on a Mystery Egg is on only while the egg is ready to hatch;
	SlimeKeys gives it the Custom style too, so it gets a row exactly when it can be hatched.

	Rows are buttons too: a click or tap holds that prompt (InputHoldBegin / End), so touch players use the card.
	The keys themselves still go through the prompts; the card only draws them.

	A click or tap hold belongs to its prompt and its InputObject, not to the row: when the card redraws (a new
	price, a prompt shown or hidden) while the press is down, the hold carries over to the new row, whose fill
	resumes at the elapsed fraction. The hold ends when that input is released (InputObject.Changed to End or
	Cancel, or a matching UserInputService.InputEnded) or when a redraw no longer shows its prompt; it never
	outlives the card.

	Pure helpers (ordered, keyLabel) are tested under Lune (tests/ui/SlimeKeyCard.spec.luau); `start` returns a
	stop function that disconnects everything and removes the card.
]]

local UI = script.Parent
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GooPalette = require(Shared:WaitForChild("GooPalette"))
local LabelFit =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Lib"):WaitForChild("ui"):WaitForChild("LabelFit"))
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local SlimeKeyCard = {}

-- Row order by prompt name (the server's HatchPrompt, SlimeKeys.MOVE_PROMPT / FAVORITE_PROMPT / SELL_PROMPT; the
-- LockButton's Constants.LOCK_PROMPT_NAME / FRIENDS_PROMPT_NAME).
SlimeKeyCard.ORDER = table.freeze({
	HatchPrompt = 1,
	MovePrompt = 2,
	FavoritePrompt = 3,
	SellPrompt = 4,
	[Constants.LOCK_PROMPT_NAME] = 5,
	[Constants.FRIENDS_PROMPT_NAME] = 6,
} :: { [string]: number })
-- Key chip colour per row: mint acts, gold is a favourite, pink can lose slimes (selling one, letting friends steal).
SlimeKeyCard.CHIP = table.freeze({
	HatchPrompt = Theme.Good,
	MovePrompt = Theme.Good,
	FavoritePrompt = Theme.Gold,
	SellPrompt = Theme.Bad,
	[Constants.LOCK_PROMPT_NAME] = Theme.Good,
	[Constants.FRIENDS_PROMPT_NAME] = Theme.Bad,
} :: { [string]: Color3 })

-- The card's title and the line under it for the part `parent` (a slime Body or the LockButton). A slime: its
-- GrabPrompt's name, and a favourite's perk (the Favorite prompt's ObjectText). The LockButton: the lock status
-- ("LOCKED 1:42" / "OPEN", from the LockPrompt's ObjectText) and the friends switch's state. Either is "" when that prompt is missing.
function SlimeKeyCard.heading(parent: Instance): (string, string)
	local function objectText(name: string): string
		local p = parent:FindFirstChild(name)
		return if p and p:IsA("ProximityPrompt") then p.ObjectText else ""
	end
	local title = objectText("GrabPrompt")
	local sub = objectText("FavoritePrompt")
	if title == "" then
		-- "<name>'s base: LOCKED 1:42" -> "LOCKED 1:42": it is the owner's own button, and the full text does not fit.
		local lock = objectText(Constants.LOCK_PROMPT_NAME)
		title = string.match(lock, ":%s*(.+)$") or lock
		sub = objectText(Constants.FRIENDS_PROMPT_NAME)
	end
	return title, if sub ~= title then sub else ""
end

-- The small line under the rows: on the lock card, while its Lock row shows, that standing on the lock pad's ring
-- locks too (LockPad); "" otherwise. `names` are the shown rows' prompt names.
SlimeKeyCard.LOCK_PAD_HINT = "or stand on the green ring"
function SlimeKeyCard.footer(names: { string }): string
	for _, name in names do
		if name == Constants.LOCK_PROMPT_NAME then
			return SlimeKeyCard.LOCK_PAD_HINT
		end
	end
	return ""
end

-- The world height of the top of a box at `cf` with `size`, however it is turned.
function SlimeKeyCard.worldTop(cf: CFrame, size: Vector3): number
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return cf.Position.Y + (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
end

-- Where the card's bottom edge goes over a part with no TagAnchor (the LockButton), as StudsOffsetWorldSpace, which
-- Roblox reads in the part's own axes: straight up in the world, `lift` studs over the top of the part or of the
-- tallest of `others` standing on its spot (the button's barrel look), so the card sits right above what you see.
function SlimeKeyCard.offsetOver(part: BasePart, others: { Instance }, lift: number): Vector3
	local top = SlimeKeyCard.worldTop(part.CFrame, part.Size)
	local at = part.CFrame.Position
	for _, o in others do
		if o ~= part and o:IsA("BasePart") then
			local d = (o :: BasePart).CFrame.Position - at
			if Vector2.new(d.X, d.Z).Magnitude < SlimeKeyCard.CARD.sameSpot then
				top = math.max(top, SlimeKeyCard.worldTop(o.CFrame, o.Size))
			end
		end
	end
	return part.CFrame:VectorToObjectSpace(Vector3.new(0, top - at.Y + lift, 0))
end

SlimeKeyCard.CARD = table.freeze({
	w = 236,
	pad = 12,
	titleH = 26,
	titleSize = 19,
	perkH = 18,
	perkSize = 14,
	rowH = 42,
	gap = 6,
	keySize = 34,
	keyTextSize = 17,
	textSize = 17,
	hintSize = 14,
	footGap = 4, -- px between the last row and the line under the rows
	radius = 22, -- the card's corners
	stroke = 3, -- Ink outline round the card and the key chips
	rowStroke = 2,
	lift = 1, -- studs above the slime's Body top (or the lock button's barrel)
	sameSpot = 1, -- studs; a part centred this close to the LockButton (its barrel look) counts as standing on it
	maxDistance = 40, -- studs; past this the card is not drawn
	bgTransparency = 0.06,
	fillTransparency = 0.65,
})

local GAMEPAD = table.freeze({
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	DPadUp = "Up",
	DPadDown = "Dn",
	DPadLeft = "Lt",
	DPadRight = "Rt",
} :: { [string]: string })

-- The text on a key chip: the keyboard key's name, or the gamepad button's short name.
function SlimeKeyCard.keyLabel(keyName: string, gamepad: boolean): string
	if gamepad then
		return GAMEPAD[keyName] or keyName
	end
	return keyName
end

-- The prompts this card draws, in row order (unknown names are left out).
function SlimeKeyCard.ordered<T>(prompts: { T }, nameOf: (T) -> string): { T }
	local out = {}
	for _, p in prompts do
		if SlimeKeyCard.ORDER[nameOf(p)] then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a, b)
		return SlimeKeyCard.ORDER[nameOf(a)] < SlimeKeyCard.ORDER[nameOf(b)]
	end)
	return out
end

export type Options = {
	prompts: ProximityPromptService,
	playerGui: Instance, -- where the BillboardGui lives (input on its rows needs a PlayerGui parent)
	tweens: TweenService,
	userInput: UserInputService?, -- releases of a click/tap hold; defaults to the real service
	clock: (() -> number)?, -- elapsed time of a hold's fill; defaults to os.clock
}

function SlimeKeyCard.start(opts: Options): () -> ()
	local C = SlimeKeyCard.CARD
	local card = create("BillboardGui", {
		Name = "SlimeKeyCard",
		Enabled = false,
		Active = true,
		AlwaysOnTop = true,
		ResetOnSpawn = false,
		LightInfluence = 0,
		MaxDistance = C.maxDistance,
		SizeOffset = Vector2.new(0, 0.5), -- the card's bottom edge sits on the anchor point
		Parent = opts.playerGui,
	}) :: BillboardGui
	LabelFit.mark(card) -- smaller pixels on a phone (Lib.ui.LabelFitView)
	local frame = create("Frame", {
		Name = "Card",
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = C.bgTransparency,
		Size = UDim2.fromScale(1, 1),
		Parent = card,
	}, { Widgets.corner(C.radius), Widgets.stroke(Theme.Ink, C.stroke) })
	local title = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = C.titleSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(C.pad, C.pad - 2),
		Size = UDim2.new(1, -C.pad * 2, 0, C.titleH),
		Parent = frame,
	})
	local perk = Widgets.label({
		Name = "Perk",
		TextSize = C.perkSize,
		TextColor3 = Theme.Good,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(C.pad, C.pad + C.titleH - 2),
		Size = UDim2.new(1, -C.pad * 2, 0, C.perkH),
		Visible = false,
		Parent = frame,
	})
	local foot = Widgets.label({
		Name = "Foot",
		TextSize = C.hintSize,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -C.pad * 2, 0, C.perkH),
		Visible = false,
		Parent = frame,
	})

	local shown: { [ProximityPrompt]: boolean } = {}
	local gamepad = false
	type Row = { frame: Frame, fill: Frame, conns: { RBXScriptConnection }, tween: Tween? }
	local rows: { [ProximityPrompt]: Row } = {}
	local watched: { [ProximityPrompt]: RBXScriptConnection } = {}
	local render: () -> ()
	local userInput: UserInputService = opts.userInput or game:GetService("UserInputService")
	local clock = opts.clock or os.clock

	-- Click/tap holds by prompt: the press's InputObject and the connection that watches it end.
	type PointerHold = { input: InputObject, conn: RBXScriptConnection? }
	local pointerHolds: { [ProximityPrompt]: PointerHold } = {}
	-- When each prompt's hold began (PromptButtonHoldBegan), so a redrawn row's fill picks up where it was.
	local holdStarted: { [ProximityPrompt]: number } = {}

	local function endPointerHold(prompt: ProximityPrompt)
		local hold = pointerHolds[prompt]
		if not hold then
			return
		end
		pointerHolds[prompt] = nil
		if hold.conn then
			hold.conn:Disconnect()
		end
		prompt:InputHoldEnd() -- an un-ended hold would still fire (Sell) after its button is gone
	end

	local function endAllPointerHolds()
		for prompt in pointerHolds do
			endPointerHold(prompt)
		end
	end

	local function beginPointerHold(prompt: ProximityPrompt, input: InputObject)
		if pointerHolds[prompt] then
			return
		end
		local hold: PointerHold = { input = input, conn = nil }
		pointerHolds[prompt] = hold
		local changed = (input :: any).Changed
		if changed then
			hold.conn = changed:Connect(function(prop: string)
				local state = input.UserInputState
				if
					prop == "UserInputState"
					and (state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel)
					and pointerHolds[prompt] == hold
				then
					endPointerHold(prompt)
				end
			end)
		end
		prompt:InputHoldBegin()
	end

	-- Ends the click/tap hold that `input` started, wherever it is released.
	local function releasePointer(input: InputObject)
		for prompt, hold in pointerHolds do
			if hold.input == input then
				endPointerHold(prompt)
			end
		end
	end

	-- Fills a hold prompt's row from the hold's elapsed fraction to full over the time that is left.
	local function startFill(prompt: ProximityPrompt, row: Row)
		local began = holdStarted[prompt]
		if not began or prompt.HoldDuration <= 0 then
			return
		end
		if row.tween then
			row.tween:Cancel()
		end
		local fraction = math.clamp((clock() - began) / prompt.HoldDuration, 0, 1)
		row.fill.Size = UDim2.fromScale(fraction, 1)
		local tween = opts.tweens:Create(
			row.fill,
			TweenInfo.new(prompt.HoldDuration * (1 - fraction), Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) }
		)
		row.tween = tween
		tween:Play()
	end

	-- Removes the rows. Click/tap holds stay: render ends the ones whose prompt is no longer drawn.
	local function clearRows()
		for _, row in rows do
			if row.tween then
				row.tween:Cancel()
			end
			for _, c in row.conns do
				c:Disconnect()
			end
			row.frame:Destroy()
		end
		table.clear(rows)
	end

	local function makeRow(prompt: ProximityPrompt, y: number): Row
		local chipColor = SlimeKeyCard.CHIP[prompt.Name] or Theme.Good
		local rowFrame = create("TextButton", {
			Name = prompt.Name,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Glass,
			BackgroundTransparency = GooPalette.GLASS_TRANSPARENCY,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(C.pad, y),
			Size = UDim2.new(1, -C.pad * 2, 0, C.rowH),
			Parent = frame,
		}, { Widgets.pill() }) :: TextButton
		local fill = create("Frame", {
			Name = "Fill",
			BorderSizePixel = 0,
			BackgroundColor3 = chipColor,
			BackgroundTransparency = C.fillTransparency,
			Size = UDim2.fromScale(0, 1),
			Parent = rowFrame,
		}, { Widgets.pill() }) :: Frame
		local inset = (C.rowH - C.keySize) / 2
		local chip = create("Frame", {
			Name = "Key",
			BackgroundColor3 = chipColor,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, inset, 0.5, 0),
			Size = UDim2.fromOffset(C.keySize, C.keySize),
			ZIndex = 2,
			Parent = rowFrame,
		}, { Widgets.pill(), Widgets.stroke(Theme.Ink, C.rowStroke) })
		Widgets.shade(chip)
		local keyText = Widgets.label({
			Name = "KeyText",
			Text = SlimeKeyCard.keyLabel(
				if gamepad then prompt.GamepadKeyCode.Name else prompt.KeyboardKeyCode.Name,
				gamepad
			),
			Font = Theme.Font,
			TextSize = C.keyTextSize,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = chip,
		})
		Widgets.inkOn(keyText, chipColor)
		local textX = inset + C.keySize + 10
		local hold = prompt.HoldDuration > 0
		Widgets.label({
			Name = "Action",
			Text = prompt.ActionText,
			Font = Theme.Font,
			TextSize = C.textSize,
			Position = UDim2.fromOffset(textX, 0),
			Size = UDim2.new(1, -(textX + (if hold then 48 else 8)), 1, 0),
			ZIndex = 2,
			Parent = rowFrame,
		})
		if hold then
			Widgets.label({
				Name = "Hint",
				Text = "Hold",
				TextSize = C.hintSize,
				TextColor3 = Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.new(0, 40, 1, 0),
				ZIndex = 2,
				Parent = rowFrame,
			})
		end
		-- A click or tap holds the prompt like its key would; the hold follows the input, not this row.
		local row: Row = { frame = rowFrame, fill = fill, conns = {}, tween = nil }
		row.conns = {
			rowFrame.InputBegan:Connect(function(input: InputObject)
				local t = input.UserInputType
				if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
					beginPointerHold(prompt, input)
				end
			end),
			rowFrame.InputEnded:Connect(releasePointer),
		}
		startFill(prompt, row) -- a hold that began before this redraw
		return row
	end

	-- Redraws the card for the slime whose prompts are shown.
	render = function()
		-- The Body most of the shown prompts sit on (all of them, normally).
		local count: { [Instance]: number } = {}
		local best, bestN = nil, 0
		for prompt in shown do
			local parent = prompt.Parent
			if parent then
				count[parent] = (count[parent] or 0) + 1
				if count[parent] > bestN then
					best, bestN = parent, count[parent]
				end
			end
		end
		clearRows()
		if not best or not best:IsA("BasePart") then
			card.Enabled = false
			card.Adornee = nil
			endAllPointerHolds()
			return
		end
		local list = {}
		for prompt in shown do
			if prompt.Parent == best then
				table.insert(list, prompt)
			end
		end
		list = SlimeKeyCard.ordered(list, function(p: ProximityPrompt): string
			return p.Name
		end)
		local name, perkText = SlimeKeyCard.heading(best)
		title.Text = name
		perk.Text = perkText
		perk.Visible = perkText ~= ""
		local y = C.pad + C.titleH + (if perk.Visible then C.perkH else 0) + C.gap
		local names = {}
		for _, prompt in list do
			rows[prompt] = makeRow(prompt, y)
			y += C.rowH + C.gap
			table.insert(names, prompt.Name)
		end
		foot.Text = SlimeKeyCard.footer(names)
		foot.Visible = foot.Text ~= ""
		if foot.Visible then
			foot.Position = UDim2.fromOffset(C.pad, y - C.gap + C.footGap)
			y += C.perkH + C.footGap
		end
		-- A click/tap hold whose prompt is no longer drawn has lost its button: end it.
		for prompt in pointerHolds do
			if not rows[prompt] then
				endPointerHold(prompt)
			end
		end
		local height = y - C.gap + C.pad
		card.Size = UDim2.fromOffset(C.w, height)
		-- Over the drawn slime: the TagAnchor (SlimeInfoCard, moved by SlimeLifeRunner) when the Body has one.
		local anchor = best:FindFirstChild(Constants.TAG_ANCHOR)
		if anchor and anchor:IsA("Attachment") then
			card.Adornee = anchor
			card.StudsOffsetWorldSpace = Vector3.new(0, best.Size.Y / 2 + C.lift, 0)
		else
			-- The LockButton lies on its side: an offset in its own axes would push the card sideways.
			card.Adornee = best
			local others = if best.Parent then best.Parent:GetChildren() else {}
			card.StudsOffsetWorldSpace = SlimeKeyCard.offsetOver(best :: BasePart, others, C.lift)
		end
		card.Enabled = #list > 0
	end

	local function watch(prompt: ProximityPrompt)
		if watched[prompt] then
			return
		end
		-- Favorite <-> Unfavorite, a new price, a new perk: redraw while shown.
		watched[prompt] = prompt.Changed:Connect(function(prop: string)
			if (prop == "ActionText" or prop == "ObjectText") and shown[prompt] then
				render()
			end
		end)
	end

	local function unwatch(prompt: ProximityPrompt)
		local c = watched[prompt]
		if c then
			c:Disconnect()
			watched[prompt] = nil
		end
	end

	local function ours(prompt: ProximityPrompt): boolean
		return SlimeKeyCard.ORDER[prompt.Name] ~= nil and prompt.Style == Enum.ProximityPromptStyle.Custom
	end

	local conns = {
		opts.prompts.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
			if not ours(prompt) then
				return
			end
			gamepad = inputType == Enum.ProximityPromptInputType.Gamepad
			shown[prompt] = true
			watch(prompt)
			render()
		end),
		opts.prompts.PromptHidden:Connect(function(prompt: ProximityPrompt)
			if not shown[prompt] then
				return
			end
			shown[prompt] = nil
			unwatch(prompt)
			render()
		end),
		opts.prompts.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
			holdStarted[prompt] = clock()
			local row = rows[prompt]
			if row then
				startFill(prompt, row)
			end
		end),
		opts.prompts.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
			holdStarted[prompt] = nil
			local row = rows[prompt]
			if row then
				if row.tween then
					row.tween:Cancel()
					row.tween = nil
				end
				row.fill.Size = UDim2.fromScale(0, 1)
			end
		end),
		userInput.InputEnded:Connect(releasePointer),
	}

	return function()
		for _, c in conns do
			c:Disconnect()
		end
		for prompt in watched do
			unwatch(prompt)
		end
		endAllPointerHolds()
		clearRows()
		card:Destroy()
	end
end

return SlimeKeyCard
