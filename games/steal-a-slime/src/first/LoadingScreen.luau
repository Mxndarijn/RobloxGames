--!strict
--[[
	LoadingScreen

	Draws the join loading screen (canvas GooLoading / GooLoadingSkip) from LoadingLook: a deep teal backdrop,
	mint goo dripping from the top edge, the title in mint with an Ink outline and shadow, a goo tube progress
	bar with a slime hopping along its tip, the tip line and a secondary Skip button (glass with a mint line,
	hidden until LoadingGate allows a skip). The Loading script only wires it to LoadingGate. Nothing is made
	until `build` is called.

	`animate(t, motion)` moves it: drips sway, drops fall, bubbles rise, a shine runs along the bar and the slime
	hops. With motion off (Roblox's Reduced Motion) everything rests; only the bar and the slime's place move.

	The goo is sized from the screen's height (gooHeight), so on a short phone screen the drips still stop above
	the title: `layout(height)` resizes it, and the Loading script calls it every tick.
]]

local LOOK = require(script.Parent:WaitForChild("LoadingLook"))

local LoadingScreen = {}

LoadingScreen.FADE = LOOK.fade -- seconds the fade-out takes

export type Screen = {
	gui: ScreenGui,
	skip: TextButton,
	setProgress: (number) -> (),
	setStatus: (string) -> (),
	setSkip: (boolean) -> (),
	layout: (number) -> (),
	animate: (number, boolean) -> (),
	fade: (TweenService) -> (),
}

-- Top edge of the title, px from the top of a `height` px screen (its label is centred on titleY).
function LoadingScreen.titleTop(height: number): number
	return height / 2 + LOOK.titleY - (LOOK.titleSize + 8) / 2
end

-- Height of the goo layer (band and drips) on a `height` px screen: gooShare of it, but always ending gooGap
-- above the title.
function LoadingScreen.gooHeight(height: number): number
	return math.max(0, math.floor(math.min(height * LOOK.gooShare, LoadingScreen.titleTop(height) - LOOK.gooGap)))
end

-- Lowest point of any drip as a fraction of the goo layer's height, at the longest point of its sway.
function LoadingScreen.dripBottom(): number
	local bottom = LOOK.gooBand
	for _, d in LOOK.drips do
		bottom = math.max(bottom, LOOK.gooBand + d.hang * (1 + LOOK.sway))
	end
	return bottom
end

-- Bottom edge of the title's shadow, px from the screen's centre.
function LoadingScreen.titleBottom(): number
	return LOOK.titleY + LOOK.titleDrop + (LOOK.titleSize + 8) / 2
end

-- Highest point the bar's slime reaches (top of its hop, stretched), px from the screen's centre.
function LoadingScreen.riderTop(): number
	local barTop = LOOK.barY - LOOK.barSize.Y.Offset / 2
	return barTop - LOOK.riderLift - LOOK.riderSize.Y * (1 + LOOK.riderSquash) - LOOK.riderHop
end

-- How long drip `i` is at time `t`, as a share of its hang (1 is its resting length).
function LoadingScreen.swayAt(i: number, t: number): number
	local period = LOOK.swayPeriods[(i - 1) % #LOOK.swayPeriods + 1]
	return 1 + LOOK.sway * math.sin(2 * math.pi * t / period)
end

-- The slime's hop at time `t`: px above the bar, then its width and height scale (flat when it lands,
-- stretched at the top).
function LoadingScreen.hopAt(t: number): (number, number, number)
	local up = math.sin(math.pi * ((t % LOOK.riderPeriod) / LOOK.riderPeriod)) -- 0 on the bar, 1 at the top
	local squash = LOOK.riderSquash * (1 - 2 * up)
	return LOOK.riderHop * up, 1 + squash, 1 - squash
end

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

local function pill(parent: Instance)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, parent)
end

local function outline(parent: Instance, color: Color3, thickness: number, transparency: number?, text: boolean?)
	make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = if text then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, parent)
end

local function centred(name: string, y: number, size: UDim2, parent: Instance): any
	return make("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, y),
		Size = size,
		BorderSizePixel = 0,
	}, parent)
end

local function title(name: string, color: Color3, y: number, parent: Instance): TextLabel
	local label = make("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, y),
		Size = UDim2.fromOffset(640, LOOK.titleSize + 8),
		BackgroundTransparency = 1,
		Font = LOOK.font,
		Text = "Steal a Slime",
		TextSize = LOOK.titleSize,
		TextColor3 = color,
	}, parent)
	outline(label, LOOK.ink, LOOK.titleStroke, 0, true)
	return label
end

-- The goo along the top edge: a full-width band, then drips, each one finger of goo with a round end.
local function goo(parent: Instance): (Frame, { Frame })
	local frames: { Frame } = {}
	local layer = make("Frame", {
		Name = "Goo",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
	}, parent)
	make("Frame", {
		Name = "Band",
		BackgroundColor3 = LOOK.band,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, LOOK.gooBand),
	}, layer)
	for i, d in LOOK.drips do
		-- Sizes are fractions of the layer's height (SizeConstraint RelativeYY), x is a fraction of the width. The
		-- finger's round top hides in the band.
		local drip = make("Frame", {
			Name = `Drip{i}`,
			BackgroundColor3 = LOOK.band,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Position = UDim2.fromScale(d.x, LOOK.gooBand - d.w),
			Size = UDim2.fromScale(d.w, d.hang + d.w),
		}, layer)
		pill(drip)
		table.insert(frames, drip)
	end
	return layer, frames
end

-- The slime riding the bar: an Ink-outlined gold jelly blob with two eyes and a highlight, standing on the bar. The
-- holder follows the fill's tip; the body inside it hops.
local function rider(bar: Frame): (Frame, Frame)
	local holder = make("Frame", {
		Name = "Rider",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(0, -LOOK.riderLift),
		Size = UDim2.fromOffset(LOOK.riderSize.X, LOOK.riderSize.Y),
	}, bar)
	local body = make("Frame", {
		Name = "Slime",
		BackgroundColor3 = LOOK.slime,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 1),
	}, holder)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, body)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, LOOK.slimeHi),
			ColorSequenceKeypoint.new(0.45, LOOK.slime),
			ColorSequenceKeypoint.new(1, LOOK.slimeLo),
		}),
	}, body)
	outline(body, LOOK.ink, LOOK.stroke)
	for i, x in { 0.36, 0.64 } do
		local eye = make("Frame", {
			Name = `Eye{i}`,
			BackgroundColor3 = LOOK.ink,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.45),
			Size = UDim2.fromScale(0.14, 0.26),
		}, body)
		pill(eye)
	end
	local highlight = make("Frame", {
		Name = "Highlight",
		BackgroundColor3 = LOOK.white,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.24, 0.26),
		Size = UDim2.fromScale(0.16, 0.14),
	}, body)
	pill(highlight)
	return holder, body
end

-- Builds the screen, unparented (the Loading script parents it to PlayerGui).
function LoadingScreen.build(): Screen
	local gui = make("ScreenGui", {
		Name = "LoadingScreen",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = LOOK.displayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local bg = make("Frame", {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, gui)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(LOOK.bg, LOOK.bgBottom) }, bg)
	local screenHeight = 720
	local bubbles: { Frame } = {}
	for i, b in LOOK.bubbles do
		local bubble = make("Frame", {
			Name = `Bubble{i}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(b[1], b[2]),
			Size = UDim2.fromOffset(b[3], b[3]),
			BackgroundColor3 = LOOK.band,
			BackgroundTransparency = LOOK.bubbleTransparency,
			BorderSizePixel = 0,
		}, bg)
		pill(bubble)
		table.insert(bubbles, bubble)
	end
	local layer, drips = goo(bg)
	-- Falling drops: over the goo, under the title and the bar.
	local drops: { Frame } = {}
	for i, d in LOOK.drops do
		local drop = make("Frame", {
			Name = `Drop{i}`,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(LOOK.drips[d.drip].x, 0),
			Size = UDim2.fromOffset(LOOK.dropSize, LOOK.dropSize),
			BackgroundColor3 = LOOK.band,
			BorderSizePixel = 0,
			Visible = false,
		}, bg)
		pill(drop)
		table.insert(drops, drop)
	end

	title("TitleShadow", LOOK.ink, LOOK.titleY + LOOK.titleDrop, bg)
	title("Title", LOOK.band, LOOK.titleY, bg)

	local bar = centred("Bar", LOOK.barY, LOOK.barSize, bg)
	bar.BackgroundColor3 = LOOK.ink
	pill(bar)
	outline(bar, LOOK.band, LOOK.stroke, LOOK.barRing)
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Visible = false,
	}, bar)
	pill(fill)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, LOOK.bandHi),
			ColorSequenceKeypoint.new(0.45, LOOK.band),
			ColorSequenceKeypoint.new(1, LOOK.bandLo),
		}),
	}, fill)
	-- The shine: a pill over the whole fill, clear but for one bright band that slides along by Offset.
	local shine = make("Frame", {
		Name = "Shine",
		BackgroundColor3 = LOOK.white,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
	}, fill)
	pill(shine)
	local shineGradient = make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, LOOK.shineTransparency),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, shine)
	local riderHolder, riderBody = rider(bar)

	local status = make("TextLabel", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, LOOK.statusY),
		Size = UDim2.fromOffset(600, LOOK.labelSize + 8),
		BackgroundTransparency = 1,
		FontFace = LOOK.fontBody,
		Text = "",
		TextSize = LOOK.labelSize,
		TextColor3 = LOOK.muted,
	}, bg)

	-- Secondary button: glass with an Ink outline, a mint line inside it (a second frame: one UIStroke each).
	local skip = make("TextButton", {
		Name = "Skip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, LOOK.skipY),
		Size = LOOK.skipSize,
		BackgroundColor3 = LOOK.glass,
		BackgroundTransparency = LOOK.skipGlass,
		AutoButtonColor = true,
		Font = LOOK.font,
		Text = "Skip", -- the Loading script swaps in the player's language (LoadingGate.SKIP_KEY)
		TextSize = LOOK.labelSize,
		TextColor3 = LOOK.band,
		Visible = false,
	}, bg)
	pill(skip)
	outline(skip, LOOK.ink, LOOK.stroke)
	local line = make("Frame", {
		Name = "Line",
		Active = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
	}, skip)
	pill(line)
	outline(line, LOOK.band, 2, 0.45)

	local self = {} :: Screen
	self.gui = gui
	self.skip = skip
	function self.setProgress(p: number)
		local a = math.clamp(p, 0, 1)
		fill.Size = UDim2.fromScale(a, 1)
		fill.Visible = a > 0
		riderHolder.Position = UDim2.new(a, 0, 0, -LOOK.riderLift)
	end
	function self.setStatus(text: string)
		status.Text = text
	end
	function self.setSkip(visible: boolean)
		skip.Visible = visible
	end
	function self.layout(height: number)
		screenHeight = height
		layer.Size = UDim2.new(1, 0, 0, LoadingScreen.gooHeight(height))
	end
	function self.animate(t: number, motion: boolean)
		local time = if motion then t else 0
		for i, drip in drips do
			local d = LOOK.drips[i]
			drip.Size = UDim2.fromScale(d.w, d.hang * LoadingScreen.swayAt(i, time) + d.w)
		end
		local gooPx = LoadingScreen.gooHeight(screenHeight)
		for i, drop in drops do
			local d = LOOK.drops[i]
			local phase = ((t + d.delay) % d.every) / d.every
			local fall = (phase - (1 - LOOK.dropFall)) / LOOK.dropFall -- 0 to 1 while it falls
			drop.Visible = motion and fall >= 0
			if drop.Visible then
				local from = gooPx * (LOOK.gooBand + LOOK.drips[d.drip].hang) - LOOK.dropSize
				drop.Position =
					UDim2.new(LOOK.drips[d.drip].x, 0, 0, math.round(from + (screenHeight - from) * fall * fall))
			end
		end
		for i, bubble in bubbles do
			local b = LOOK.bubbles[i]
			local phase = if motion then (t / (LOOK.bubblePeriod + (i - 1) * 1.3) + i * 0.37) % 1 else 0.5
			bubble.Position = UDim2.fromScale(b[1], b[2] - LOOK.bubbleRise * (phase - 0.5))
			bubble.BackgroundTransparency = 1 - (1 - LOOK.bubbleTransparency) * math.sin(math.pi * phase)
		end
		shine.Visible = motion
		shineGradient.Offset = Vector2.new(((t / LOOK.shinePeriod) % 1) * 2 - 1, 0)
		local lift, sx, sy = LoadingScreen.hopAt(time)
		riderBody.Position = UDim2.new(0.5, 0, 1, -math.round(lift))
		riderBody.Size = UDim2.fromScale(sx, sy)
	end
	-- Fades every part out together (text, fills and outlines) over LOOK.fade seconds.
	function self.fade(tweens: TweenService)
		local info = TweenInfo.new(LOOK.fade)
		for _, d in gui:GetDescendants() do
			local goal: { [string]: number }? = nil
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				goal = { TextTransparency = 1, BackgroundTransparency = 1 }
			elseif d:IsA("Frame") then
				goal = { BackgroundTransparency = 1 }
			elseif d:IsA("UIStroke") then
				goal = { Transparency = 1 }
			end
			if goal then
				tweens:Create(d, info, goal):Play()
			end
		end
	end
	return self
end

return LoadingScreen
