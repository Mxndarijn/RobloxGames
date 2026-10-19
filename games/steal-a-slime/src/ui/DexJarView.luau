--!strict
--[[
	DexJarView

	The SlimeDex nav tile as a jar of slime: green goo fills the tile from a floor puddle up to the dex
	completion (Nav.dexProgress), a light rim marks its surface and the percent sits on the goo. When the
	percent rises the goo sloshes up to its new level (no tween with Reduced Motion). Built by init.client
	inside the Dex tile; the goo draws under the tile's icon, the percent over it (tests/ui/DexJarView.spec.luau).
]]

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Widgets = if script then require(script.Parent.Widgets) else require("./Widgets")

local Theme = Widgets.Theme
local create = Widgets.create

local DexJarView = {}

-- Goo heights are tile fractions, the rest design px.
local JAR = table.freeze({
	puddle = 0.12, -- goo height at 0%
	goo = 0.25, -- goo transparency: the tile's purple tints it a deeper green
	rim = 3, -- surface highlight
	rimTransparency = 0.35,
	textSize = 18,
	textH = 20,
	textBottom = 3, -- percent baseline box above the tile's bottom edge
	slosh = 0.5, -- seconds for the goo to rise
	gooZ = 0, -- under the tile's icon (ZIndex 1)
	textZ = 2, -- over it
})
DexJarView.JAR = JAR

-- Goo height (tile fraction) for a completion `fraction` (0..1): the puddle at 0, the full tile at 1.
function DexJarView.level(fraction: number): number
	local f = if type(fraction) == "number" and fraction == fraction then math.clamp(fraction, 0, 1) else 0
	return JAR.puddle + (1 - JAR.puddle) * f
end

export type Progress = { fraction: number, text: string }
export type View = { update: (progress: Progress?) -> (), level: () -> number }

function DexJarView.new(tile: Frame): View
	-- Rounded like the tile, so the goo stays inside its corners.
	local corner = tile:FindFirstChildOfClass("UICorner")
	local jar = create("CanvasGroup", {
		Name = "DexJar",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = JAR.gooZ,
		Visible = false,
		Parent = tile,
	}, { create("UICorner", { CornerRadius = if corner then corner.CornerRadius else UDim.new() }) })
	local goo = create("Frame", {
		Name = "Goo",
		BackgroundColor3 = Theme.Good,
		BackgroundTransparency = JAR.goo,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, DexJarView.level(0)),
		Parent = jar,
	})
	create("Frame", {
		Name = "Rim",
		BackgroundColor3 = Theme.Text,
		BackgroundTransparency = JAR.rimTransparency,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, JAR.rim),
		Parent = goo,
	})
	local text = Widgets.label({
		Name = "Percent",
		Text = "",
		Visible = false,
		Font = Theme.Font,
		TextSize = JAR.textSize,
		TextColor3 = Theme.Text,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -JAR.textBottom),
		Size = UDim2.new(1, 0, 0, JAR.textH),
		ZIndex = JAR.textZ,
		Parent = tile,
	})

	local current: number? = nil

	local function setLevel(level: number)
		if level == current then
			return
		end
		local rising = current ~= nil and level > current
		current = level
		local size = UDim2.fromScale(1, level)
		if rising and not (GuiService :: any).ReducedMotionEnabled then
			-- A newer tween on Size replaces one still running.
			TweenService:Create(goo, TweenInfo.new(JAR.slosh, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = size,
			}):Play()
		else
			goo.Size = size
		end
	end

	return {
		update = function(progress: Progress?)
			jar.Visible = progress ~= nil
			text.Visible = progress ~= nil
			if progress then
				text.Text = progress.text
				setLevel(DexJarView.level(progress.fraction))
			end
		end,
		-- The goo's target height (tile fraction); the tween may still be on its way there.
		level = function(): number
			return current or DexJarView.level(0)
		end,
	}
end

return table.freeze(DexJarView)
