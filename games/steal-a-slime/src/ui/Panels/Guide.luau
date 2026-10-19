--!strict
--[[
	Guide panel (v28 item 5): what the Guide NPC tells you. Opened by "Talk"
	(E) at the TutorialNpc (init.client, Constants.GUIDE_PROMPT), closed like
	every menu (X, Esc, B, tap outside). Not in the nav. One next-goal card
	and up to GuideTips.MAX_TIPS icon tips (GuideTips.view).
]]

local UI = script.Parent.Parent
local GuideTips = require(UI.GuideTips)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Guide = {}

Guide.GOAL_H = 96
Guide.TIP_H = 44
Guide.GAP = 8
Guide.CONTENT_H = Guide.GOAL_H + Guide.GAP + GuideTips.MAX_TIPS * (Guide.TIP_H + Guide.GAP)

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
		Text = "NEXT GOAL",
		Font = Theme.Font,
		TextSize = 13,
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
		TextSize = 13,
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
			Position = UDim2.fromOffset(0, Guide.GOAL_H + Guide.GAP + (i - 1) * (Guide.TIP_H + Guide.GAP)),
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

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		local view = GuideTips.view(state, rarityNames, ctx.serverNow())
		goalIcon.Text = view.goalIcon
		goalText.Text = view.goal
		goalDetail.Text = view.goalDetail
		for i, row in tipRows do
			local tip = view.tips[i]
			row.Visible = tip ~= nil
			row.Text = if tip then `{tip.icon}  {tip.text}` else ""
		end
	end

	return self
end

return Guide
