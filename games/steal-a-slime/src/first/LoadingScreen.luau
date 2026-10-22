--!strict
--[[
	LoadingScreen

	Draws the join loading screen (canvas GooLoading / GooLoadingSkip) from LoadingLook: a deep teal backdrop,
	mint goo dripping from the top edge, the title in mint with an Ink outline and shadow, a goo tube progress
	bar, the status line and a secondary Skip button (glass with a mint line, hidden until LoadingGate allows a
	skip). The Loading script only wires it to LoadingGate. Nothing is made until `build` is called.

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

-- Lowest point of any drip as a fraction of the goo layer's height.
function LoadingScreen.dripBottom(): number
	local bottom = LOOK.gooBand
	for _, d in LOOK.drips do
		bottom = math.max(bottom, LOOK.gooBand + d.len - d.w * 0.3 + d.w * 1.15)
	end
	return bottom
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

-- The goo along the top edge: a full-width band, then drips of a neck and a round drop with a dot of shine.
local function goo(parent: Instance): Frame
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
		-- Sizes are fractions of the layer's height (SizeConstraint RelativeYY), x is a fraction of the width.
		local neck = make("Frame", {
			Name = `Neck{i}`,
			BackgroundColor3 = LOOK.band,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Position = UDim2.fromScale(d.x, LOOK.gooBand - 0.05),
			Size = UDim2.fromScale(d.w * 0.64, d.len + 0.05),
		}, layer)
		pill(neck)
		local drop = make("Frame", {
			Name = `Drop{i}`,
			BackgroundColor3 = LOOK.band,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Position = UDim2.fromScale(d.x, LOOK.gooBand + d.len - d.w * 0.3),
			Size = UDim2.fromScale(d.w, d.w * 1.15),
		}, layer)
		pill(drop)
		local dot = make("Frame", {
			Name = "Dot",
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.26, 0.2),
			Size = UDim2.fromScale(0.26, 0.24),
		}, drop)
		pill(dot)
	end
	return layer
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
	end
	local layer = goo(bg)

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
		Text = "Skip",
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
	end
	function self.setStatus(text: string)
		status.Text = text
	end
	function self.setSkip(visible: boolean)
		skip.Visible = visible
	end
	function self.layout(height: number)
		layer.Size = UDim2.new(1, 0, 0, LoadingScreen.gooHeight(height))
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
