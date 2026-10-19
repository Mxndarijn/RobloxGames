--!strict
--[[
	DexJarView

	The SlimeDex nav tile as a jar of slime: green goo fills the tile from a floor puddle up to the dex
	completion (Nav.dexProgress), a light rim marks its surface and the percent sits on the goo. When the
	percent rises the goo sloshes up to its new level (no tween with Reduced Motion). Built by init.client
	inside the Dex tile; the goo draws under the tile's icon, the percent over it (Layout.NAV_TILE_Z,
	tests/ui/DexJarView.spec.luau).

	The goo is a tile-sized rounded frame (scale 1 / level of the clip) inside a rectangular clip that grows
	from the bottom, so its bottom corners always follow the tile's and its surface stays flat.
]]

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Layout = if script then require(script.Parent.Layout) else require("./Layout")
local Widgets = if script then require(script.Parent.Widgets) else require("./Widgets")

local Theme = Widgets.Theme
local create = Widgets.create

local DexJarView = {}

-- Goo heights are tile fractions, the rest design px.
local JAR = table.freeze({
	puddle = 0.12, -- goo height at 0%
	goo = 0.25, -- goo transparency: the tile's purple tints it a deeper green
	selectedGoo = 0.45, -- on the selected (Accent green) tile the goo is Ink, a darker slime
	rim = 3, -- surface highlight
	rimTransparency = 0.35,
	textSize = 18,
	textH = 20,
	textBottom = 3, -- percent box above the tile's bottom edge
	slosh = 0.5, -- seconds for the goo to rise
	sloshTop = 0.85, -- above this level the rise eases without the Back overshoot, which would leave the tile
})
DexJarView.JAR = JAR

-- Goo height (tile fraction) for a completion `fraction` (0..1): the puddle at 0, the full tile at 1.
function DexJarView.level(fraction: number): number
	local f = if type(fraction) == "number" and fraction == fraction then math.clamp(fraction, 0, 1) else 0
	return JAR.puddle + (1 - JAR.puddle) * f
end

-- The rim would cross the tile's rounded top corners above this level, so it hides there.
function DexJarView.rimShown(level: number, tileH: number, radius: number): boolean
	return tileH <= 0 or level <= 1 - radius / tileH
end

export type Progress = { fraction: number, text: string }
export type View = {
	update: (progress: Progress?) -> (),
	setSelected: (selected: boolean) -> (),
	level: () -> number,
}

function DexJarView.new(tile: Frame): View
	local corner = tile:FindFirstChildOfClass("UICorner")
	local radius = if corner then corner.CornerRadius else UDim.new()
	local clip = create("Frame", {
		Name = "DexJar",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, DexJarView.level(0)),
		ZIndex = Layout.NAV_TILE_Z.goo,
		Visible = false,
		Parent = tile,
	})
	local goo = create("Frame", {
		Name = "Goo",
		BackgroundColor3 = Theme.Good,
		BackgroundTransparency = JAR.goo,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1 / DexJarView.level(0)),
		Parent = clip,
	}, { create("UICorner", { CornerRadius = radius }) })
	local rim = create("Frame", {
		Name = "Rim",
		BackgroundColor3 = Theme.Text,
		BackgroundTransparency = JAR.rimTransparency,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, JAR.rim),
		Parent = clip,
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
		ZIndex = Layout.NAV_TILE_Z.text,
		Parent = tile,
	})

	local current: number? = nil
	local tween: any = nil

	local function setLevel(level: number)
		if level == current then
			return
		end
		local rising = current ~= nil and level > current
		current = level
		if tween then
			tween:Cancel() -- else a slosh still running would overwrite a later level
			tween = nil
		end
		-- Tile-sized at the target level; while the clip is still rising the goo is taller than it, never shorter.
		goo.Size = UDim2.fromScale(1, 1 / level)
		rim.Visible = DexJarView.rimShown(level, tile.Size.Y.Offset, radius.Offset)
		local size = UDim2.fromScale(1, level)
		if rising and not (GuiService :: any).ReducedMotionEnabled then
			local style = if level <= JAR.sloshTop then Enum.EasingStyle.Back else Enum.EasingStyle.Quad
			tween = TweenService:Create(clip, TweenInfo.new(JAR.slosh, style, Enum.EasingDirection.Out), {
				Size = size,
			})
			tween:Play()
		else
			clip.Size = size
		end
	end

	return {
		update = function(progress: Progress?)
			clip.Visible = progress ~= nil
			text.Visible = progress ~= nil
			if progress then
				text.Text = progress.text
				setLevel(DexJarView.level(progress.fraction))
			end
		end,
		setSelected = function(selected: boolean)
			goo.BackgroundColor3 = if selected then Theme.Ink else Theme.Good
			goo.BackgroundTransparency = if selected then JAR.selectedGoo else JAR.goo
		end,
		-- The goo's target height (tile fraction); the tween may still be on its way there.
		level = function(): number
			return current or DexJarView.level(0)
		end,
	}
end

return table.freeze(DexJarView)
