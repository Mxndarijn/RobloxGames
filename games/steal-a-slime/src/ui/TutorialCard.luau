--!strict
--[[
	TutorialCard (client, contract/tutorial.md): the tutorial just above the item bar, as notice cards like the steal
	cards (Widgets.noticeCard / noticeIcon).

	* The step card: Gold ring (guidance), the step's icon, title and one hint line that names the current
	  device's control (Tutorial.fromState), and "3/8" on the right. It stays until the server moves the step on.
	  Tapping it shrinks it to its icon; tapping again opens it. The Guide's "Show the tutorial again" opens it too.
	* The done card: Good (mint) ring, "🎉 <what was done>" for DONE_SECONDS after a step is done; after the last
	  step "Tutorial done" with a pointer to Goals. Their time is paused while a menu or popup hides them.

	The cards stack upwards from just above the hotbar (Layout.screen `hotbar`), at the banner width and clear of
	the nav. While the player carries a slime the bar is hidden and the carry card takes its place, so the cards
	sit above the carry card instead; move mode (SlimeMove, `setMoving`) uses the same slot. `setMenuOpen` hides them for an open menu, the daily popup and the bag.
	The UI never advances the tutorial; it only shows State.
]]

local UserInputService = game:GetService("UserInputService")

local InputKind =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Lib"):WaitForChild("ui"):WaitForChild("InputKind"))
local Layout = require(script.Parent.Layout)
local Tutorial = require(script.Parent.Tutorial)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local N = Layout.NOTICE_CARD

local TutorialCard = {}

TutorialCard.DONE_SECONDS = 2.5
TutorialCard.FINISHED_SECONDS = 6
TutorialCard.COUNTER_W = 44 -- the "3/8" column on the right
TutorialCard.NARROW_W = 300 -- banner stacks narrower than this (design px) leave the "3/8" column out
TutorialCard.GAP = 10 -- design px between the cards and the hotbar (or the carry card) under them

export type TutorialCard = {
	frame: Frame,
	update: (state: any) -> (),
	tick: (now: number) -> (),
	setMenuOpen: (isOpen: boolean) -> (),
	setMoving: (on: boolean) -> (),
	layout: (screen: Layout.Screen) -> (),
	shown: () -> boolean,
	hidden: () -> boolean,
	showAgain: () -> (),
	finishedShowing: () -> boolean,
	skipping: () -> (),
}

local function textColumn(row: Frame, rightPad: number): (TextLabel, TextLabel, Frame)
	local column = create("Frame", {
		Name = "Text",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(N.icon + N.gap + rightPad), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	}, { Widgets.list(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left) })
	local title = Widgets.label({
		Name = "Title",
		LayoutOrder = 1,
		Font = Theme.Font,
		TextSize = N.title,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = column,
	})
	local sub = Widgets.label({
		Name = "Sub",
		LayoutOrder = 2,
		FontFace = Theme.FontBody,
		TextSize = N.sub,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = column,
	})
	return title, sub, column
end

-- A notice card with an icon and a text column; `color` is the ring and icon colour.
local function buildCard(parent: Instance, name: string, order: number, color: Color3, rightPad: number): any
	local card, ring = Widgets.noticeCard({
		Name = name,
		LayoutOrder = order,
		Visible = false,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, color)
	local row = create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	}, {
		create("UIPadding", {
			PaddingLeft = UDim.new(0, N.pad),
			PaddingRight = UDim.new(0, N.pad + 4),
			PaddingTop = UDim.new(0, N.pad),
			PaddingBottom = UDim.new(0, N.pad),
		}),
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, N.gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local icon = Widgets.noticeIcon({ LayoutOrder = 1, Parent = row }, "", color)
	local title, sub, column = textColumn(row, rightPad)
	return { card = card, ring = ring, row = row, icon = icon, title = title, sub = sub, column = column }
end

-- The current device and the shown name of the tutorial prompts' key on it (Tutorial.PROMPT_KEYS), from
-- UserInputService so a PlayStation pad reads "Square" and a keyboard layout its own letter.
local function device(): (InputKind.Kind, string?)
	local kind: InputKind.Kind = InputKind.kind(UserInputService)
	if kind == "touch" then
		return kind, nil
	end
	local keyName: string = (Tutorial.PROMPT_KEYS :: any)[kind]
	local ok, text = pcall(function()
		return UserInputService:GetStringForKeyCode((Enum.KeyCode :: any)[keyName])
	end)
	if ok and type(text) == "string" and text ~= "" then
		return kind, if kind == "gamepad" then Tutorial.gamepadLabel(text) else text
	end
	return kind, nil
end

function TutorialCard.new(parent: Instance, _ctx: any, order: number): TutorialCard
	local frame = create("Frame", {
		Name = "Tutorial",
		LayoutOrder = order,
		Visible = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(Layout.BANNER_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = parent,
	}, {
		-- Bottom-aligned: the step card sits on the hotbar line and the done card stacks above it.
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, N.stack),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local latest: any = nil
	local shownId: string? = nil
	local collapsed = false
	local menuOpen = false
	local narrow = false -- a phone's narrow stack: no "3/8" column
	local wanted = false -- a step is running
	local doneUntil = 0
	local finishedUntil = 0
	local skipped = false -- the player asked to skip: no "Tutorial done" card
	local screen: Layout.Screen? = nil
	local carrying = false -- the carry card has the hotbar's place
	local moving = false -- the move card (SlimeMove) has it

	-- The cards are built the first time something shows, so a player past the tutorial carries none.
	local parts: any = nil
	local function build(): any
		if parts then
			return parts
		end
		local done = buildCard(frame, "Done", 1, Theme.Good, 0)
		local step = buildCard(frame, "Step", 2, Theme.Gold, TutorialCard.COUNTER_W)
		local counter = Widgets.label({
			Name = "Counter",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(N.pad + 4), 0.5, 0),
			Size = UDim2.fromOffset(TutorialCard.COUNTER_W, N.title),
			Font = Theme.Font,
			TextSize = N.sub,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = step.card,
		})
		-- The whole step card is the tap target that shrinks / opens it.
		local tap = create("TextButton", {
			Name = "Tap",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = step.card,
		})
		parts = { done = done, step = step, counter = counter, tap = tap }
		return parts
	end

	local function refresh()
		local showStep = wanted and not menuOpen
		local showDone = os.clock() < doneUntil and not menuOpen
		frame.Visible = showStep or showDone
		if not parts then
			return
		end
		local step, counter = parts.step, parts.counter
		step.card.Visible = showStep
		parts.done.card.Visible = showDone
		step.column.Visible = not collapsed
		step.column.Size = UDim2.new(1, -(N.icon + N.gap + (if narrow then 0 else TutorialCard.COUNTER_W)), 0, 0)
		counter.Visible = not collapsed and not narrow
		step.card.AutomaticSize = if collapsed then Enum.AutomaticSize.XY else Enum.AutomaticSize.Y
		step.card.Size = if collapsed then UDim2.fromOffset(0, 0) else UDim2.fromScale(1, 0)
		step.row.AutomaticSize = if collapsed then Enum.AutomaticSize.XY else Enum.AutomaticSize.Y
		step.row.Size = if collapsed then UDim2.fromOffset(0, 0) else UDim2.fromScale(1, 0)
	end

	local function showDone(title: string, sub: string?, seconds: number)
		local done = build().done
		done.icon.Text = "🎉"
		done.title.Text = title
		done.sub.Text = sub or ""
		done.sub.Visible = sub ~= nil
		doneUntil = os.clock() + seconds
	end

	local function draw()
		local view = Tutorial.fromState(latest, device())
		if view == nil then
			return
		end
		local p = build()
		p.step.icon.Text = view.icon
		p.step.title.Text = view.title
		p.step.sub.Text = view.body
		p.counter.Text = view.counter
		if not p.wired then
			p.wired = true
			p.tap.Activated:Connect(function()
				collapsed = not collapsed
				refresh()
			end)
		end
	end

	-- Bottom edge just above the hotbar, or above the carry card while carrying (the bar is hidden then).
	local function place()
		if not screen then
			return
		end
		local under = if carrying or moving then math.min(screen.carry.y, screen.hotbar.y) else screen.hotbar.y
		frame.Size = UDim2.fromOffset(math.round(screen.banners.w), 0)
		frame.Position = UDim2.fromOffset(math.round(screen.banners.x), math.round(under - TutorialCard.GAP))
	end

	local self = {} :: TutorialCard
	self.frame = frame

	function self.update(state: any)
		latest = state
		local id = if type(state) == "table" and type(state.tutorialStepId) == "string"
			then state.tutorialStepId
			else nil
		if id ~= shownId then
			local before = if shownId then Tutorial.find(shownId) else nil
			if before and id ~= nil then
				showDone(before.done, nil, TutorialCard.DONE_SECONDS)
			elseif before and not skipped then
				showDone(Tutorial.FINISHED, Tutorial.FINISHED_SUB, TutorialCard.FINISHED_SECONDS)
				finishedUntil = doneUntil
			end
			shownId = id
			collapsed = false
			skipped = false
		end
		wanted = id ~= nil
		local nowCarrying = type(state) == "table" and state.carrying ~= nil
		if nowCarrying ~= carrying then
			carrying = nowCarrying
			place()
		end
		draw()
		refresh()
	end

	local lastTick = os.clock()
	function self.tick(_now: number)
		local t = os.clock()
		-- A done card's time only runs while it can be seen: a menu or popup over it pauses it.
		if menuOpen and doneUntil > t then
			doneUntil += t - lastTick
			if finishedUntil > t then
				finishedUntil += t - lastTick
			end
		end
		lastTick = t
		if parts and parts.done.card.Visible and t >= doneUntil then
			refresh()
		end
	end

	-- Phones' narrow banner stack (Layout.screen banners narrower than NARROW_W) drops the "3/8" column so the
	-- title and hint keep their width.
	function self.layout(s: Layout.Screen)
		screen = s
		narrow = s.banners.w < TutorialCard.NARROW_W
		place()
		refresh()
	end

	function self.setMoving(on: boolean)
		if on ~= moving then
			moving = on
			place()
		end
	end

	function self.setMenuOpen(isOpen: boolean)
		menuOpen = isOpen
		refresh()
	end

	-- A step is running and its card is not shrunk (the hint ring follows it).
	function self.shown(): boolean
		return wanted and not collapsed
	end

	-- The player shrank the current step's card (the Guide offers to show it again).
	function self.hidden(): boolean
		return wanted and collapsed
	end

	function self.showAgain()
		collapsed = false
		draw()
		refresh()
	end

	-- The Guide's Skip was confirmed: the end of the tutorial that follows shows no "Tutorial done" card.
	function self.skipping()
		skipped = true
	end

	-- The "Tutorial done" card is up (the hint rings Goals meanwhile).
	function self.finishedShowing(): boolean
		return os.clock() < finishedUntil
	end

	-- The hint line names the device's own control: it follows the last input.
	UserInputService.LastInputTypeChanged:Connect(function()
		if wanted then
			draw()
		end
	end)

	return self
end

return TutorialCard
