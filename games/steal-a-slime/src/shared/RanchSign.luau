--!strict
--[[
	RanchSign (Instance builders, no Roblox API at load time)

	The plot sign by the bridge, as a ranch sign on one post: a nailed wooden plank with the owner's name carved in
	(the Sign part, drawn by the server's PlotSigns) and, under it on two chains, an enamel plate that shows the lock
	(the LockSign part, drawn by each client's PlotDecor): red with a shut padlock and the time left, or green with
	an open padlock. A free plot shows the plank only.

	  RanchSign.plank(parent, deps, aspect) -> Plank         the plank, filling `parent` (a SurfaceGui)
	  RanchSign.paintPlank(plank, deps, owned)                owner's colours or the free plot's
	  RanchSign.plate(parent, deps, aspect) -> Plate          chains + plate, filling `parent`
	  RanchSign.paintPlate(plate, deps, locked, big, small)   red / green, padlock shut / open, the two lines

	Sizes are scale fractions of the part's face; `aspect` is that face's width / height (WorldLayout.NAME_BOARD /
	LOCK_SIGN), so nails, rim and padlock come out round and even. px values are at PIXELS_PER_STUD. `deps` ({ Instance, Enum, UDim, UDim2, Color3, ColorSequence, ColorSequenceKeypoint }) is the
	Roblox globals in the game and @lune/roblox's in tests.
]]

export type Deps = {
	Instance: any,
	Enum: any,
	UDim: any,
	UDim2: any,
	Color3: any,
	ColorSequence: any,
	ColorSequenceKeypoint: any,
}
export type Plank = { frame: any, title: any, stats: any }
export type Plate = { root: any, plate: any, shackle: any, big: any, small: any }

local RanchSign = {}

RanchSign.PIXELS_PER_STUD = 50
RanchSign.PLANK = "Plank"
RanchSign.PLATE = "Plate"

local function rgb(r: number, g: number, b: number): { number }
	return table.freeze({ r, g, b })
end

RanchSign.COLORS = table.freeze({
	wood = rgb(138, 86, 52),
	woodLight = rgb(150, 98, 61),
	woodDark = rgb(122, 74, 44),
	edge = rgb(67, 38, 15), -- the plank's outline
	carve = rgb(58, 31, 11), -- the name's carved edge
	name = rgb(255, 231, 189),
	stats = rgb(246, 217, 168),
	freeName = rgb(232, 206, 166), -- a free plot's plank reads quieter
	nail = rgb(206, 200, 188),
	chain = rgb(140, 146, 152),
	locked = rgb(211, 58, 74), -- the plate's enamel
	open = rgb(51, 165, 86),
	rim = rgb(255, 246, 234), -- the plate's white rim, the padlock and the text
	plateEdge = rgb(60, 20, 26),
})

-- Boxes { x, y, w, h } as fractions of the face.
RanchSign.PLANK_BOX = table.freeze({
	title = table.freeze({ 0.08, 0.14, 0.84, 0.46 }),
	stats = table.freeze({ 0.08, 0.62, 0.84, 0.24 }),
	nails = table.freeze({ 0.045, 0.955 }), -- nail centres x, at y 0.2
	nail = 0.14, -- nail size, fraction of the plank's height
	corner = 0.12,
	stroke = 5, -- px
})
RanchSign.PLATE_BOX = table.freeze({
	plate = table.freeze({ 0.13, 0.17, 0.74, 0.83 }), -- the plate under its chains
	chains = table.freeze({ 0.21, 0.79 }), -- chain centres x
	chainWidth = 0.022,
	links = 3, -- links per chain, from the top of the face to the plate
	padlock = table.freeze({ 0.06, 0.17, 0.27, 0.66 }), -- inside the plate
	small = table.freeze({ 0.37, 0.14, 0.58, 0.25 }), -- "Locked" / "stealable!"
	big = table.freeze({ 0.37, 0.38, 0.58, 0.5 }), -- the time / "Open"
	corner = 0.22,
	rim = 4, -- px, the white rim inside the plate's edge
	rimInset = 0.05, -- fraction of the plate's height
	stroke = 3, -- px, the plate's dark outer edge
	shackleStroke = 7, -- px
})

local function color(deps: Deps, c: { number }): any
	return deps.Color3.fromRGB(c[1], c[2], c[3])
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

local function corner(deps: Deps, parent: any, scale: number)
	make(deps, "UICorner", { CornerRadius = deps.UDim.new(scale, 0) }, parent)
end

local function label(deps: Deps, parent: any, name: string, font: any, rgbColor: { number }, b: { number }): any
	local l = make(deps, "TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = font,
		TextScaled = true,
		TextColor3 = color(deps, rgbColor),
		Text = "",
		ZIndex = 3,
	}, parent)
	place(deps, l, b)
	return l
end

-- The plank, filling `parent`; finds an existing one first, so callers stay idempotent.
function RanchSign.plank(parent: any, deps: Deps, aspect: number): Plank
	local C, B = RanchSign.COLORS, RanchSign.PLANK_BOX
	local frame = parent:FindFirstChild(RanchSign.PLANK)
	if not frame then
		frame = make(deps, "Frame", {
			Name = RanchSign.PLANK,
			BackgroundColor3 = deps.Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = deps.UDim2.fromScale(1, 1),
		}, parent)
		corner(deps, frame, B.corner)
		make(deps, "UIStroke", {
			Color = color(deps, C.edge),
			Thickness = B.stroke,
			ApplyStrokeMode = deps.Enum.ApplyStrokeMode.Border,
		}, frame)
		-- The grain: light and dark bands across the plank.
		local K = deps.ColorSequenceKeypoint
		make(deps, "UIGradient", {
			Name = "Grain",
			Rotation = 90,
			Color = deps.ColorSequence.new({
				K.new(0, color(deps, C.woodLight)),
				K.new(0.3, color(deps, C.wood)),
				K.new(0.33, color(deps, C.woodDark)),
				K.new(0.36, color(deps, C.wood)),
				K.new(0.68, color(deps, C.woodLight)),
				K.new(0.71, color(deps, C.woodDark)),
				K.new(1, color(deps, C.wood)),
			}),
		}, frame)
		for i, x in B.nails do
			local nail = make(deps, "Frame", {
				Name = `Nail{i}`,
				BackgroundColor3 = color(deps, C.nail),
				BorderSizePixel = 0,
				ZIndex = 2,
			}, frame)
			local w = B.nail / aspect
			nail.Position = deps.UDim2.fromScale(x - w / 2, 0.2 - B.nail / 2)
			nail.Size = deps.UDim2.fromScale(w, B.nail)
			corner(deps, nail, 1)
		end
		local title = label(deps, frame, "Title", deps.Enum.Font.LuckiestGuy, C.name, B.title)
		make(deps, "UIStroke", {
			Name = "Carve",
			Color = color(deps, C.carve),
			Thickness = 3,
			ApplyStrokeMode = deps.Enum.ApplyStrokeMode.Contextual,
			LineJoinMode = deps.Enum.LineJoinMode.Round,
		}, title)
		label(deps, frame, "Stats", deps.Enum.Font.DenkOne, C.stats, B.stats)
	end
	return { frame = frame, title = frame:FindFirstChild("Title"), stats = frame:FindFirstChild("Stats") }
end

-- An owned plot's name is bright cream; a free plot's quieter.
function RanchSign.paintPlank(plank: Plank, deps: Deps, owned: boolean)
	local C = RanchSign.COLORS
	plank.title.TextColor3 = color(deps, if owned then C.name else C.freeName)
end

-- The chains and the plate, filling `parent`; finds an existing one first.
function RanchSign.plate(parent: any, deps: Deps, aspect: number): Plate
	local C, B = RanchSign.COLORS, RanchSign.PLATE_BOX
	local root = parent:FindFirstChild(RanchSign.PLATE)
	if not root then
		root = make(deps, "Frame", {
			Name = RanchSign.PLATE,
			BackgroundTransparency = 1,
			Size = deps.UDim2.fromScale(1, 1),
		}, parent)
		local p = B.plate
		for i, x in B.chains do
			for j = 1, B.links do
				local h = p[2] / B.links
				local link = make(deps, "Frame", {
					Name = `Chain{i}Link{j}`,
					BackgroundTransparency = 1,
				}, root)
				link.Position = deps.UDim2.fromScale(x - B.chainWidth / 2, (j - 1) * h - h * 0.15)
				link.Size = deps.UDim2.fromScale(B.chainWidth, h * 1.3)
				corner(deps, link, 1)
				make(deps, "UIStroke", { Color = color(deps, C.chain), Thickness = 3 }, link)
			end
		end
		local plate = make(deps, "Frame", { Name = "Enamel", BorderSizePixel = 0, ZIndex = 1 }, root)
		place(deps, plate, p)
		corner(deps, plate, B.corner)
		make(deps, "UIStroke", {
			Color = color(deps, C.plateEdge),
			Thickness = B.stroke,
			ApplyStrokeMode = deps.Enum.ApplyStrokeMode.Border,
		}, plate)
		local rim = make(deps, "Frame", { Name = "Rim", BackgroundTransparency = 1, ZIndex = 2 }, plate)
		local inset = B.rimInset
		local plateAspect = aspect * p[3] / p[4] -- keeps the rim's inset even on all sides
		place(deps, rim, { inset / plateAspect, inset, 1 - 2 * inset / plateAspect, 1 - 2 * inset })
		corner(deps, rim, B.corner)
		make(deps, "UIStroke", { Color = color(deps, C.rim), Thickness = B.rim }, rim)
		-- The padlock: a body and, behind it, a shackle drawn as a round outline.
		local lock = make(deps, "Frame", { Name = "Padlock", BackgroundTransparency = 1, ZIndex = 3 }, plate)
		place(deps, lock, B.padlock)
		make(deps, "UIAspectRatioConstraint", { AspectRatio = 1 }, lock)
		local shackle = make(deps, "Frame", { Name = "Shackle", BackgroundTransparency = 1, ZIndex = 3 }, lock)
		place(deps, shackle, { 0.2, 0.02, 0.6, 0.66 })
		corner(deps, shackle, 1)
		make(deps, "UIStroke", { Color = color(deps, C.rim), Thickness = B.shackleStroke }, shackle)
		local body = make(deps, "Frame", {
			Name = "Body",
			BackgroundColor3 = color(deps, C.rim),
			BorderSizePixel = 0,
			ZIndex = 4,
		}, lock)
		place(deps, body, { 0.08, 0.44, 0.84, 0.56 })
		corner(deps, body, 0.22)
		label(deps, plate, "Small", deps.Enum.Font.DenkOne, C.rim, B.small)
		label(deps, plate, "Big", deps.Enum.Font.DenkOne, C.rim, B.big)
	end
	local plate = root:FindFirstChild("Enamel")
	local lock = plate:FindFirstChild("Padlock")
	return {
		root = root,
		plate = plate,
		shackle = lock:FindFirstChild("Shackle"),
		big = plate:FindFirstChild("Big"),
		small = plate:FindFirstChild("Small"),
	}
end

-- Red with the shackle shut, or green with it lifted open; `big` / `small` are the plate's two lines.
function RanchSign.paintPlate(plate: Plate, deps: Deps, locked: boolean, big: string, small: string)
	local C = RanchSign.COLORS
	local enamel = color(deps, if locked then C.locked else C.open)
	if plate.plate.BackgroundColor3 ~= enamel then
		plate.plate.BackgroundColor3 = enamel
		-- Open: the shackle lifts a little and slides off to the right.
		plate.shackle.Position = if locked then deps.UDim2.fromScale(0.2, 0.02) else deps.UDim2.fromScale(0.4, -0.06)
	end
	if plate.big.Text ~= big then
		plate.big.Text = big
	end
	if plate.small.Text ~= small then
		plate.small.Text = small
	end
end

return table.freeze(RanchSign)
