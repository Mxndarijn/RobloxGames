--!strict
--[[
	MascotSign (Instance builders, no Roblox API at load time)

	The plot sign by the bridge: the jar's slime mascot peeking over a glass nameplate, its two paws on the edge.
	The nameplate has the owner's name and stats. The plot's theme (Config.PLOT_SKINS) colours the mascot and a strip of
	goo along the nameplate's top edge that drips down its face. A free plot shows a pale mascot asleep. PlotSigns draws it on the
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

-- The goo along the nameplate's top edge: the strip { x, y, w, h } on the face and its drips { x, length } (face
-- fractions), kept near the ends so they stay clear of the text.
MascotSign.GOO = table.freeze({
	strip = table.freeze({ 0.02, 0.44, 0.96, 0.075 }),
	drips = table.freeze({
		table.freeze({ 0.07, 0.15 }),
		table.freeze({ 0.16, 0.09 }),
		table.freeze({ 0.84, 0.12 }),
		table.freeze({ 0.93, 0.07 }),
	}),
	drip = 0.032, -- drip width
	dripTop = 0.47, -- where the drips start, inside the strip
})

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
		-- The theme's goo along the bar's top edge, dripping down its face (painted in the mascot's colour).
		local G = MascotSign.GOO
		frame(deps, root, "Goo", C.asleep, G.strip, 5, 0.5)
		for i, d in G.drips do
			frame(deps, root, `Drip{i}`, C.asleep, { d[1] - G.drip / 2, G.dripTop, G.drip, d[2] }, 5, 1)
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

-- Paints `sign` for `look`: the text, awake or asleep, and the theme colour on the mascot and the nameplate's goo.
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
	sign.root:FindFirstChild("Goo").BackgroundColor3 = color(deps, body)
	for i in MascotSign.GOO.drips do
		sign.root:FindFirstChild(`Drip{i}`).BackgroundColor3 = color(deps, body)
	end
end

return table.freeze(MascotSign)
