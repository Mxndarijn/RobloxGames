--!strict
--[[
	MascotSign (Instance builders, no Roblox API at load time)

	The plot sign by the bridge: the jar's slime mascot peeking over a glass nameplate, its two paws on the edge.
	The nameplate has the owner's name and stats. The mascot wears the plot's theme (Config.PLOT_SKINS): the skin's
	colour and a small extra on its head or body. A free plot shows a pale mascot asleep. PlotSigns draws it on the
	plot's Sign part, server-side, so every player sees the same sign.

	  MascotSign.build(parent, deps) -> Sign      every piece, filling `parent` (a SurfaceGui); finds an existing one
	  MascotSign.paint(sign, deps, look)          title / stats text, awake in the skin's look or asleep

	Sizes are scale fractions of the Sign's face (WorldLayout.NAME_BOARD, 2:1). `deps` ({ Instance, Enum, UDim,
	UDim2, Color3, ColorSequence, ColorSequenceKeypoint }) is the Roblox globals in the game and @lune/roblox's in
	tests.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local GooPalette = if script then require(script.Parent.GooPalette) else require("./GooPalette")

export type Deps = {
	Instance: any,
	Enum: any,
	UDim: any,
	UDim2: any,
	Color3: any,
	ColorSequence: any,
	ColorSequenceKeypoint: any,
}
export type Look = { title: string, stats: string, owned: boolean, skin: string? }
export type Sign = { root: any, mascot: any, title: any, stats: any }

local MascotSign = {}

MascotSign.ROOT = "MascotSign"
MascotSign.PIXELS_PER_STUD = 50

local function rgb(r: number, g: number, b: number): { number }
	return table.freeze({ r, g, b })
end

MascotSign.COLORS = table.freeze({
	asleep = rgb(156, 201, 189), -- a free plot's pale mascot
	eye = rgb(255, 255, 255),
	pupil = rgb(16, 20, 24),
	cheek = rgb(245, 154, 176),
	sprout = rgb(95, 191, 74),
	sproutDark = rgb(47, 106, 42),
	acorn = rgb(150, 101, 58), -- Forest's acorn cap
	acornHi = rgb(196, 146, 92),
	acornDark = rgb(86, 54, 27),
	ice = rgb(214, 244, 255),
	iceEdge = rgb(44, 111, 136),
	star = rgb(255, 224, 110),
	starEdge = rgb(196, 140, 20),
	sprinkles = table.freeze({ rgb(255, 226, 122), rgb(127, 208, 239), rgb(255, 255, 255), rgb(154, 214, 160) }),
})

-- Boxes { x, y, w, h } as fractions of the face (2:1), or of the mascot's square for its own pieces.
MascotSign.BOX = table.freeze({
	bar = table.freeze({ 0, 0.46, 1, 0.54 }),
	title = table.freeze({ 0.04, 0.05, 0.92, 0.53 }), -- inside the bar
	stats = table.freeze({ 0.06, 0.6, 0.88, 0.3 }), -- inside the bar
	mascot = table.freeze({ 0.3, 0.14, 0.4, 0.8 }), -- a circle (0.4 of the width = 0.8 of the height); the bar hides its lower half
	eyes = table.freeze({ 0.35, 0.65 }), -- eye centres x, inside the mascot
	eyeY = 0.24,
	eye = 0.17,
	cheeks = table.freeze({ 0.2, 0.8 }), -- below and outside the eyes, above the bar
	cheekY = 0.29,
	cheek = table.freeze({ 0.13, 0.09 }),
	paws = table.freeze({ 0.3, 0.7 }), -- paw centres x on the face: at the mascot's sides
	paw = table.freeze({ 0.07, 0.12 }), -- paw w, h on the face
	deepen = 0.12, -- the body is the skin's swatch colour this much toward Ink, so the white eyes stand out
	zz = table.freeze({ 0.66, 0.02, 0.14, 0.16 }),
	corner = 0.22, -- the bar's corner, fraction of its height
	stroke = 5, -- px, the bar's outline
})

-- What each skin puts on its mascot (skin ids from Config.PLOT_SKINS); none for the rest.
MascotSign.EXTRAS = table.freeze({
	garden = "sprout",
	crystal = "crystal",
	starlight = "star",
	candy = "sprinkles",
	mushroom = "acorn",
} :: { [string]: string })

local function color(deps: Deps, c: { number }): any
	return deps.Color3.fromRGB(c[1], c[2], c[3])
end

local function mix(c: { number }, to: { number }, f: number): { number }
	local function at(i: number): number
		return math.floor(c[i] + (to[i] - c[i]) * f + 0.5)
	end
	return { at(1), at(2), at(3) }
end

local function make(deps: Deps, className: string, props: { [string]: any }, parent: any): any
	local inst = deps.Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function place(deps: Deps, inst: any, b: { number })
	inst.Position = deps.UDim2.fromScale(b[1], b[2])
	inst.Size = deps.UDim2.fromScale(b[3], b[4])
end

local function frame(
	deps: Deps,
	parent: any,
	name: string,
	c: { number },
	b: { number },
	z: number,
	round: number?
): any
	local f =
		make(deps, "Frame", { Name = name, BackgroundColor3 = color(deps, c), BorderSizePixel = 0, ZIndex = z }, parent)
	place(deps, f, b)
	if round then
		make(deps, "UICorner", { CornerRadius = deps.UDim.new(round, 0) }, f)
	end
	return f
end

-- The mascot body colour for a look: the skin's colour awake, pale asleep.
function MascotSign.bodyColor(look: Look): { number }
	if not look.owned then
		return MascotSign.COLORS.asleep
	end
	local swatch: { number } = Config.PLOT_SKINS[1].color or MascotSign.COLORS.asleep
	for _, skin in Config.PLOT_SKINS do
		if skin.id == look.skin and skin.color then
			swatch = skin.color
		end
	end
	return mix(swatch, GooPalette.Ink, MascotSign.BOX.deepen)
end

-- The extra a look's mascot wears, or nil.
function MascotSign.extra(look: Look): string?
	return if look.owned and look.skin then MascotSign.EXTRAS[look.skin] else nil
end

local function buildExtras(deps: Deps, root: any)
	local C = MascotSign.COLORS
	local sprout = make(deps, "Frame", { Name = "sprout", BackgroundTransparency = 1, ZIndex = 2 }, root)
	place(deps, sprout, { 0.455, 0.0, 0.09, 0.17 })
	frame(deps, sprout, "Stem", C.sproutDark, { 0.44, 0.5, 0.12, 0.5 }, 2)
	local l = frame(deps, sprout, "LeafL", C.sprout, { -0.05, 0.1, 0.55, 0.45 }, 2, 1)
	l.Rotation = -25
	local r = frame(deps, sprout, "LeafR", C.sprout, { 0.5, 0.1, 0.55, 0.45 }, 2, 1)
	r.Rotation = 25

	-- Frost: a little crown of ice crystals sitting on the head (the face is 2:1, so a square is w = h / 2).
	local crystal = make(deps, "Frame", { Name = "crystal", BackgroundTransparency = 1, ZIndex = 2 }, root)
	place(deps, crystal, { 0, 0, 1, 1 })
	for i, c in { { 0.48, 0.07, 0.04, 45 }, { 0.443, 0.105, 0.028, 30 }, { 0.529, 0.105, 0.028, 60 } } do
		local gem = frame(deps, crystal, `Gem{i}`, C.ice, { c[1], c[2], c[3], c[3] * 2 }, 2, 0.15)
		gem.Rotation = c[4]
		make(deps, "UIStroke", { Color = color(deps, C.iceEdge), Thickness = 2 }, gem)
	end

	-- Starlight: an eight-point star on the head.
	local star = make(deps, "Frame", { Name = "star", BackgroundTransparency = 1, ZIndex = 2 }, root)
	place(deps, star, { 0.45, 0.0, 0.1, 0.2 })
	for i, rot in { 0, 45 } do
		local ray = frame(deps, star, `Ray{i}`, C.star, { 0.2, 0.2, 0.6, 0.6 }, 2, 0.12)
		ray.Rotation = rot
		make(deps, "UIStroke", { Color = color(deps, C.starEdge), Thickness = 1.5 }, ray)
	end

	-- Candy: sprinkles on the top of the head, clear of the eyes.
	local sprinkles = make(deps, "Frame", { Name = "sprinkles", BackgroundTransparency = 1, ZIndex = 2 }, root)
	place(deps, sprinkles, { 0, 0, 1, 1 })
	local spots = {
		{ 0.37, 0.21, -30 },
		{ 0.46, 0.165, 20 },
		{ 0.55, 0.17, 70 },
		{ 0.63, 0.22, -40 },
		{ 0.345, 0.3, 10 },
		{ 0.655, 0.3, 60 },
	}
	for i, spot in spots do
		local c = C.sprinkles[(i - 1) % #C.sprinkles + 1]
		local bit = frame(deps, sprinkles, `Bit{i}`, c, { spot[1], spot[2], 0.026, 0.026 }, 2, 0.5)
		bit.Rotation = spot[3]
	end

	-- Forest: a small acorn cap worn like a hat, with its little stem on top (the top of a rounded frame, cut off flat
	-- by its holder, so it sits on the head like a cap).
	local acorn = make(deps, "Frame", { Name = "acorn", BackgroundTransparency = 1, ZIndex = 2 }, root)
	place(deps, acorn, { 0, 0, 1, 1 })
	frame(deps, acorn, "Stem", C.acornDark, { 0.494, 0.03, 0.014, 0.06 }, 2, 0.4)
	local holder =
		make(deps, "Frame", { Name = "Cap", BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2 }, acorn)
	place(deps, holder, { 0.41, 0.075, 0.18, 0.135 })
	local cap = frame(deps, holder, "Dome", GooPalette.White, { 0, 0, 1, 2 }, 2, 1)
	make(deps, "UIStroke", { Color = color(deps, C.acornDark), Thickness = 1.5 }, cap)
	local K = deps.ColorSequenceKeypoint
	make(deps, "UIGradient", {
		Rotation = 90,
		Color = deps.ColorSequence.new({
			K.new(0, color(deps, C.acornHi)),
			K.new(0.6, color(deps, C.acorn)),
			K.new(1, color(deps, C.acorn)),
		}),
	}, cap)
	-- the cap's scales: two rows of small darker dots
	for i, d in
		{ { 0.22, 0.2 }, { 0.42, 0.14 }, { 0.62, 0.14 }, { 0.8, 0.2 }, { 0.32, 0.38 }, { 0.52, 0.34 }, { 0.71, 0.38 } }
	do
		frame(deps, cap, `Scale{i}`, C.acornDark, { d[1] - 0.05, d[2], 0.1, 0.09 }, 2, 1).BackgroundTransparency = 0.45
	end
	frame(deps, acorn, "Rim", C.acornDark, { 0.405, 0.2, 0.19, 0.02 }, 2, 0.5)
end

-- Every piece of the sign, filling `parent`; finds an existing one first, so callers stay idempotent.
function MascotSign.build(parent: any, deps: Deps): Sign
	local C, B = MascotSign.COLORS, MascotSign.BOX
	local root = parent:FindFirstChild(MascotSign.ROOT)
	if not root then
		root = make(
			deps,
			"Frame",
			{ Name = MascotSign.ROOT, BackgroundTransparency = 1, Size = deps.UDim2.fromScale(1, 1) },
			parent
		)
		-- The mascot: a circle whose lower half hides behind the bar.
		local mascot = frame(deps, root, "Mascot", C.asleep, B.mascot, 1, 1)
		mascot.BackgroundColor3 = color(deps, GooPalette.White)
		make(deps, "UIGradient", { Name = "Shade", Rotation = 90 }, mascot)
		local shine = frame(deps, mascot, "Shine", C.eye, { 0.16, 0.1, 0.2, 0.12 }, 1, 1)
		shine.BackgroundTransparency = 0.45
		shine.Rotation = -24
		for i, x in B.eyes do
			local eye = frame(deps, mascot, `Eye{i}`, C.eye, { x - B.eye / 2, B.eyeY - B.eye / 2, B.eye, B.eye }, 1, 1)
			make(deps, "UIStroke", { Color = color(deps, GooPalette.Ink), Thickness = 1.5, Transparency = 0.4 }, eye)
			frame(deps, eye, "Pupil", C.pupil, { 0.22, 0.16, 0.56, 0.66 }, 1, 1)
			frame(deps, mascot, `Lid{i}`, C.pupil, { x - B.eye * 0.4, B.eyeY, B.eye * 0.8, 0.025 }, 1, 1)
		end
		for i, x in B.cheeks do
			local cheek =
				frame(deps, mascot, `Cheek{i}`, C.cheek, { x - B.cheek[1] / 2, B.cheekY, B.cheek[1], B.cheek[2] }, 1, 1)
			cheek.BackgroundTransparency = 0.1
		end
		buildExtras(deps, root)
		-- The nameplate, over the mascot's lower half.
		local bar = frame(deps, root, "Bar", GooPalette.White, B.bar, 3)
		make(deps, "UICorner", { CornerRadius = deps.UDim.new(B.corner, 0) }, bar)
		make(deps, "UIStroke", { Color = color(deps, GooPalette.Ink), Thickness = B.stroke }, bar)
		local K = deps.ColorSequenceKeypoint
		make(deps, "UIGradient", {
			Rotation = 90,
			Color = deps.ColorSequence.new({
				K.new(0, color(deps, { 21, 73, 75 })),
				K.new(1, color(deps, GooPalette.Bg)),
			}),
		}, bar)
		type Spec = { name: string, rgb: { number }, box: { number } }
		local specs: { Spec } = {
			{ name = "Title", rgb = GooPalette.Text, box = B.title },
			{ name = "Stats", rgb = GooPalette.Mint, box = B.stats },
		}
		for _, spec in specs do
			local label = make(deps, "TextLabel", {
				Name = spec.name,
				BackgroundTransparency = 1,
				Font = deps.Enum.Font.FredokaOne,
				TextScaled = true,
				TextColor3 = color(deps, spec.rgb),
				Text = "",
				ZIndex = 4,
			}, bar)
			place(deps, label, spec.box)
		end
		-- Its paws on the bar's top edge.
		for i, x in B.paws do
			frame(
				deps,
				root,
				`Paw{i}`,
				C.asleep,
				{ x - B.paw[1] / 2, B.bar[2] - B.paw[2] / 2, B.paw[1], B.paw[2] },
				5,
				0.5
			)
		end
		local zz = make(deps, "TextLabel", {
			Name = "Zz",
			BackgroundTransparency = 1,
			Font = deps.Enum.Font.FredokaOne,
			TextScaled = true,
			Text = "z z",
			TextColor3 = color(deps, GooPalette.Text),
			ZIndex = 2,
		}, root)
		place(deps, zz, B.zz)
		make(deps, "UIStroke", { Color = color(deps, GooPalette.Ink), Thickness = 2 }, zz)
	end
	local bar = root:FindFirstChild("Bar")
	return {
		root = root,
		mascot = root:FindFirstChild("Mascot"),
		title = bar:FindFirstChild("Title"),
		stats = bar:FindFirstChild("Stats"),
	}
end

-- Paints `sign` for `look`: the text, the mascot's colour, awake or asleep, and its theme's extra.
function MascotSign.paint(sign: Sign, deps: Deps, look: Look)
	sign.title.Text = look.title
	sign.stats.Text = look.stats
	local body = MascotSign.bodyColor(look)
	local K = deps.ColorSequenceKeypoint
	sign.mascot:FindFirstChild("Shade").Color = deps.ColorSequence.new({
		K.new(0, color(deps, mix(body, { 255, 255, 255 }, 0.1))),
		K.new(0.15, color(deps, body)),
		K.new(1, color(deps, mix(body, GooPalette.Ink, 0.35))),
	})
	local awake = look.owned
	for i in MascotSign.BOX.eyes do
		sign.mascot:FindFirstChild(`Eye{i}`).Visible = awake
		sign.mascot:FindFirstChild(`Lid{i}`).Visible = not awake
		sign.mascot:FindFirstChild(`Cheek{i}`).BackgroundTransparency = if awake then 0.1 else 0.6
	end
	for i in MascotSign.BOX.paws do
		sign.root:FindFirstChild(`Paw{i}`).BackgroundColor3 = color(deps, body)
	end
	sign.root:FindFirstChild("Zz").Visible = not awake
	local extra = MascotSign.extra(look)
	for _, name in MascotSign.EXTRAS do
		sign.root:FindFirstChild(name).Visible = name == extra
	end
end

return table.freeze(MascotSign)
