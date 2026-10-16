--!strict
--[[
	Rebirth panel (v28): only the NEXT rebirth. One requirement card (its
	cash cost, a progress bar and how much is still missing), one line of
	what it gives (income multiplier, lock time), the keeper and the
	Rebirth button (state.canRebirth, two clicks). No ladder of later tiers,
	no rank essay: Progress.nextRebirth has the numbers.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Layout = require(UI.Layout)
local Progress = require(UI.Progress)
local Selection = require(UI.Selection)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Rebirth = {}

-- Body rows top to bottom (design px; the body is Layout.panelBody of the
-- Rebirth card, MENU_HEIGHTS.Rebirth tall).
Rebirth.ROWS = table.freeze({
	need = { y = 0, h = 112 }, -- requirement card
	slime = { y = 120, h = 72 }, -- v29: the slime it also needs
	gives = { y = 200, h = 40 }, -- reward chips
	keeper = { y = 246, h = 22 },
	button = { y = 276, h = Layout.BUTTON },
	note = { y = 338, h = 18 },
})
Rebirth.CONTENT_H = 356 -- note.y + note.h
Rebirth.SLIME_IMAGE = 56

function Rebirth.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "RebirthPanel", "Rebirth", "♻️", Color3.fromRGB(200, 150, 40))
	local rows = Rebirth.ROWS
	-- Scrolls only when the card is shorter than the content (landscape
	-- phones); a fixed canvas, nothing in it moves.
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		CanvasSize = UDim2.fromOffset(0, Rebirth.CONTENT_H),
		Parent = panel.body,
	})

	-- Requirement card: "NEXT: REBIRTH n", the cost, a bar, what's missing.
	local need = create("Frame", {
		Name = "Need",
		BackgroundColor3 = Theme.Row,
		Position = UDim2.fromOffset(0, rows.need.y),
		Size = UDim2.new(1, 0, 0, rows.need.h),
		Parent = content,
	}, { Widgets.corner(12) })
	local heading = Widgets.label({
		Name = "Heading",
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 18),
		Parent = need,
	})
	local cost = Widgets.label({
		Name = "Cost",
		Font = Theme.Font,
		TextSize = 30,
		TextColor3 = Theme.Gold,
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -24, 0, 36),
		Parent = need,
	})
	local _, setBar = Widgets.bar(need, Theme.Gold, UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 68))
	local missing = Widgets.label({
		Name = "Missing",
		TextSize = 14,
		Position = UDim2.fromOffset(12, 86),
		Size = UDim2.new(1, -24, 0, 18),
		Parent = need,
	})

	-- v29: the slime this rebirth also needs. Image first (the real slime in a
	-- viewport, a dark silhouette while missing), its name, then Owned / Missing.
	local slimeCard = create("Frame", {
		Name = "SlimeNeed",
		BackgroundColor3 = Theme.Row,
		Position = UDim2.fromOffset(0, rows.slime.y),
		Size = UDim2.new(1, 0, 0, rows.slime.h),
		Parent = content,
	}, { Widgets.corner(12) })
	local imageSize = Rebirth.SLIME_IMAGE
	local slimeImage = create("Frame", {
		Name = "Image",
		Position = UDim2.fromOffset(8, (rows.slime.h - imageSize) // 2),
		Size = UDim2.fromOffset(imageSize, imageSize),
		BackgroundTransparency = 0.55,
		Parent = slimeCard,
	}, { Widgets.corner(14) })
	local slimeView = create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = slimeImage,
	})
	local slimeGlyph = Widgets.label({
		Name = "Glyph",
		Text = "?",
		Font = Theme.Font,
		TextSize = 28,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Size = UDim2.fromScale(1, 1),
		Parent = slimeImage,
	})
	local slimeHeading = Widgets.label({
		Name = "SlimeHeading",
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(imageSize + 18, 8),
		Size = UDim2.new(1, -(imageSize + 26), 0, 16),
		Parent = slimeCard,
	})
	local slimeName = Widgets.label({
		Name = "SlimeName",
		Font = Theme.Font,
		TextSize = 18,
		Position = UDim2.fromOffset(imageSize + 18, 24),
		Size = UDim2.new(1, -(imageSize + 26), 0, 22),
		Parent = slimeCard,
	})
	local slimeState = Widgets.label({
		Name = "SlimeState",
		Font = Theme.Font,
		TextSize = 15,
		Position = UDim2.fromOffset(imageSize + 18, 46),
		Size = UDim2.new(1, -(imageSize + 26), 0, 18),
		Parent = slimeCard,
	})

	-- What the next rebirth gives: two chips.
	local function chip(name: string, x: UDim): TextLabel
		local label = Widgets.label({
			Name = name,
			Font = Theme.Font,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.BgLight,
			Position = UDim2.new(x, UDim.new(0, rows.gives.y)),
			Size = UDim2.new(0.5, -4, 0, rows.gives.h),
			Parent = content,
		})
		Widgets.corner(10).Parent = label
		return label
	end
	local incomeChip = chip("Income", UDim.new(0, 0))
	local lockChip = chip("LockTime", UDim.new(0.5, 4))

	local keepLine = Widgets.label({
		Name = "Keeper",
		TextSize = 15,
		Position = UDim2.fromOffset(0, rows.keeper.y),
		Size = UDim2.new(1, 0, 0, rows.keeper.h),
		Parent = content,
	})

	local btn = Widgets.confirmButton(
		{
			Name = "RebirthButton",
			Text = "♻️ Rebirth",
			Position = UDim2.fromOffset(0, rows.button.y),
			Size = UDim2.new(1, 0, 0, rows.button.h),
			TextSize = 20,
		},
		Theme.Gold,
		"Tap again to rebirth",
		function()
			ctx.send("Rebirth")
		end
	)
	btn.instance.TextColor3 = Color3.fromRGB(40, 30, 10)
	btn.instance.Parent = content

	Widgets.label({
		Name = "Note",
		Text = "Resets cash and slimes. Keeps ★, pads, upgrades.",
		TextSize = 12,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, rows.note.y),
		Size = UDim2.new(1, 0, 0, rows.note.h),
		Parent = content,
	})

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		local nextUp = Progress.nextRebirth(state, ctx.Config)
		heading.Text = if nextUp.maxed then "ALL REBIRTHS DONE" else `TO REBIRTH {nextUp.rebirth} YOU NEED`
		cost.Text = if nextUp.maxed then "🏆 Max" else `💰 {Format.formatCash(nextUp.cost)}`
		setBar(nextUp.fraction)
		missing.Text = if nextUp.maxed then "" else `{nextUp.progress} · {nextUp.need}`
		missing.TextColor3 = if nextUp.ready then Theme.Accent else Theme.Text
		incomeChip.Text = `📈 {Format.formatMultiplier(nextUp.multiplier)} income`
		lockChip.Text = `🔒 +{nextUp.lockGain}s lock`
		incomeChip.Visible = not nextUp.maxed
		lockChip.Visible = not nextUp.maxed

		local fav = Selection.findSlime(state.slimes, state.favoriteId)
		keepLine.Text = if fav then `⭐ Keeps {ctx.Genome.displayName(fav.slime)}` else "⭐ Keeps your best slime"
		keepLine.TextColor3 = if fav then Theme.Gold else Theme.Muted

		slimeCard.Visible = nextUp.slime ~= nil
		local slimeNeed = nextUp.slime
		if slimeNeed then
			slimeHeading.Text = "AND THIS SLIME"
			slimeName.Text = slimeNeed.name
			slimeCard.BackgroundTransparency = if slimeNeed.owned then 0 else 0.35
			slimeName.TextColor3 = if slimeNeed.owned then Theme.Text else Theme.Muted
			slimeState.Text = if slimeNeed.owned then "✅ Owned" else "Missing"
			slimeState.TextColor3 = if slimeNeed.owned then Theme.Accent else Theme.Muted
			slimeImage.BackgroundColor3 = Widgets.color3(slimeNeed.color)
			local look = `{slimeNeed.id}:{slimeNeed.owned}`
			if slimeView:GetAttribute("Look") ~= look then
				local opts = { locked = not slimeNeed.owned }
				local ok = false
				if ctx.buildSlime then
					local genome = {
						id = `Rebirth_{slimeNeed.id}`,
						name = slimeNeed.name,
						tier = slimeNeed.tier,
						color = slimeNeed.color,
						size = 1,
						pattern = "Plain",
						eyes = "Round",
						mouth = "Smile",
						mutation = "None",
						species = slimeNeed.id,
					}
					local built, model = pcall(ctx.buildSlime, genome)
					ok = built and model ~= nil and SlimePreview.mountModel(slimeView, model, opts)
				end
				if not ok then
					ok = SlimePreview.mount(slimeView, slimeNeed.color, opts)
				end
				slimeView:SetAttribute("Look", look)
				slimeView.Visible = ok
			end
			slimeGlyph.Visible = not slimeNeed.owned and not slimeView.Visible
		end

		local reason = if nextUp.ready
			then "♻️ Rebirth!"
			elseif
				nextUp.slimeMissing and nextUp.have >= nextUp.cost
			then `♻️ Need {slimeNeed and slimeNeed.name or "a slime"}`
			else `♻️ Need {nextUp.need}`
		btn.setText(reason)
		btn.setEnabled(nextUp.ready)
	end

	return self
end

return Rebirth
