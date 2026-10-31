--!strict
--[[
	TutorialCard (client, contract/tutorial.md): the tutorial just above the item bar, as notice cards like the steal
	cards (Widgets.noticeCard / noticeIcon).

	* The step card: Gold ring (guidance), the step's icon, title and one hint line that names the current
	  device's control (Tutorial.fromState), and on the right "3/8" over a Hide button. It stays until the server
	  moves the step on. The card itself takes no taps; Hide puts it away until the next step, and the Guide's
	  "Show the tutorial again" brings it back.
	* The done card: Good (mint) ring, "🎉 <what was done>" for DONE_SECONDS after a step is done; after the last
	  step "Tutorial done" with a pointer to Goals. Their time is paused while a menu or popup hides them.

	The cards stack upwards from just above the hotbar (Layout.screen `hotbar`), at the banner width and clear of
	the nav. While the player carries a slime the bar is hidden and the carry card takes its place, so the cards
	sit above the carry card instead. `setMenuOpen` hides them for an open menu, the daily popup and the bag.
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
TutorialCard.SIDE_W = Layout.MIN_TOUCH_DESIGN -- the right column: "3/8" over Hide; the whole column is Hide's tap area
TutorialCard.HIDE_H = 26 -- the Hide pill (design px)
TutorialCard.HIDE_TEXT = "Hide"
TutorialCard.NARROW_W = 300 -- banner stacks narrower than this (design px) leave the "3/8" out and put Hide under the icon
TutorialCard.GAP = 10 -- design px between the cards and the hotbar (or the carry card) under them

export type TutorialCard = {
	frame: Frame,
	update: (state: any) -> (),
	tick: (now: number) -> (),
	setMenuOpen: (isOpen: boolean) -> (),
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
	local collapsed = false -- the player hid the current step's card
	local menuOpen = false
	local narrow = false -- a phone's narrow stack: no "3/8"
	local wanted = false -- a step is running
	local doneUntil = 0
	local finishedUntil = 0
	local skipped = false -- the player asked to skip: no "Tutorial done" card
	local screen: Layout.Screen? = nil
	local carrying = false -- the carry card has the hotbar's place

	local refresh: () -> ()

	-- The cards are built the first time something shows, so a player past the tutorial carries none.
	local parts: any = nil
	local function build(): any
		if parts then
			return parts
		end
		local done = buildCard(frame, "Done", 1, Theme.Good, 0)
		local step = buildCard(frame, "Step", 2, Theme.Gold, TutorialCard.SIDE_W)
		local function hide()
			collapsed = true
			refresh()
		end
		-- The right column, full card height, is Hide's tap area (at least MIN_TOUCH on a phone); the rest of the
		-- card takes no taps.
		local side = create("TextButton", {
			Name = "Hide",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 0),
			Size = UDim2.new(0, TutorialCard.SIDE_W, 1, 0),
			ZIndex = 2,
			Parent = step.card,
		})
		side.Activated:Connect(hide)
		local counter = Widgets.label({
			Name = "Counter",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, N.pad),
			Size = UDim2.new(1, 0, 0, N.sub),
			Font = Theme.Font,
			TextSize = N.sub,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = side,
		})
		local pill = Widgets.button({
			Name = "HideButton",
			Text = TutorialCard.HIDE_TEXT,
			TextSize = 14,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -N.pad),
			Size = UDim2.new(1, -4, 0, TutorialCard.HIDE_H),
			Parent = side,
		}, Theme.Info, hide)
		parts = { done = done, step = step, counter = counter, pill = pill.instance, side = side }
		return parts
	end

	function refresh()
		local showStep = wanted and not menuOpen and not collapsed
		local showDone = os.clock() < doneUntil and not menuOpen
		frame.Visible = showStep or showDone
		if not parts then
			return
		end
		local step, counter = parts.step, parts.counter
		step.card.Visible = showStep
		parts.done.card.Visible = showDone
		-- On a phone's narrow stack the "3/8" goes and Hide moves under the icon, so the title and hint keep the
		-- card's full width; the card is then at least as tall as the icon and the pill.
		local sideW = if narrow then 0 else TutorialCard.SIDE_W
		step.column.Size = UDim2.new(1, -(N.icon + N.gap + sideW), 0, 0)
		counter.Visible = not narrow
		local list = step.row:FindFirstChildOfClass("UIListLayout") :: UIListLayout
		list.VerticalAlignment = if narrow then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center
		step.card.Size = UDim2.new(1, 0, 0, if narrow then N.pad * 2 + N.icon + 4 + TutorialCard.HIDE_H else 0)
		parts.side.AnchorPoint = if narrow then Vector2.new(0, 1) else Vector2.new(1, 0)
		parts.side.Position = if narrow then UDim2.new(0, 4, 1, 0) else UDim2.new(1, -4, 0, 0)
		parts.side.Size = if narrow
			then UDim2.fromOffset(TutorialCard.SIDE_W, TutorialCard.SIDE_W)
			else UDim2.new(0, TutorialCard.SIDE_W, 1, 0)
		parts.pill.Position = if narrow
			then UDim2.new(0, N.pad - 4 + N.icon / 2, 1, -N.pad)
			else UDim2.new(0.5, 0, 1, -N.pad)
		parts.pill.Size = UDim2.new(0, if narrow then N.icon else TutorialCard.SIDE_W - 4, 0, TutorialCard.HIDE_H)
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
	end

	-- Bottom edge just above the hotbar, or above the carry card while carrying (the bar is hidden then).
	local function place()
		if not screen then
			return
		end
		local under = if carrying then math.min(screen.carry.y, screen.hotbar.y) else screen.hotbar.y
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

	-- Phones' narrow banner stack (Layout.screen banners narrower than NARROW_W) drops the "3/8" and keeps Hide.
	function self.layout(s: Layout.Screen)
		screen = s
		narrow = s.banners.w < TutorialCard.NARROW_W
		place()
		refresh()
	end

	function self.setMenuOpen(isOpen: boolean)
		menuOpen = isOpen
		refresh()
	end

	-- A step is running and its card is not hidden (the hint ring follows it).
	function self.shown(): boolean
		return wanted and not collapsed
	end

	-- The player hid the current step's card (the Guide offers to show it again).
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
