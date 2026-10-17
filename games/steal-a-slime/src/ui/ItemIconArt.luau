--!strict
--[[
	ItemIconArt

	UI-drawn item icons: small scenes of layered rounded frames (+ UIGradient /
	UIStroke / UICorner and allowlisted glyphs), no meshes and no images. Used
	for every item whose spec has source "drawn" (ItemIcons.DRAWN lists the
	ids). All geometry is in 0..1 of the icon square, so one recipe is crisp
	from 36 px rows to big popups. ItemIconView builds the recipe into an "Art"
	frame above the tile; static, so it never counts against the live-viewport cap.

	ItemIconArt.RECIPES[id](pen) draws with pen:shape / pen:text; shapes stack
	in call order.
]]

local Widgets = require(script.Parent.Widgets)

local create = Widgets.create

local ItemIconArt = {}

type Color = Color3
export type Opts = {
	round: number?, -- corner radius as a fraction of the shorter side (0.5 = pill / circle)
	rot: number?,
	stroke: boolean?, -- thin darker outline (default true)
	flat: boolean?, -- no top-light gradient
	alpha: number?,
}
export type Pen = {
	shape: (Pen, number, number, number, number, Color, Opts?) -> Frame,
	circle: (Pen, number, number, number, Color, Opts?) -> Frame,
	text: (Pen, string, number, number, number, Color?) -> TextLabel,
	clip: (Pen, number, number, number, number) -> Pen, -- pen for a child viewport; ClipsDescendants
}

local function rgb(r: number, g: number, b: number): Color
	return Color3.fromRGB(r, g, b)
end
local WHITE, INK = rgb(255, 255, 255), rgb(30, 30, 50)
local GOLD, GOLD_D = rgb(255, 204, 60), rgb(200, 140, 20)
local GREEN, RED, BLUE = rgb(110, 210, 90), rgb(225, 70, 70), rgb(90, 160, 240)
local PURPLE, SILVER, CREAM = rgb(170, 100, 220), rgb(200, 205, 220), rgb(255, 244, 214)

local function newPen(parent: Instance, z0: number): Pen
	local z = z0
	local pen = {} :: any
	function pen.shape(_: Pen, cx: number, cy: number, w: number, h: number, color: Color, o: Opts?): Frame
		local opts = o or {}
		z += 1
		local f = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(cx, cy),
			Size = UDim2.fromScale(w, h),
			BackgroundColor3 = color,
			BackgroundTransparency = opts.alpha or 0,
			BorderSizePixel = 0,
			Rotation = opts.rot or 0,
			ZIndex = z,
			Parent = parent,
		}, { Widgets.corner(1) })
		local corner = f:FindFirstChildOfClass("UICorner") :: UICorner
		corner.CornerRadius = UDim.new(opts.round or 0.2, 0)
		if opts.stroke ~= false then
			Widgets.stroke(color:Lerp(INK, 0.55), 1).Parent = f
		end
		if not opts.flat then
			create("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(color:Lerp(WHITE, 0.3), color:Lerp(INK, 0.12)),
				Parent = f,
			})
		end
		return f
	end
	function pen.circle(self: Pen, cx: number, cy: number, d: number, color: Color, o: Opts?): Frame
		local opts = table.clone(o or {})
		opts.round = 0.5
		return self:shape(cx, cy, d, d, color, opts)
	end
	function pen.text(_: Pen, text: string, cx: number, cy: number, size: number, color: Color?): TextLabel
		z += 1
		return create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(cx, cy),
			Size = UDim2.fromScale(size, size),
			BackgroundTransparency = 1,
			Font = Widgets.Theme.Font,
			Text = text,
			TextScaled = true,
			TextColor3 = color or WHITE,
			TextStrokeColor3 = INK,
			TextStrokeTransparency = 0.45,
			ZIndex = z,
			Parent = parent,
		})
	end
	function pen.clip(_: Pen, cx: number, cy: number, w: number, h: number): Pen
		z += 1
		local holder = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(cx, cy),
			Size = UDim2.fromScale(w, h),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = z,
			Parent = parent,
		})
		-- Children are positioned in the holder's own 0..1 space.
		return newPen(holder, z)
	end
	return pen :: Pen
end

local function blob(p: Pen, cx: number, cy: number, s: number, color: Color)
	p:shape(cx, cy, s, s * 0.82, color, { round = 0.42 })
	p:circle(cx - s * 0.18, cy - s * 0.04, s * 0.14, WHITE, { stroke = false, flat = true })
	p:circle(cx + s * 0.18, cy - s * 0.04, s * 0.14, WHITE, { stroke = false, flat = true })
	p:circle(cx - s * 0.16, cy - s * 0.03, s * 0.07, INK, { stroke = false, flat = true })
	p:circle(cx + s * 0.2, cy - s * 0.03, s * 0.07, INK, { stroke = false, flat = true })
end

local function padlock(p: Pen, cx: number, cy: number, s: number, plate: Color)
	p:shape(cx, cy - s * 0.3, s * 0.62, s * 0.7, SILVER, { round = 0.5 })
	p:shape(cx, cy - s * 0.26, s * 0.34, s * 0.5, INK:Lerp(plate, 0.35), { round = 0.5, stroke = false, flat = true })
	p:shape(cx, cy + s * 0.14, s * 0.84, s * 0.6, GOLD, { round = 0.2 })
	p:shape(cx, cy + s * 0.14, s * 0.62, s * 0.4, plate, { round = 0.2 })
	p:circle(cx, cy + s * 0.08, s * 0.14, INK, { stroke = false, flat = true })
	p:shape(cx, cy + s * 0.2, s * 0.07, s * 0.16, INK, { round = 0.3, stroke = false, flat = true })
end

local function clover(p: Pen, cx: number, cy: number, s: number, leaf: Color)
	p:shape(cx + s * 0.04, cy + s * 0.34, s * 0.07, s * 0.36, leaf:Lerp(INK, 0.35), { rot = 18, round = 0.4 })
	for _, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		p:circle(cx + d[1] * s * 0.19, cy + d[2] * s * 0.19, s * 0.4, leaf)
	end
end

local function cloud(p: Pen, cx: number, cy: number, s: number, color: Color)
	p:circle(cx - s * 0.22, cy + s * 0.02, s * 0.36, color)
	p:circle(cx + s * 0.04, cy - s * 0.1, s * 0.46, color)
	p:circle(cx + s * 0.27, cy + s * 0.04, s * 0.34, color)
	p:shape(cx + s * 0.02, cy + s * 0.12, s * 0.74, s * 0.26, color, { round = 0.5, stroke = false })
end

local function bottle(p: Pen, liquid: Color)
	p:shape(0.5, 0.3, 0.22, 0.26, rgb(200, 235, 250), { round = 0.25 })
	p:shape(0.5, 0.17, 0.18, 0.12, rgb(170, 110, 60), { round = 0.3 })
	p:circle(0.5, 0.64, 0.64, rgb(200, 235, 250))
	p:circle(0.5, 0.67, 0.5, liquid, { stroke = false })
	p:text("⚡", 0.5, 0.66, 0.34, WHITE)
end

local function coinPile(p: Pen)
	p:shape(0.5, 0.78, 0.66, 0.2, GOLD_D, { round = 0.5 })
	p:shape(0.5, 0.64, 0.66, 0.2, GOLD, { round = 0.5 })
	p:shape(0.5, 0.5, 0.66, 0.2, GOLD_D, { round = 0.5 })
	p:shape(0.5, 0.36, 0.66, 0.22, GOLD, { round = 0.5 })
	p:text("$", 0.5, 0.36, 0.26, rgb(150, 95, 10))
	p:circle(0.78, 0.2, 0.12, rgb(255, 235, 140), { flat = true, stroke = false })
end

local function sparkle(p: Pen, cx: number, cy: number, s: number)
	p:text("✨", cx, cy, s)
end

local RECIPES: { [string]: (Pen) -> () } = {}

RECIPES.Lock = function(p)
	padlock(p, 0.5, 0.5, 0.9, BLUE)
end

RECIPES.LockUpgrade = function(p)
	padlock(p, 0.4, 0.55, 0.74, rgb(60, 180, 190))
	p:circle(0.72, 0.3, 0.38, WHITE)
	p:circle(0.72, 0.3, 0.28, rgb(60, 180, 190), { stroke = false, flat = true })
	p:shape(0.72, 0.25, 0.05, 0.12, WHITE, { stroke = false, flat = true })
	p:shape(0.76, 0.3, 0.1, 0.05, WHITE, { stroke = false, flat = true })
	p:text("⬆️", 0.74, 0.74, 0.3, GREEN)
end

RECIPES.SpeedCoil = function(p)
	for i = 0, 4 do
		p:shape(
			0.5,
			0.2 + i * 0.15,
			0.56,
			0.11,
			i % 2 == 0 and GOLD or rgb(240, 175, 40),
			{ round = 0.5, rot = i % 2 == 0 and -7 or 7 }
		)
	end
	p:shape(0.5, 0.88, 0.5, 0.06, INK, { round = 0.5, alpha = 0.55, stroke = false, flat = true })
	p:text("⚡", 0.5, 0.5, 0.52, rgb(255, 255, 190))
end

RECIPES.MysteryEgg = function(p)
	p:circle(0.5, 0.6, 0.66, CREAM)
	p:circle(0.5, 0.36, 0.5, CREAM, { stroke = false })
	p:circle(0.5, 0.42, 0.2, CREAM, { stroke = false, flat = true })
	p:circle(0.3, 0.62, 0.12, PURPLE, { stroke = false })
	p:circle(0.7, 0.7, 0.14, PURPLE, { stroke = false })
	p:circle(0.62, 0.3, 0.09, PURPLE, { stroke = false })
	p:text("?", 0.5, 0.52, 0.42, WHITE)
	sparkle(p, 0.82, 0.18, 0.22)
end

RECIPES.Slap = function(p)
	for i = 0, 3 do
		p:shape(0.3 + i * 0.14, (i == 1 or i == 2) and 0.26 or 0.3, 0.12, 0.34, WHITE, { rot = -12, round = 0.5 })
	end
	p:shape(0.26, 0.58, 0.12, 0.3, WHITE, { rot = -58, round = 0.5 })
	p:shape(0.5, 0.58, 0.5, 0.36, WHITE, { rot = -12, round = 0.3 })
	for i = 0, 2 do
		p:shape(0.84, 0.35 + i * 0.14, 0.2 - i * 0.03, 0.05, rgb(255, 140, 60), { round = 0.5, stroke = false })
	end
end

RECIPES.Upgrade_Income = function(p)
	p:circle(0.5, 0.56, 0.74, rgb(225, 170, 95))
	p:shape(0.5, 0.3, 0.66, 0.22, GREEN, { round = 0.5 })
	for _, x in { 0.3, 0.52, 0.7 } do
		p:shape(x, 0.42, 0.1, 0.18, GREEN, { round = 0.5, stroke = false })
	end
	p:circle(0.38, 0.6, 0.12, rgb(90, 55, 30), { stroke = false })
	p:circle(0.62, 0.6, 0.12, rgb(90, 55, 30), { stroke = false })
	p:circle(0.5, 0.76, 0.09, rgb(90, 55, 30), { stroke = false })
end

RECIPES.Upgrade_CarrySpeed = function(p)
	p:shape(0.4, 0.66, 0.5, 0.22, GREEN, { rot = -35, round = 0.5 })
	p:shape(0.58, 0.36, 0.44, 0.22, GREEN, { rot = 55, round = 0.5 })
	p:circle(0.5, 0.36, 0.3, GREEN:Lerp(WHITE, 0.1))
	p:shape(0.3, 0.68, 0.1, 0.26, GOLD, { rot = -35, round = 0.2 })
	p:circle(0.72, 0.22, 0.26, GREEN)
	p:shape(0.5, 0.88, 0.5, 0.06, INK, { round = 0.5, alpha = 0.55, stroke = false, flat = true })
end

RECIPES.Upgrade_OfflineCap = function(p)
	p:circle(0.46, 0.5, 0.72, rgb(255, 225, 90))
	p:circle(0.62, 0.42, 0.62, rgb(66, 66, 150), { stroke = false, flat = true })
	blob(p, 0.36, 0.64, 0.26, GREEN)
	p:text("z", 0.55, 0.42, 0.14, WHITE)
	for _, s in { { 0.78, 0.2, 0.2 }, { 0.84, 0.55, 0.14 }, { 0.62, 0.84, 0.14 } } do
		p:text("★", s[1], s[2], s[3], rgb(255, 235, 120))
	end
end

RECIPES.Upgrade_Luck = function(p)
	clover(p, 0.5, 0.48, 0.9, rgb(70, 190, 90))
	p:circle(0.5, 0.48, 0.3, GOLD)
	p:circle(0.47, 0.44, 0.1, rgb(255, 240, 170), { stroke = false, flat = true })
end

RECIPES.Upgrade_RainMagnet = function(p)
	p:shape(0.5, 0.36, 0.62, 0.62, RED, { round = 0.5 })
	p:shape(0.5, 0.42, 0.3, 0.46, rgb(80, 130, 210), { round = 0.5, stroke = false, flat = true })
	p:shape(0.3, 0.6, 0.18, 0.28, RED, { round = 0.1 })
	p:shape(0.7, 0.6, 0.18, 0.28, RED, { round = 0.1 })
	p:shape(0.3, 0.76, 0.18, 0.12, SILVER, { round = 0.1 })
	p:shape(0.7, 0.76, 0.18, 0.12, SILVER, { round = 0.1 })
	for _, x in { 0.22, 0.5, 0.78 } do
		p:circle(x, 0.92, 0.1, rgb(120, 200, 255), { stroke = false })
	end
	p:text("*", 0.5, 0.82, 0.2, WHITE)
end

RECIPES.Boost_Code = function(p)
	bottle(p, rgb(255, 205, 40))
end

RECIPES.Boost_Blessed = function(p)
	p:circle(0.5, 0.22, 0.56, rgb(255, 245, 200))
	p:shape(0.5, 0.22, 0.34, 0.2, rgb(130, 90, 220), { round = 0.5, stroke = false, flat = true })
	blob(p, 0.5, 0.64, 0.5, rgb(235, 225, 255))
	sparkle(p, 0.18, 0.4, 0.22)
	sparkle(p, 0.84, 0.5, 0.2)
end

RECIPES.Boost_Weekend = function(p)
	local colors = { RED, BLUE, GREEN, PURPLE, GOLD }
	for i = 1, 10 do
		local a = i * 0.628
		p:shape(
			0.5 + math.cos(a) * 0.4,
			0.5 + math.sin(a) * 0.4,
			0.1,
			0.06,
			colors[(i - 1) % 5 + 1],
			{ rot = i * 37 % 90, stroke = false, round = 0.2 }
		)
	end
	p:text("x2", 0.5, 0.5, 0.86, GOLD)
end

RECIPES.Boost_Friend = function(p)
	blob(p, 0.27, 0.6, 0.42, rgb(110, 210, 90))
	blob(p, 0.73, 0.6, 0.42, rgb(130, 190, 255))
	p:text("💗", 0.5, 0.26, 0.34)
end

RECIPES.Perk_income = function(p)
	p:circle(0.5, 0.64, 0.64, rgb(150, 205, 110))
	p:shape(0.5, 0.34, 0.26, 0.14, rgb(120, 175, 85), { round = 0.4 })
	p:text("$", 0.5, 0.64, 0.4, GOLD)
	p:circle(0.72, 0.2, 0.26, GOLD)
	p:circle(0.72, 0.2, 0.14, GOLD_D, { stroke = false, flat = true })
end

RECIPES.Perk_luck = function(p)
	clover(p, 0.5, 0.5, 0.9, rgb(70, 190, 90))
	p:circle(0.58, 0.4, 0.28, RED)
	p:shape(0.58, 0.4, 0.03, 0.28, INK, { stroke = false, flat = true })
	p:circle(0.54, 0.34, 0.05, INK, { stroke = false, flat = true })
	p:circle(0.63, 0.45, 0.05, INK, { stroke = false, flat = true })
end

RECIPES.Perk_mutation = function(p)
	for i = 0, 6 do
		local y = 0.1 + i * 0.13
		local x = math.sin(i * 0.95) * 0.22
		p:shape(0.5, y, math.abs(x) * 2, 0.03, WHITE, { alpha = 0.6, stroke = false, flat = true })
		p:circle(0.5 + x, y, 0.15, PURPLE)
		p:circle(0.5 - x, y, 0.15, rgb(110, 220, 110))
	end
end

RECIPES.Event_luck = function(p)
	local arch = p:clip(0.5, 0.36, 0.9, 0.5)
	for i, c in ipairs({ RED, rgb(255, 160, 50), GOLD, GREEN, BLUE }) do
		arch:circle(0.5, 1, 1.9 - i * 0.28, c, { stroke = false, flat = true })
	end
	p:text("🍀", 0.5, 0.42, 0.34)
	p:circle(0.3, 0.8, 0.2, GOLD)
	p:circle(0.5, 0.84, 0.2, GOLD_D)
	p:circle(0.7, 0.8, 0.2, GOLD)
end

RECIPES.Event_mutation = function(p)
	p:shape(0.5, 0.2, 0.22, 0.3, rgb(200, 235, 250), { round = 0.2 })
	p:circle(0.5, 0.62, 0.66, rgb(200, 235, 250))
	p:circle(0.5, 0.65, 0.52, rgb(110, 220, 120), { stroke = false })
	blob(p, 0.5, 0.68, 0.3, rgb(190, 255, 170))
	p:circle(0.3, 0.4, 0.07, WHITE, { alpha = 0.5, stroke = false, flat = true })
	sparkle(p, 0.84, 0.2, 0.22)
	p:text("🧬", 0.2, 0.16, 0.2)
end

RECIPES.Event_rain = function(p)
	for i = 0, 3 do
		p:shape(0.24 + i * 0.17, 0.78 - (i % 2) * 0.1, 0.07, 0.18, rgb(110, 225, 100), { rot = 12, round = 0.5 })
	end
	cloud(p, 0.5, 0.36, 0.9, rgb(95, 120, 170))
end

RECIPES.Appraise = function(p)
	p:shape(0.76, 0.8, 0.14, 0.34, GOLD_D, { rot = -45, round = 0.3 })
	p:circle(0.42, 0.42, 0.66, GOLD)
	p:circle(0.42, 0.42, 0.5, rgb(190, 235, 255), { stroke = false })
	blob(p, 0.42, 0.46, 0.3, rgb(110, 210, 90))
	sparkle(p, 0.7, 0.18, 0.24)
end

RECIPES.Daily = function(p)
	p:shape(0.46, 0.52, 0.7, 0.76, WHITE, { round = 0.1 })
	p:shape(0.46, 0.26, 0.7, 0.24, RED, { round = 0.1 })
	p:text("★", 0.46, 0.56, 0.36, GOLD)
	p:text("🎁", 0.78, 0.78, 0.32)
end

RECIPES.Rebirth = function(p)
	p:circle(0.5, 0.5, 0.8, rgb(110, 215, 160))
	p:text("♻️", 0.5, 0.5, 0.66, WHITE)
	sparkle(p, 0.82, 0.2, 0.24)
	sparkle(p, 0.18, 0.78, 0.2)
end

RECIPES.Cash = coinPile

RECIPES.Gift = function(p)
	p:shape(0.5, 0.64, 0.72, 0.5, PURPLE, { round = 0.1 })
	p:shape(0.5, 0.4, 0.8, 0.2, PURPLE:Lerp(WHITE, 0.15), { round = 0.2, rot = -4 })
	p:shape(0.5, 0.6, 0.14, 0.62, GOLD, { round = 0.1 })
	p:circle(0.4, 0.26, 0.22, GOLD)
	p:circle(0.6, 0.26, 0.22, GOLD)
	p:circle(0.5, 0.3, 0.1, GOLD_D, { flat = true })
	sparkle(p, 0.82, 0.16, 0.22)
end

RECIPES.Quest = function(p)
	for i, c in ipairs({ RED, WHITE, RED, WHITE, RED }) do
		p:circle(0.46, 0.56, 0.82 - (i - 1) * 0.16, c, { flat = i % 2 == 0 })
	end
	p:shape(0.7, 0.3, 0.5, 0.06, GOLD_D, { rot = -40, round = 0.5 })
	p:shape(0.86, 0.14, 0.14, 0.14, WHITE, { rot = -40, round = 0.2 })
end

RECIPES.Code_SLIMEBOOST = RECIPES.Boost_Code
RECIPES.Code_WELCOME = RECIPES.Cash
RECIPES.Code_LAUNCH = RECIPES.Cash

ItemIconArt.RECIPES = table.freeze(RECIPES)

function ItemIconArt.has(id: string): boolean
	return RECIPES[id] ~= nil
end

-- Rebuilds the recipe for `id` into `parent` (an empty frame); false when there is none.
function ItemIconArt.draw(parent: Instance, id: string, z: number): boolean
	local recipe = RECIPES[id]
	if recipe == nil then
		return false
	end
	recipe(newPen(parent, z))
	return true
end

return ItemIconArt
