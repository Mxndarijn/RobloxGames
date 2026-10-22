--!strict
--[[
	GooBoard (Instance builders, no Roblox API at load time)

	The Goo board the world signs share (canvas GooWorldSigns): a glass card with an Ink outline and, on top,
	a coloured band that drips goo into the empty strip under it: each drip one finger of goo with a round end.
	PlotSigns draws it on a plot's Sign (mint band, or no band on an empty plot) and PodiumRigs on the podium
	name boards (gold band). Everything is sized by scale, so the same board fits a SurfaceGui or a
	BillboardGui of any size; text goes on top through GooBoard.text.

	`deps` ({ Instance, Enum, UDim, UDim2, Color3 }) is the Roblox globals in the game and @lune/roblox's in tests.
]]

local GooPalette = if script then require(script.Parent.GooPalette) else require("./GooPalette")

export type Deps = { Instance: any, Enum: any, UDim: any, UDim2: any, Color3: any }
export type Drip = { x: number, w: number, len: number } -- fractions of the card: centre x, drop width, neck length
export type Spec = {
	band: number, -- band height, fraction of the card
	radius: number, -- corner radius, fraction of the card's shorter side
	drips: { Drip },
	stroke: number, -- px Ink outline round the card
	glassTransparency: number,
}

local GooBoard = {}

GooBoard.CARD = "GooCard"

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

local function round(deps: Deps, parent: any, scale: number)
	make(deps, "UICorner", { CornerRadius = deps.UDim.new(scale, 0) }, parent)
end

-- Where a drip's drop hangs: its top-left corner and size as fractions of the card (pure; the spec checks that
-- every drip stays clear of the text under the band).
function GooBoard.dripBox(spec: Spec, d: Drip, aspect: number): (number, number, number, number)
	local dropH = d.w * aspect -- a round drop: as tall as it is wide in px
	return d.x - d.w / 2, spec.band + d.len, d.w, dropH
end

-- The lowest point any goo reaches, as a fraction of the card height, for a card `aspect` = width / height.
function GooBoard.gooBottom(spec: Spec, aspect: number): number
	local bottom = spec.band
	for _, d in spec.drips do
		local _, y, _, h = GooBoard.dripBox(spec, d, aspect)
		bottom = math.max(bottom, y + h)
	end
	return bottom
end

-- Builds the board under `parent` (a SurfaceGui, BillboardGui or Frame) and returns the card frame. The band
-- is the card's child "Band"; GooBoard.paint colours or hides it. `aspect` is the board's width / height, so
-- the drops come out round.
function GooBoard.build(parent: any, deps: Deps, spec: Spec, aspect: number): any
	local card = make(deps, "Frame", {
		Name = GooBoard.CARD,
		BackgroundColor3 = color(deps, GooPalette.Bg),
		BackgroundTransparency = spec.glassTransparency,
		BorderSizePixel = 0,
		Size = deps.UDim2.fromScale(1, 1),
	}, parent)
	round(deps, card, spec.radius)
	make(deps, "UIStroke", {
		Color = color(deps, GooPalette.Ink),
		Thickness = spec.stroke,
		ApplyStrokeMode = deps.Enum.ApplyStrokeMode.Border,
	}, card)
	local band = make(deps, "Frame", {
		Name = "Band",
		BorderSizePixel = 0,
		Size = deps.UDim2.fromScale(1, spec.band),
	}, card)
	round(deps, band, spec.radius / spec.band) -- the card's corner, measured against the band's shorter side
	-- The band's lower corners are square: a foot covers them, the drips hang under it.
	make(deps, "Frame", {
		Name = "Foot",
		BorderSizePixel = 0,
		Position = deps.UDim2.fromScale(0, 0.5),
		Size = deps.UDim2.fromScale(1, 0.5),
	}, band)
	local edge = make(deps, "Frame", {
		Name = "Goo",
		BackgroundTransparency = 1,
		Position = deps.UDim2.fromScale(0, 1),
		Size = deps.UDim2.fromScale(1, 1 / spec.band), -- the card's height, so fractions below read as card fractions
	}, band)
	for i, d in spec.drips do
		-- One finger of goo whose round end is the drop (GooBoard.dripBox); its round top hides in the band.
		local x, y, w, h = GooBoard.dripBox(spec, d, aspect)
		local drip = make(deps, "Frame", {
			Name = `Drip{i}`,
			BorderSizePixel = 0,
			Position = deps.UDim2.fromScale(x, -h),
			Size = deps.UDim2.fromScale(w, y - spec.band + h * 2),
		}, edge)
		round(deps, drip, 1)
	end
	return card
end

-- Colours the band and its goo `rgb`, or hides it (nil): an empty plot's sign is plain glass.
function GooBoard.paint(card: any, deps: Deps, rgb: { number }?)
	local band = card:FindFirstChild("Band")
	if not band then
		return
	end
	band.Visible = rgb ~= nil
	if not rgb then
		return
	end
	local c = color(deps, rgb)
	for _, piece in { band, table.unpack(band:GetDescendants()) } do
		if piece:IsA("Frame") and piece.Name ~= "Goo" then
			piece.BackgroundColor3 = c
		end
	end
end

-- A Fredoka label for a board: scaled text in `rgb`, outlined in Ink when `outline` is set (one UIStroke,
-- Contextual so it edges the glyphs). Finds an existing child of that name first, so callers stay idempotent.
function GooBoard.text(parent: any, deps: Deps, name: string, rgb: { number }, outline: number?): any
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local label = make(deps, "TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = deps.Enum.Font.FredokaOne,
		TextScaled = true,
		TextColor3 = color(deps, rgb),
		Text = "",
		ZIndex = 2, -- over the band and its goo
	}, parent)
	if outline then
		make(deps, "UIStroke", {
			Name = "Outline",
			Color = color(deps, GooPalette.Ink),
			Thickness = outline,
			ApplyStrokeMode = deps.Enum.ApplyStrokeMode.Contextual,
			LineJoinMode = deps.Enum.LineJoinMode.Round,
		}, label)
	end
	return label
end

return table.freeze(GooBoard)
