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

	Hatch: the server's owner-only HatchPrompt on a Mystery Egg is on only while the egg is ready to hatch;
	SlimeKeys gives it the Custom style too, so it gets a row exactly when it can be hatched.

	Rows are buttons too: a click or tap holds that prompt (InputHoldBegin / End), so touch players use the card.
	The keys themselves still go through the prompts; the card only draws them.

	Pure helpers (ordered, keyLabel) are tested under Lune (tests/ui/SlimeKeyCard.spec.luau); `start` returns a
	stop function that disconnects everything and removes the card.
]]

local UI = script.Parent
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GooPalette = require(Shared:WaitForChild("GooPalette"))
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local SlimeKeyCard = {}

-- Row order by prompt name (the server's HatchPrompt, SlimeKeys.MOVE_PROMPT / FAVORITE_PROMPT / SELL_PROMPT).
SlimeKeyCard.ORDER =
	table.freeze({ HatchPrompt = 1, MovePrompt = 2, FavoritePrompt = 3, SellPrompt = 4 } :: { [string]: number })
-- Key chip colour per row: mint acts, gold is a favourite, pink loses the slime.
SlimeKeyCard.CHIP = table.freeze({
	HatchPrompt = Theme.Good,
	MovePrompt = Theme.Good,
	FavoritePrompt = Theme.Gold,
	SellPrompt = Theme.Bad,
} :: { [string]: Color3 })
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
	radius = 22, -- the card's corners
	stroke = 3, -- Ink outline round the card and the key chips
	rowStroke = 2,
	lift = 1, -- studs above the slime's Body top
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

	local shown: { [ProximityPrompt]: boolean } = {}
	local gamepad = false
	type Row = { frame: Frame, fill: Frame, conns: { RBXScriptConnection }, tween: Tween? }
	local rows: { [ProximityPrompt]: Row } = {}
	local watched: { [ProximityPrompt]: RBXScriptConnection } = {}
	local render: () -> ()

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
		-- A click or tap holds the prompt like its key would.
		local conns = {
			rowFrame.InputBegan:Connect(function(input: InputObject)
				local t = input.UserInputType
				if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
					prompt:InputHoldBegin()
				end
			end),
			rowFrame.InputEnded:Connect(function(input: InputObject)
				local t = input.UserInputType
				if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
					prompt:InputHoldEnd()
				end
			end),
		}
		return { frame = rowFrame, fill = fill, conns = conns, tween = nil }
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
		local grab = best:FindFirstChild("GrabPrompt")
		local name = if grab and grab:IsA("ProximityPrompt") then grab.ObjectText else ""
		title.Text = name
		-- The favourite's Favorite prompt carries its perk as ObjectText (SlimeKeys.labels).
		local fav = best:FindFirstChild("FavoritePrompt")
		local perkText = if fav and fav:IsA("ProximityPrompt") and fav.ObjectText ~= name then fav.ObjectText else ""
		perk.Text = perkText
		perk.Visible = perkText ~= ""
		local y = C.pad + C.titleH + (if perk.Visible then C.perkH else 0) + C.gap
		for _, prompt in list do
			rows[prompt] = makeRow(prompt, y)
			y += C.rowH + C.gap
		end
		local height = y - C.gap + C.pad
		card.Size = UDim2.fromOffset(C.w, height)
		-- Over the drawn slime: the TagAnchor (SlimeInfoCard, moved by SlimeLifeRunner) when the Body has one.
		local anchor = best:FindFirstChild(Constants.TAG_ANCHOR)
		card.Adornee = if anchor and anchor:IsA("Attachment") then anchor else best
		card.StudsOffsetWorldSpace = Vector3.new(0, best.Size.Y / 2 + C.lift, 0)
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
			local row = rows[prompt]
			if row and prompt.HoldDuration > 0 then
				if row.tween then
					row.tween:Cancel()
				end
				row.fill.Size = UDim2.fromScale(0, 1)
				local tween = opts.tweens:Create(
					row.fill,
					TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear),
					{ Size = UDim2.fromScale(1, 1) }
				)
				row.tween = tween
				tween:Play()
			end
		end),
		opts.prompts.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
			local row = rows[prompt]
			if row then
				if row.tween then
					row.tween:Cancel()
					row.tween = nil
				end
				row.fill.Size = UDim2.fromScale(0, 1)
			end
		end),
	}

	return function()
		for _, c in conns do
			c:Disconnect()
		end
		for prompt in watched do
			unwatch(prompt)
		end
		clearRows()
		card:Destroy()
	end
end

return SlimeKeyCard
