--!strict
--[[
	Guide panel: what the Guide NPC tells you. Opened by "Talk" (E) at the TutorialNpc (init.client,
	Constants.GUIDE_PROMPT), closed like every menu (X, Esc, B, tap outside). Not in the nav. One next-goal card
	and up to GuideTips.MAX_TIPS icon tips (GuideTips.view). While the tutorial runs, the first slots hold its
	buttons: "Show the tutorial again" when the player shrank the tutorial card (ctx.tutorial, TutorialCard; it
	opens the card and closes the Guide), and "Hold to skip the tutorial" (Request SkipTutorial).
]]

local UI = script.Parent.Parent
local GuideTips = require(UI.GuideTips)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Guide = {}

Guide.GOAL_H = 96
Guide.TIP_H = 44
Guide.GAP = 8
Guide.CONTENT_H = Guide.GOAL_H + Guide.GAP + GuideTips.MAX_TIPS * (Guide.TIP_H + Guide.GAP)
Guide.SHOW_TEXT = "📖  Show the tutorial again"
Guide.SKIP_TEXT = "Hold to skip the tutorial"

local function slotY(slot: number): number
	return Guide.GOAL_H + Guide.GAP + (slot - 1) * (Guide.TIP_H + Guide.GAP)
end

function Guide.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "GuidePanel", "Guide", "🧙")
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		CanvasSize = UDim2.fromOffset(0, Guide.CONTENT_H),
		Parent = panel.body,
	})

	local goalCard = create("Frame", {
		Name = "Goal",
		BackgroundColor3 = Theme.Row,
		Size = UDim2.new(1, -8, 0, Guide.GOAL_H),
		Parent = content,
	}, { Widgets.corner(12) })
	local goalIcon = Widgets.iconBadge({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Parent = goalCard,
	}, "🎯", Theme.BgLight, 60)
	Widgets.label({
		Name = "Heading",
		Text = "Next goal",
		Font = Theme.Font,
		TextSize = Layout.MIN_TEXT,
		TextColor3 = Theme.Accent,
		Position = UDim2.fromOffset(82, 10),
		Size = UDim2.new(1, -92, 0, 16),
		Parent = goalCard,
	})
	local goalText = Widgets.label({
		Name = "GoalText",
		Font = Theme.Font,
		TextSize = 18,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(82, 28),
		Size = UDim2.new(1, -92, 0, 42),
		Parent = goalCard,
	})
	local goalDetail = Widgets.label({
		Name = "GoalDetail",
		TextSize = Layout.MIN_TEXT,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(82, 72),
		Size = UDim2.new(1, -92, 0, 16),
		Parent = goalCard,
	})

	local tipRows: { TextLabel } = {}
	for i = 1, GuideTips.MAX_TIPS do
		local row = Widgets.label({
			Name = `Tip{i}`,
			TextSize = 15,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.BgLight,
			Position = UDim2.fromOffset(0, slotY(i)),
			Size = UDim2.new(1, -8, 0, Guide.TIP_H),
			Parent = content,
		})
		Widgets.corner(10).Parent = row
		Widgets.create("UIPadding", { PaddingLeft = UDim.new(0, 12), Parent = row })
		tipRows[i] = row
	end

	local rarityNames: { string } = {}
	for i, rarity in ctx.Config.RARITIES do
		rarityNames[i] = rarity.name
	end

	local showTutorial = Widgets.button(
		{
			Name = "ShowTutorial",
			Text = Guide.SHOW_TEXT,
			TextSize = 15,
			Visible = false,
			Position = UDim2.fromOffset(0, slotY(1)),
			Size = UDim2.new(1, -8, 0, Guide.TIP_H),
			Parent = content,
		},
		Theme.Info,
		function()
			if ctx.tutorial then
				ctx.tutorial.showAgain()
			end
			if ctx.togglePanel then
				ctx.togglePanel("Guide") -- close the Guide so the card is in view
			end
		end
	)

	-- Ends the tutorial for good (Request SkipTutorial): a hold, like every action that can't be undone.
	local skipTutorial = Widgets.holdButton(
		{
			Name = "SkipTutorial",
			Text = Guide.SKIP_TEXT,
			TextSize = 15,
			Visible = false,
			Position = UDim2.fromOffset(0, slotY(1)),
			Size = UDim2.new(1, -8, 0, Guide.TIP_H),
			Parent = content,
		},
		Theme.BgLight,
		function()
			if ctx.tutorial then
				ctx.tutorial.skipping()
			end
			ctx.send("SkipTutorial")
		end,
		ctx.Config.HOLD_CONFIRM_SECONDS
	)

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		local view = GuideTips.view(state, rarityNames, ctx.serverNow())
		goalIcon.Text = view.goalIcon
		goalText.Text = view.goal
		goalDetail.Text = view.goalDetail
		local hidden = ctx.tutorial ~= nil and ctx.tutorial.hidden()
		local running = type(state) == "table" and state.tutorialStepId ~= nil
		showTutorial.instance.Visible = hidden
		skipTutorial.instance.Visible = running
		-- The tutorial buttons take the first slots, then the tips.
		local first = 1
		if hidden then
			first += 1
		end
		if running then
			skipTutorial.instance.Position = UDim2.fromOffset(0, slotY(first))
			first += 1
		end
		for i, row in tipRows do
			local tip = view.tips[i - first + 1]
			row.Visible = tip ~= nil
			row.Text = if tip then `{tip.icon}  {tip.text}` else ""
		end
	end

	return self
end

return Guide
