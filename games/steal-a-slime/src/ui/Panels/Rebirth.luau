--!strict
--[[
	Rebirth panel: v13 rank + next rank (when sent), readiness (READY / $ more needed + bar), the rebirth ladder
	(current tier and the next ones: income multiplier, lock length, cost; see
	Progress.rebirthTiers) and which slime is kept (favourite). The Rebirth
	button follows state.canRebirth (two clicks).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local Format = require(UI.Format)
local Progress = require(UI.Progress)
local Selection = require(UI.Selection)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme

local Rebirth = {}

local AHEAD = 3

function Rebirth.new(parent: Instance, ctx: any)
	local panel =
		Widgets.panel(parent, "RebirthPanel", "Rebirth", UDim2.fromOffset(420, 450), UDim2.new(0, 96, 0.5, -225))
	local layout = Widgets.list(Enum.FillDirection.Vertical, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = panel.body

	local function line(order: number, size: number?): TextLabel
		return Widgets.label({
			LayoutOrder = order,
			TextSize = size or 16,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			Size = UDim2.new(1, 0, 0, (size or 16) + 6),
			Parent = panel.body,
		})
	end

	-- v13 rank (hidden on servers without ranks).
	local rankLine = line(-2, 18)
	rankLine.Font = Theme.Font
	rankLine.TextColor3 = Theme.Gold
	local nextRankLine = line(-1, 13)
	nextRankLine.Size = UDim2.new(1, 0, 0, 34)
	nextRankLine.TextColor3 = Theme.Muted
	nextRankLine.TextYAlignment = Enum.TextYAlignment.Top

	local statusLine = line(1, 22)
	statusLine.Font = Theme.Font
	local barFrame, setBar = Widgets.bar(panel.body, Theme.Gold, UDim2.new(1, 0, 0, 14))
	barFrame.LayoutOrder = 2
	local costLine = line(3, 14)
	costLine.TextColor3 = Theme.Muted

	local ladderTitle = line(4, 14)
	ladderTitle.Font = Theme.Font
	ladderTitle.TextColor3 = Theme.Muted
	ladderTitle.Text = "EACH REBIRTH: +income multiplier, +lock time"

	local tierRows: { TextLabel } = {}
	for i = 1, AHEAD + 1 do
		local row = Widgets.label({
			Name = `Tier{i}`,
			LayoutOrder = 4 + i,
			TextSize = 14,
			BackgroundTransparency = 0.3,
			BackgroundColor3 = Theme.Row,
			Size = UDim2.new(1, 0, 0, 24),
			Parent = panel.body,
		})
		Widgets.corner(6).Parent = row
		Widgets.create("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = row })
		tierRows[i] = row
	end

	local keepLine = line(20)
	keepLine.Size = UDim2.new(1, 0, 0, 40)
	local warnLine = line(21, 13)
	warnLine.TextColor3 = Theme.Muted
	warnLine.Size = UDim2.new(1, 0, 0, 34) -- two lines; grows if it needs more
	warnLine.AutomaticSize = Enum.AutomaticSize.Y
	warnLine.Text = "Wipes cash and slimes. Keeps your ★ favourite, pads, shop upgrades and Slimedex."

	local btn = Widgets.confirmButton(
		{
			Name = "RebirthButton",
			Text = "Rebirth",
			LayoutOrder = 22,
			Size = UDim2.new(1, 0, 0, 44),
			TextSize = 18,
		},
		Theme.Gold,
		"Click again to rebirth",
		function()
			ctx.send("Rebirth")
		end
	)
	btn.instance.TextColor3 = Color3.fromRGB(40, 30, 10)
	btn.instance.Parent = panel.body

	local self = { frame = panel.frame }

	function self.update(state: any)
		local cfg = ctx.Config
		local rank = Progress.rank(state)
		rankLine.Visible = rank.title ~= nil
		nextRankLine.Visible = rank.next ~= nil
		rankLine.Text = rank.title or ""
		nextRankLine.Text = rank.next or ""
		panel.frame.Size = UDim2.fromOffset(420, if rank.title then 510 else 450)

		local status = Progress.rebirthStatus(state, cfg.MAX_REBIRTHS)
		statusLine.Text = status.text
		statusLine.TextColor3 = if status.ready then Theme.Gold else Theme.Text
		setBar(status.fraction)
		costLine.Text =
			`Next rebirth costs {Format.formatCash(state.rebirthCost)} · you have {Format.formatCash(state.cash)}`

		local tiers = Progress.rebirthTiers(state, cfg, Economy.rebirthCost, AHEAD)
		for i, row in tierRows do
			local tier = tiers[i]
			row.Visible = tier ~= nil
			if tier then
				row.Text = Progress.tierText(tier)
				row.TextColor3 = if tier.current then Theme.Accent elseif i == 2 then Theme.Gold else Theme.Text
				row.Font = if tier.current or i == 2 then Theme.Font else Theme.FontBody
			end
		end

		local fav = Selection.findSlime(state.slimes, state.favoriteId)
		if fav then
			keepLine.Text = `Keeper: ★ {ctx.Genome.displayName(fav.slime)}`
			keepLine.TextColor3 = Theme.Gold
		else
			keepLine.Text = "Keeper: your best slime (set a ★ favourite on the Plot panel to choose)"
			keepLine.TextColor3 = Theme.Muted
		end

		btn.setEnabled(state.canRebirth == true)
	end

	return self
end

return Rebirth
