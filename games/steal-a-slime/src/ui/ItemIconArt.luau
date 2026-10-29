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
		-- TextScaled draws a lone glyph at about the label's height, so the rise is a share of `size`.
		local rise = Widgets.emojiRise(Widgets.Theme.Font, text) * size
		return create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(cx, cy + rise),
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

RECIPES.Upgrade_QuickBrew = function(p)
	p:shape(0.5, 0.66, 0.7, 0.46, rgb(200, 120, 60), { round = 0.45 })
	p:shape(0.5, 0.46, 0.76, 0.14, rgb(110, 60, 30), { round = 0.5 })
	p:shape(0.5, 0.46, 0.62, 0.08, GREEN, { round = 0.5, stroke = false })
	-- A gold bolt over the goo: two slanted bars.
	p:shape(0.56, 0.16, 0.14, 0.26, GOLD, { rot = 25, round = 0.2 })
	p:shape(0.46, 0.3, 0.14, 0.26, GOLD, { rot = 25, round = 0.2 })
end

RECIPES.Upgrade_Luck = function(p)
	clover(p, 0.5, 0.48, 0.9, rgb(70, 190, 90))
	p:circle(0.5, 0.48, 0.3, GOLD)
	p:circle(0.47, 0.44, 0.1, rgb(255, 240, 170), { stroke = false, flat = true })
end

-- World shop items without art yet: restocking consumables (Consumable_<id>) and PvP tools (Pvp_<id>).
local function flask(p: Pen, liquid: Color, mark: string)
	p:shape(0.5, 0.2, 0.2, 0.2, SILVER, { round = 0.3 })
	p:shape(0.5, 0.36, 0.3, 0.22, rgb(200, 235, 250), { round = 0.2 })
	p:circle(0.5, 0.66, 0.66, rgb(200, 235, 250))
	p:circle(0.5, 0.69, 0.52, liquid, { stroke = false })
	p:text(mark, 0.5, 0.68, 0.34)
end

RECIPES.Consumable_LuckPotion = function(p)
	flask(p, rgb(70, 190, 90), "🍀")
	sparkle(p, 0.82, 0.2, 0.2)
end

RECIPES.Consumable_WeatherTotem = function(p)
	p:shape(0.5, 0.82, 0.62, 0.16, rgb(120, 125, 140), { round = 0.3 })
	p:shape(0.5, 0.5, 0.42, 0.7, rgb(150, 155, 170), { round = 0.2 })
	p:shape(0.5, 0.26, 0.5, 0.18, rgb(170, 175, 190), { round = 0.3 })
	p:circle(0.4, 0.46, 0.1, INK, { stroke = false, flat = true })
	p:circle(0.6, 0.46, 0.1, INK, { stroke = false, flat = true })
	p:shape(0.5, 0.66, 0.24, 0.07, INK, { round = 0.5, stroke = false, flat = true })
	cloud(p, 0.5, 0.1, 0.34, WHITE)
end

local TIER_COLORS = {
	rgb(120, 200, 120),
	rgb(90, 160, 240),
	rgb(170, 100, 220),
	rgb(255, 150, 60),
	rgb(255, 204, 60),
}
-- Config.PVP_TOOLS: id, line, tier, glyph of the Fun items (tests/ui/WorldShop.spec checks the list is complete).
local PVP_ART: { { string | number } } = {
	{ "KnockGlove1", "Knockback", 1 },
	{ "KnockGlove2", "Knockback", 2 },
	{ "KnockGlove3", "Knockback", 3 },
	{ "KnockGlove4", "Knockback", 4 },
	{ "KnockGlove5", "Knockback", 5 },
	{ "GooTrap1", "Trap", 1 },
	{ "GooTrap2", "Trap", 2 },
	{ "GooTrap3", "Trap", 3 },
	{ "GooBlaster1", "Blaster", 1 },
	{ "GooBlaster2", "Blaster", 2 },
	{ "GooBlaster3", "Blaster", 3 },
	{ "FunConfetti", "Fun", 1, "🎉" },
	{ "FunBalloon", "Fun", 2, "🎈" },
	{ "FunBubbles", "Fun", 3, "🫧" },
	{ "FunBouncePad", "Fun", 4, "🦘" },
	{ "FunSqueaky", "Fun", 5, "🔨" },
	{ "FunHatLauncher", "Fun", 1, "🎩" },
	{ "FunDanceBomb", "Fun", 2, "💣" },
	{ "FunFireworks", "Fun", 3, "🎆" },
}
ItemIconArt.PVP_IDS = table.freeze(table.clone(PVP_ART))

for _, row in PVP_ART do
	local line, tier = row[2] :: string, row[3] :: number
	local color = TIER_COLORS[math.min(tier, #TIER_COLORS)]
	local glyph = row[4] :: string?
	RECIPES[`Pvp_{row[1]}`] = function(p)
		if line == "Knockback" then
			p:shape(0.5, 0.82, 0.5, 0.2, color, { round = 0.2 })
			p:circle(0.5, 0.46, 0.66, WHITE)
			p:shape(0.74, 0.4, 0.2, 0.26, WHITE, { rot = 30, round = 0.5 })
			p:shape(0.4, 0.36, 0.34, 0.08, color:Lerp(INK, 0.3), { round = 0.5, stroke = false, flat = true })
		elseif line == "Trap" then
			p:shape(0.5, 0.64, 0.84, 0.4, color, { round = 0.5 })
			p:shape(0.5, 0.62, 0.6, 0.26, color:Lerp(WHITE, 0.3), { round = 0.5, stroke = false })
			p:circle(0.32, 0.3, 0.14, color, { stroke = false })
			p:circle(0.62, 0.22, 0.1, color, { stroke = false })
		elseif line == "Blaster" then
			p:shape(0.46, 0.46, 0.62, 0.3, color, { round = 0.3 })
			p:shape(0.8, 0.44, 0.2, 0.14, SILVER, { round = 0.3 })
			p:shape(0.34, 0.7, 0.16, 0.3, color:Lerp(INK, 0.35), { round = 0.2, rot = 12 })
			p:circle(0.5, 0.46, 0.2, WHITE, { stroke = false, flat = true })
		else
			p:circle(0.5, 0.5, 0.82, color)
			p:circle(0.5, 0.5, 0.64, color:Lerp(WHITE, 0.25), { stroke = false })
			p:circle(0.34, 0.3, 0.14, WHITE, { stroke = false, flat = true, alpha = 0.5 })
			p:text(glyph or "?", 0.5, 0.52, 0.46, WHITE)
		end
	end
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

RECIPES.Boost_Mvp = function(p)
	coinPile(p)
	p:text("👑", 0.5, 0.16, 0.4, GOLD)
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

RECIPES.Pet = function(p)
	cloud(p, 0.5, 0.78, 0.86, rgb(190, 222, 255))
	blob(p, 0.5, 0.48, 0.6, rgb(255, 150, 60))
	p:shape(0.5, 0.66, 0.5, 0.07, RED, { round = 0.5 })
	p:circle(0.5, 0.72, 0.11, GOLD)
	sparkle(p, 0.16, 0.24, 0.18)
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

RECIPES.Event_rain = function(p)
	for i = 0, 3 do
		p:shape(0.24 + i * 0.17, 0.78 - (i % 2) * 0.1, 0.07, 0.18, rgb(110, 225, 100), { rot = 12, round = 0.5 })
	end
	cloud(p, 0.5, 0.36, 0.9, rgb(95, 120, 170))
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

-- Goals: one scene per Config.GOALS id.
RECIPES.Goal_Catch = function(p)
	p:shape(0.3, 0.78, 0.07, 0.5, rgb(150, 100, 55), { rot = 35, round = 0.4 })
	p:circle(0.6, 0.38, 0.62, WHITE, { alpha = 0.55 })
	blob(p, 0.6, 0.42, 0.32, GREEN)
	p:shape(0.6, 0.38, 0.62, 0.05, rgb(150, 100, 55), { round = 0.5 })
end

RECIPES.Goal_Merge = function(p)
	blob(p, 0.26, 0.62, 0.34, rgb(110, 210, 90))
	blob(p, 0.74, 0.62, 0.34, rgb(130, 190, 255))
	blob(p, 0.5, 0.3, 0.46, PURPLE)
	p:text("🌀", 0.5, 0.82, 0.26)
end

RECIPES.Goal_Steal = function(p)
	blob(p, 0.4, 0.5, 0.5, rgb(235, 90, 90))
	p:shape(0.4, 0.46, 0.5, 0.14, INK, { round = 0.3, stroke = false, flat = true })
	p:circle(0.74, 0.7, 0.4, rgb(190, 140, 80))
	p:text("$", 0.74, 0.7, 0.2, GOLD)
	for i = 0, 2 do
		p:shape(0.1, 0.4 + i * 0.12, 0.16 - i * 0.03, 0.04, WHITE, { alpha = 0.6, stroke = false, flat = true })
	end
end

RECIPES.Goal_Lock = function(p)
	padlock(p, 0.5, 0.5, 0.9, BLUE)
	p:text("★", 0.5, 0.64, 0.24, GOLD)
end

RECIPES.Goal_Pads = function(p)
	p:shape(0.5, 0.74, 0.84, 0.3, rgb(150, 155, 165), { round = 0.3 })
	p:shape(0.5, 0.7, 0.66, 0.18, rgb(110, 215, 120), { round = 0.5 })
	p:shape(0.5, 0.7, 0.8, 0.28, rgb(120, 230, 130), { round = 0.5, alpha = 0.7, stroke = false, flat = true })
	blob(p, 0.5, 0.42, 0.46, GREEN)
end

RECIPES.Goal_Earn = function(p)
	for i = 0, 4 do
		p:shape(0.5, 0.86 - i * 0.15, 0.56, 0.16, i % 2 == 0 and GOLD or GOLD_D, { round = 0.5 })
	end
	p:text("$", 0.5, 0.16, 0.24, GOLD)
end

RECIPES.Goal_Rebirth = function(p)
	p:circle(0.5, 0.5, 0.8, rgb(110, 215, 160))
	p:text("♻️", 0.5, 0.5, 0.66, WHITE)
	sparkle(p, 0.82, 0.2, 0.24)
	sparkle(p, 0.18, 0.78, 0.2)
end

-- Dex reward trophies: a gold cup with a slime on top and the milestone on the base. The cup
-- (and the slime) get richer towards the top milestone.
local function trophy(p: Pen, count: number)
	local digits = #tostring(count)
	p:shape(0.5, 0.9, 0.56, 0.12, rgb(120, 90, 60), { round = 0.2 })
	p:shape(0.5, 0.78, 0.2, 0.16, GOLD_D, { round = 0.2 })
	p:shape(0.5, 0.52, 0.56, 0.44, GOLD, { round = 0.4 })
	p:circle(0.2, 0.44, 0.22, GOLD, { stroke = true })
	p:circle(0.8, 0.44, 0.22, GOLD, { stroke = true })
	p:shape(0.5, 0.52, 0.56, 0.44, GOLD, { round = 0.4 })
	p:shape(0.5, 0.29, 0.6, 0.06, GOLD_D, { round = 0.5 })
	blob(p, 0.5, 0.15, 0.3, if count >= 200 then PURPLE else GREEN)
	p:text(tostring(count), 0.5, 0.54, if digits >= 3 then 0.5 else 0.4, rgb(150, 95, 10))
end

-- Badges: a gold medal on a ribbon with a small emblem per badge.
local BADGE_EMBLEMS: { [string]: { glyph: string, tint: Color? } } = {
	FirstSlime = { glyph = "★" },
	FirstSteal = { glyph = "💨" },
	FirstRebirth = { glyph = "♻️" },
	Rebirth5 = { glyph = "5", tint = rgb(110, 215, 160) },
	Dex25 = { glyph = "25", tint = BLUE },
	Dex50 = { glyph = "50", tint = GREEN },
	Dex100 = { glyph = "100", tint = PURPLE },
	FirstLegendary = { glyph = "👑" },
	FirstSecret = { glyph = "🔒" },
	Millionaire = { glyph = "$", tint = rgb(110, 210, 90) },
}

local function medal(p: Pen, key: string)
	local e = BADGE_EMBLEMS[key] or BADGE_EMBLEMS.FirstSlime
	p:shape(0.36, 0.2, 0.2, 0.44, RED, { rot = 20, round = 0.1 })
	p:shape(0.64, 0.2, 0.2, 0.44, BLUE, { rot = -20, round = 0.1 })
	p:circle(0.5, 0.62, 0.74, GOLD)
	p:circle(0.5, 0.62, 0.56, GOLD_D, { stroke = false, flat = true })
	p:circle(0.5, 0.62, 0.5, e.tint or GOLD, { stroke = true })
	p:text(e.glyph, 0.5, 0.62, if #e.glyph >= 3 then 0.46 else 0.38, WHITE)
end

for key in BADGE_EMBLEMS do
	RECIPES[`Badge_{key}`] = function(p)
		medal(p, key)
	end
end

-- SlimeDex milestone trophies (Config.DEX_MILESTONES): "Dex_<species count>".
local function trophyRecipe(id: string): ((Pen) -> ())?
	local count = tonumber(string.match(id, "^Dex_(%d+)$"))
	if count == nil then
		return nil
	end
	return function(p)
		trophy(p, count)
	end
end

-- Pet seats (PetSeat_<id>): one puffy cloud with a slime on it for every seat, shown only when the seat's uploaded
-- picture can't be used; the tile behind it carries the seat's own colour.
local function seatRecipe(id: string): ((Pen) -> ())?
	if string.sub(id, 1, 8) ~= "PetSeat_" then
		return nil
	end
	return function(p)
		p:circle(0.32, 0.66, 0.28, WHITE)
		p:circle(0.68, 0.66, 0.28, WHITE)
		p:circle(0.5, 0.56, 0.34, WHITE)
		p:shape(0.5, 0.74, 0.7, 0.2, WHITE, { round = 0.5, stroke = false })
		blob(p, 0.5, 0.4, 0.3, GREEN)
	end
end

local function color3(c: { number }?, fallback: Color): Color
	return if c then rgb(c[1], c[2], c[3]) else fallback
end

-- Carry trails (Trail_<id>): a slime hopping to the right with the trail's colours streaming out behind it in
-- shrinking puffs, from the spec's `colors`.
local function trailRecipe(id: string): ((Pen, any) -> ())?
	if string.sub(id, 1, 6) ~= "Trail_" then
		return nil
	end
	return function(p, spec)
		local colors: { { number } } = if spec and type(spec.colors) == "table" then spec.colors else {}
		local n = 6
		for i = n, 1, -1 do
			local t = (i - 1) / (n - 1)
			local c = color3(colors[(i - 1) % math.max(#colors, 1) + 1], GOLD)
			p:circle(0.66 - t * 0.5, 0.56 - t * 0.2 + (i % 2) * 0.05, 0.3 - t * 0.17, c)
		end
		sparkle(p, 0.2, 0.22, 0.18)
		blob(p, 0.72, 0.6, 0.38, GREEN)
	end
end

-- Bat skins (BatSkin_<id>): the Bat tilted, barrel and grip in the spec's `colors`.
local function batRecipe(id: string): ((Pen, any) -> ())?
	if string.sub(id, 1, 8) ~= "BatSkin_" then
		return nil
	end
	return function(p, spec)
		local colors = if spec and type(spec.colors) == "table" then spec.colors else {}
		local barrel = color3(colors[1], rgb(222, 170, 110))
		local grip = color3(colors[2], rgb(150, 100, 60))
		p:shape(0.33, 0.68, 0.12, 0.42, grip, { rot = 40, round = 0.5 })
		p:circle(0.2, 0.83, 0.14, grip)
		p:shape(0.6, 0.38, 0.24, 0.62, barrel, { rot = 40, round = 0.5 })
		p:circle(0.66, 0.3, 0.1, barrel:Lerp(WHITE, 0.5), { stroke = false, flat = true })
	end
end

-- Fanfares (Fanfare_), lock styles (LockStyle_) and slime hats (Hat_) of the Exclusive shop (§15), drawn in the
-- spec's colour until pictures are rendered.
local function styleRecipe(id: string): ((Pen, any) -> ())?
	local kind = string.match(id, "^(%a+)_")
	if kind ~= "Fanfare" and kind ~= "LockStyle" and kind ~= "Hat" then
		return nil
	end
	return function(p, spec)
		local c = color3(spec and spec.color, GOLD)
		if kind == "Fanfare" then
			blob(p, 0.5, 0.66, 0.42, GREEN)
			for i = 0, 5 do
				local a = i * math.pi / 3
				p:circle(
					0.5 + 0.34 * math.cos(a),
					0.36 + 0.24 * math.sin(a),
					0.07,
					if i % 2 == 0 then c else rgb(250, 150, 182)
				)
			end
		elseif kind == "LockStyle" then
			p:circle(0.5, 0.5, 0.36, c)
			p:circle(0.5, 0.5, 0.24, c:Lerp(WHITE, 0.4), { stroke = false, flat = true })
			p:shape(0.5, 0.58, 0.2, 0.16, RED, { round = 0.2 })
			p:shape(0.5, 0.46, 0.12, 0.12, RED, { round = 0.5 })
		else
			blob(p, 0.5, 0.66, 0.46, GREEN)
			p:shape(0.5, 0.32, 0.22, 0.26, c, { round = 0.3 })
			p:shape(0.5, 0.44, 0.38, 0.06, c:Lerp(INK, 0.2), { round = 0.5 })
		end
	end
end

-- Plot skins: a small ranch diorama (floor slab, fence posts, decor) per skin.
local function diorama(p: Pen, floor: Color, fence: Color, decor: (Pen) -> ())
	p:shape(0.5, 0.74, 0.92, 0.42, floor:Lerp(INK, 0.25), { round = 0.2 })
	p:shape(0.5, 0.68, 0.92, 0.4, floor, { round = 0.2 })
	for i = 0, 4 do
		p:shape(0.14 + i * 0.18, 0.5, 0.08, 0.2, fence, { round = 0.3 })
	end
	p:shape(0.5, 0.52, 0.84, 0.05, fence, { round = 0.5 })
	decor(p)
end

RECIPES.PlotSkin_classic = function(p)
	diorama(p, rgb(120, 190, 90), rgb(235, 205, 160), function(q)
		blob(q, 0.5, 0.74, 0.3, GREEN)
		q:circle(0.2, 0.78, 0.1, rgb(255, 120, 150), { stroke = false })
		q:circle(0.82, 0.76, 0.1, GOLD, { stroke = false })
	end)
end

RECIPES.PlotSkin_mushroom = function(p)
	diorama(p, rgb(112, 150, 72), rgb(255, 214, 196), function(q)
		q:shape(0.5, 0.64, 0.12, 0.26, CREAM, { round = 0.3 })
		q:shape(0.5, 0.46, 0.46, 0.26, RED, { round = 0.5 })
		q:circle(0.42, 0.44, 0.08, WHITE, { stroke = false, flat = true })
		q:circle(0.58, 0.48, 0.07, WHITE, { stroke = false, flat = true })
		q:shape(0.8, 0.72, 0.1, 0.12, CREAM, { round = 0.3 })
		q:shape(0.8, 0.64, 0.22, 0.12, RED, { round = 0.5 })
	end)
end

RECIPES.PlotSkin_candy = function(p)
	diorama(p, rgb(224, 142, 172), rgb(255, 190, 214), function(q)
		q:shape(0.5, 0.66, 0.06, 0.34, WHITE, { round = 0.4 })
		q:circle(0.5, 0.44, 0.34, rgb(255, 110, 150))
		q:circle(0.5, 0.44, 0.22, WHITE, { stroke = false })
		q:circle(0.5, 0.44, 0.1, rgb(255, 110, 150), { stroke = false })
		q:circle(0.22, 0.78, 0.12, rgb(120, 220, 200))
		q:circle(0.8, 0.78, 0.12, GOLD)
	end)
end

RECIPES.PlotSkin_crystal = function(p)
	diorama(p, rgb(148, 124, 190), rgb(214, 196, 255), function(q)
		q:shape(0.5, 0.56, 0.2, 0.5, rgb(160, 230, 255), { rot = 0, round = 0.2 })
		q:shape(0.36, 0.66, 0.14, 0.32, rgb(200, 150, 255), { rot = -20, round = 0.2 })
		q:shape(0.66, 0.68, 0.14, 0.3, rgb(120, 200, 255), { rot = 22, round = 0.2 })
		sparkle(q, 0.8, 0.3, 0.2)
	end)
end

RECIPES.PlotSkin_garden = function(p)
	diorama(p, rgb(132, 190, 100), rgb(246, 236, 214), function(q)
		q:shape(0.5, 0.62, 0.05, 0.36, rgb(110, 170, 90), { round = 0.4 })
		for i = 0, 7 do
			local a = i * math.pi / 4
			q:circle(0.5 + 0.13 * math.cos(a), 0.4 + 0.13 * math.sin(a), 0.08, GOLD, { stroke = false })
		end
		q:circle(0.5, 0.4, 0.09, rgb(150, 100, 60), { stroke = false })
		q:shape(0.2, 0.78, 0.16, 0.12, rgb(222, 140, 102), { round = 0.3 })
		q:circle(0.2, 0.68, 0.1, rgb(252, 176, 118))
		q:circle(0.82, 0.76, 0.1, rgb(250, 150, 182))
	end)
end

RECIPES.PlotSkin_starlight = function(p)
	diorama(p, rgb(170, 158, 216), rgb(236, 196, 104), function(q)
		q:shape(0.5, 0.64, 0.05, 0.32, rgb(126, 114, 176), { round = 0.4 })
		q:shape(0.5, 0.4, 0.24, 0.24, GOLD, { rot = 45, round = 0.2 })
		q:shape(0.5, 0.4, 0.12, 0.12, rgb(255, 240, 192), { rot = 45, round = 0.2 })
		q:circle(0.22, 0.76, 0.1, rgb(255, 240, 192))
		q:shape(0.82, 0.3, 0.12, 0.12, GOLD, { rot = 45, round = 0.2 })
	end)
end

-- Exclusive base skins (contract/exclusive-shop.md §15), drawn until their tower pictures are rendered.
RECIPES.PlotSkin_fairground = function(p)
	diorama(p, rgb(214, 176, 120), rgb(252, 216, 110), function(q)
		q:shape(0.5, 0.66, 0.05, 0.34, rgb(250, 240, 220), { round = 0.4 })
		q:shape(0.5, 0.36, 0.5, 0.2, rgb(92, 200, 196), { round = 0.5 })
		q:shape(0.38, 0.36, 0.1, 0.2, rgb(250, 240, 220), { round = 0.2 })
		q:shape(0.62, 0.36, 0.1, 0.2, rgb(250, 240, 220), { round = 0.2 })
		q:circle(0.5, 0.24, 0.06, GOLD)
		q:circle(0.2, 0.78, 0.1, rgb(250, 150, 182))
		q:circle(0.82, 0.76, 0.1, GOLD)
	end)
end

RECIPES.PlotSkin_beach = function(p)
	diorama(p, rgb(238, 214, 160), rgb(250, 150, 130), function(q)
		q:shape(0.5, 0.58, 0.05, 0.42, rgb(176, 128, 92), { round = 0.4 })
		q:shape(0.5, 0.34, 0.5, 0.14, rgb(92, 210, 220), { round = 0.5 })
		q:shape(0.5, 0.34, 0.16, 0.14, rgb(250, 240, 220), { round = 0.2 })
		q:circle(0.2, 0.78, 0.1, rgb(250, 150, 130))
		q:shape(0.82, 0.76, 0.14, 0.14, rgb(252, 216, 110), { rot = 45, round = 0.3 })
	end)
end

RECIPES.PlotSkin_space = function(p)
	diorama(p, rgb(150, 150, 196), rgb(140, 232, 244), function(q)
		q:circle(0.5, 0.48, 0.26, rgb(140, 120, 220))
		q:shape(0.5, 0.48, 0.66, 0.08, rgb(140, 232, 244), { rot = -15, round = 0.5 })
		sparkle(q, 0.2, 0.26, 0.14)
		sparkle(q, 0.82, 0.74, 0.12)
	end)
end

RECIPES.PlotSkin_winter = function(p)
	diorama(p, rgb(236, 240, 248), rgb(226, 96, 96), function(q)
		q:shape(0.5, 0.56, 0.36, 0.3, rgb(176, 120, 84), { round = 0.2 })
		q:shape(0.5, 0.38, 0.46, 0.12, WHITE, { round = 0.5 })
		q:shape(0.5, 0.58, 0.1, 0.1, rgb(250, 206, 120), { round = 0.3 })
		q:circle(0.2, 0.78, 0.1, rgb(226, 96, 96))
		q:circle(0.82, 0.78, 0.1, WHITE)
	end)
end

RECIPES.PlotSkin_haunted = function(p)
	diorama(p, rgb(140, 112, 160), rgb(250, 160, 80), function(q)
		q:circle(0.5, 0.5, 0.24, rgb(250, 150, 70))
		q:shape(0.5, 0.28, 0.06, 0.1, rgb(110, 170, 90), { round = 0.4 })
		q:shape(0.44, 0.46, 0.06, 0.06, rgb(80, 60, 90), { rot = 45 })
		q:shape(0.56, 0.46, 0.06, 0.06, rgb(80, 60, 90), { rot = 45 })
		q:shape(0.5, 0.58, 0.16, 0.04, rgb(80, 60, 90), { round = 0.5 })
		q:circle(0.8, 0.26, 0.07, rgb(250, 240, 220))
	end)
end

RECIPES.Code_SLIMEBOOST = RECIPES.Boost_Code
RECIPES.Code_WELCOME = RECIPES.Cash
RECIPES.Code_LAUNCH = RECIPES.Cash

ItemIconArt.RECIPES = table.freeze(RECIPES)

local function recipeOf(id: string): ((Pen, any) -> ())?
	local fixed: any = RECIPES[id] or trophyRecipe(id) or seatRecipe(id)
	return fixed or trailRecipe(id) or batRecipe(id) or styleRecipe(id)
end

function ItemIconArt.has(id: string): boolean
	return recipeOf(id) ~= nil
end

-- Rebuilds the recipe for `id` into `parent` (an empty frame); false when there is none. `spec` (the ItemIcons
-- spec) gives the scenes drawn in an item's own colours (trails, Bat skins) their `colors`.
function ItemIconArt.draw(parent: Instance, id: string, z: number, spec: any?): boolean
	local recipe = recipeOf(id)
	if recipe == nil then
		return false
	end
	recipe(newPen(parent, z), spec)
	return true
end

return ItemIconArt
