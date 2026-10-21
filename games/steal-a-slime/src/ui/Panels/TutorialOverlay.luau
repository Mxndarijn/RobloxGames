--!strict
--[[
	Tutorial overlay: a card at the bottom centre with the current step from
	Tutorial (`State.tutorialStepId`, else `tutorialStep`; CONTRACT §8.3). "Hide" hides it locally until the server moves to
	another step; the UI never advances the tutorial itself. While carrying,
	the card moves up so the carry panel (Drop) below it stays visible.
	`layout(screen)` takes both boxes from Layout.screen (card height fits
	the longest step body, Layout.tutorialHeight).
]]

local UI = script.Parent.Parent
local InputKind = require(UI.InputKind)
local Layout = require(UI.Layout)
local Tutorial = require(UI.Tutorial)
local Widgets = require(UI.Widgets)

local UserInputService = game:GetService("UserInputService")

local Theme = Widgets.Theme
local create = Widgets.create

local TutorialOverlay = {}

local BOTTOM = UDim2.new(0.5, 0, 1, -24)
local ABOVE_CARRY = UDim2.new(0.5, 0, 1, -24 - 96 - 12) -- Carry panel is 96px tall

function TutorialOverlay.new(parent: Instance, _ctx: any)
	local card = create("Frame", {
		Name = "TutorialOverlay",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = BOTTOM,
		Size = UDim2.fromOffset(520, 124),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.05,
		ZIndex = Layout.ZINDEX.Tutorial,
		Parent = parent,
	}, { Widgets.corner(Layout.NOTICE_RADIUS) })
	Widgets.ring(card, Theme.Gold, Layout.NOTICE_RADIUS) -- guidance is a Gold-ringed notice

	local counter = Widgets.label({
		Name = "Counter",
		TextSize = 12,
		TextColor3 = Theme.Accent,
		Font = Theme.Font,
		Size = UDim2.new(1, -100, 0, 16),
		Position = UDim2.fromOffset(14, 10),
		ZIndex = 11,
		Parent = card,
	})
	local title = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = 20,
		Size = UDim2.new(1, -100, 0, 24),
		Position = UDim2.fromOffset(14, 26),
		ZIndex = 11,
		Parent = card,
	})
	local body = Widgets.label({
		Name = "Body",
		TextSize = 14,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -Layout.TUTORIAL.padX * 2, 0, 60),
		Position = UDim2.fromOffset(Layout.TUTORIAL.padX, Layout.TUTORIAL.bodyTop),
		ZIndex = 11,
		Parent = card,
	})

	local shownStep: string? = nil
	local hiddenStep: string? = nil
	local wanted = false -- the step wants the card shown (not finished, not Hidden)
	local menuOpen = false

	local hide = Widgets.button(
		{
			Name = "Hide",
			Text = "Hide",
			TextSize = 13,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 8),
			Size = UDim2.fromOffset(72, Layout.MIN_TOUCH_DESIGN),
			ZIndex = 11,
		},
		Theme.BgLight,
		function()
			hiddenStep = shownStep
			wanted = false
			card.Visible = false
		end
	)
	hide.instance.Parent = card

	local self = { frame = card }
	local screen: Layout.Screen? = nil
	local carrying = false

	local function place()
		if screen == nil then
			card.AnchorPoint = Vector2.new(0.5, 1)
			card.Position = if carrying then ABOVE_CARRY else BOTTOM
			return
		end
		local r = if carrying then screen.tutorialCarrying else screen.tutorial
		card.AnchorPoint = Vector2.zero
		card.Position = UDim2.fromOffset(r.x, r.y)
		card.Size = UDim2.fromOffset(r.w, r.h)
		body.Size =
			UDim2.new(1, -Layout.TUTORIAL.padX * 2, 0, r.h - Layout.TUTORIAL.bodyTop - Layout.TUTORIAL.padBottom)
	end

	function self.layout(s: Layout.Screen)
		screen = s
		place()
	end

	-- A menu open hides the card (MenuState.tutorialVisible) without touching the
	-- step or the player's Hide choice; closing it restores the card as it was.
	function self.setMenuOpen(isOpen: boolean)
		menuOpen = isOpen
		card.Visible = wanted and not menuOpen
	end

	-- The step wants its card (and hint) shown, whether or not a menu covers it now.
	function self.shown(): boolean
		return wanted
	end

	local latest: any = nil

	function self.update(state: any)
		latest = state
		local view = Tutorial.fromState(state, InputKind.kind(UserInputService))
		shownStep = if view then view.id else nil
		wanted = view ~= nil and view.id ~= hiddenStep
		if view == nil or not wanted then
			card.Visible = false
			return
		end
		carrying = state.carrying ~= nil
		place()
		counter.Text = view.counter
		title.Text = view.title
		body.Text = view.body
		card.Visible = not menuOpen
	end

	-- The step text names the device's own control: it follows the last input.
	UserInputService.LastInputTypeChanged:Connect(function()
		if wanted and latest then
			local view = Tutorial.fromState(latest, InputKind.kind(UserInputService))
			if view then
				body.Text = view.body
			end
		end
	end)

	return self
end

return TutorialOverlay
