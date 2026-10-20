--!strict
--[[
	DexJarView

	The SlimeDex nav tile as a jar of slime: green goo fills the tile from a floor puddle up to the dex
	completion (DexJarView.progress), a light rim marks its surface and the percent sits on the goo. When the
	percent rises the goo sloshes up to its new level (no tween with Reduced Motion). Built by init.client
	inside the Dex tile; the goo draws under the tile's icon, the percent over it (Layout.NAV_TILE_Z,
	tests/ui/DexJarView.spec.luau).

	The goo is a tile-sized rounded frame (scale 1 / level of the clip) inside a rectangular clip that grows
	from the bottom, so its bottom corners always follow the tile's and its surface stays flat. The rim is a
	square bar, so it only shows while the surface is clear of the tile's rounded corners, top and bottom;
	it follows the clip's real height (its Size changes every frame of a slosh), so no timer or frame loop.
]]

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Layout = if script then require(script.Parent.Layout) else require("./Layout")
local SlimeDex = if script then require(script.Parent.SlimeDex) else require("./SlimeDex")
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
	overshoot = 0.1, -- Back easing peaks this share of the rise past its target
})
DexJarView.JAR = JAR

-- Goo height (tile fraction) for a completion `fraction` (0..1): the puddle at 0, the full tile at 1.
function DexJarView.level(fraction: number): number
	local f = if type(fraction) == "number" and fraction == fraction then math.clamp(fraction, 0, 1) else 0
	return JAR.puddle + (1 - JAR.puddle) * f
end

-- Highest level whose rim stays under the tile's rounded top corners.
function DexJarView.rimTop(tileH: number, radius: number): number
	return if tileH > 0 then 1 - radius / tileH else 1
end

-- Lowest level whose rim (hanging JAR.rim under the surface) stays above the tile's rounded bottom corners.
function DexJarView.rimBottom(tileH: number, radius: number): number
	return if tileH > 0 then (radius + JAR.rim) / tileH else 0
end

function DexJarView.rimShown(level: number, tileH: number, radius: number): boolean
	return level >= DexJarView.rimBottom(tileH, radius) and level <= DexJarView.rimTop(tileH, radius)
end

-- A rise from `from` to `to` may bounce (Back) only if its overshoot peak stays under the top corners, so
-- the rim does not flicker off and on; otherwise it eases in (Quad) without passing its target.
function DexJarView.bounces(from: number, to: number, tileH: number, radius: number): boolean
	return to + JAR.overshoot * (to - from) <= DexJarView.rimTop(tileH, radius)
end

export type Progress = { fraction: number, text: string }

-- SlimeDex completion for the jar, the same percent as the panel (SlimeDex.summary); nil until State has a dex.
function DexJarView.progress(state: any): Progress?
	local dex = if type(state) == "table" and type(state.dex) == "table" then state.dex else nil
	if dex == nil or type(dex.total) ~= "number" or dex.total <= 0 then
		return nil
	end
	local summary = SlimeDex.summary(dex)
	return { fraction = summary.fraction, text = summary.percent }
end

export type View = {
	update: (progress: Progress?) -> (),
	setSelected: (selected: boolean) -> (),
	-- Re-checks the rim after the layout resized the tile.
	relayout: () -> (),
	level: () -> number,
}

-- Roblox's own Reduced Motion setting; init.client also passes the game's (DexJarView.new `reducedMotion`).
local function systemReducedMotion(): boolean
	return (GuiService :: any).ReducedMotionEnabled == true
end

function DexJarView.new(tile: Frame, reducedMotion: (() -> boolean)?): View
	local calm = reducedMotion or systemReducedMotion
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

	-- The rim at the clip's real height (mid-slosh too), so it shows only clear of the tile's corners.
	local function syncRim()
		rim.Visible = DexJarView.rimShown(clip.Size.Y.Scale, tile.Size.Y.Offset, radius.Offset)
	end
	clip:GetPropertyChangedSignal("Size"):Connect(syncRim)

	local function stopSlosh()
		if tween then
			tween:Cancel() -- else a slosh still running would overwrite a later level
			tween = nil
		end
	end

	local function setLevel(level: number)
		if level == current then
			return
		end
		local from = current
		current = level
		stopSlosh()
		-- Tile-sized at the target level; while the clip is still rising the goo is taller than it, never shorter.
		goo.Size = UDim2.fromScale(1, 1 / level)
		local size = UDim2.fromScale(1, level)
		if from == nil or level < from or calm() then
			clip.Size = size
			syncRim()
			return
		end
		local style = if DexJarView.bounces(from, level, tile.Size.Y.Offset, radius.Offset)
			then Enum.EasingStyle.Back
			else Enum.EasingStyle.Quad
		tween = TweenService:Create(clip, TweenInfo.new(JAR.slosh, style, Enum.EasingDirection.Out), { Size = size })
		tween:Play()
	end

	return {
		update = function(progress: Progress?)
			clip.Visible = progress ~= nil
			text.Visible = progress ~= nil
			if progress then
				text.Text = progress.text
				setLevel(DexJarView.level(progress.fraction))
			elseif tween then
				-- Hidden mid-slosh: land on the level now, so showing it again needs no slosh to finish.
				stopSlosh()
				clip.Size = UDim2.fromScale(1, current or DexJarView.level(0))
				syncRim()
			end
		end,
		relayout = syncRim,
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
