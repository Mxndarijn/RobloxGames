--!strict
--[[
	PlotSigns (Roblox adapter + pure text)

	Writes the owner and stats onto each plot's `Sign` part (the name board on the lock sign's post). The static
	world (world/Plots.rbxmx, WorldLayout.NAME_BOARD) ships the Sign as a bare board with no SurfaceGui, so the
	server adds one on its Front face (facing out of the jar) and draws the Goo board on it (GooBoard): an owned
	plot gets a mint band with the owner's name in Ink and its income, rebirths and steals under it; a free plot
	is plain glass with "Plot n" and "Empty plot". No Back face: it lies against the glass. Server-side so the
	text replicates to every client.

	PlotSigns.lines(plotIndex, owner?) -> { title, stats, owned }   -- pure
	PlotSigns.ensure(sign, deps?) -> { TextLabel }                  -- idempotent
	PlotSigns.apply(sign, lines, deps?)                             -- writes on change

	`deps` ({ Instance, Enum, UDim, UDim2, Color3 }) defaults to the Roblox globals; Lune tests pass @lune/roblox's.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local GooPalette = if Shared then require(Shared.GooPalette) else require("../shared/GooPalette")
local GooBoard = if Shared then require(Shared.GooBoard) else require("../shared/GooBoard")
local NumberFormat = if Shared then require(Shared.NumberFormat) else require("../shared/NumberFormat")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")

export type Lines = { title: string, stats: string, owned: boolean }
export type Owner = { name: string, data: PlayerData.Data } -- reads slimes, trophies, rebirths, totalStolen
type Deps = GooBoard.Deps

local PlotSigns = {}

PlotSigns.GUI_PREFIX = "SignGui"
PlotSigns.FACES = table.freeze({ "Front" })
PlotSigns.PIXELS_PER_STUD = 50
-- The name board's width / height (WorldLayout.NAME_BOARD, 12 x 3.6 studs), so the goo drops come out round.
PlotSigns.ASPECT = 12 / 3.6

-- The board: a mint band over the top half, a short lip and a drip at each end, clear of the stats line.
PlotSigns.BOARD = table.freeze({
	band = 0.46,
	radius = 0.24,
	lip = 0.05,
	scallops = 14,
	drips = table.freeze({
		table.freeze({ x = 0.05, w = 0.035, len = 0.08 }),
		table.freeze({ x = 0.935, w = 0.028, len = 0.04 }),
	}),
	stroke = 6, -- px at PIXELS_PER_STUD
	glassTransparency = 0,
} :: GooBoard.Spec)

-- Text boxes as fractions of the board { x, y, w, h }: on an owned plot the name sits in the band, on a free
-- plot "Plot n" moves down into the glass.
PlotSigns.TEXT = table.freeze({
	ownedTitle = table.freeze({ 0.06, 0.07, 0.88, 0.33 }),
	freeTitle = table.freeze({ 0.1, 0.12, 0.8, 0.42 }),
	stats = table.freeze({ 0.1, 0.6, 0.8, 0.28 }),
})

local function plural(n: number, word: string): string
	return `{NumberFormat.short(n)} {word}{if n == 1 then "" else "s"}`
end

function PlotSigns.lines(plotIndex: number, owner: Owner?): Lines
	if not owner then
		return { title = `Plot {plotIndex}`, stats = "Empty plot", owned = false }
	end
	local data = owner.data
	return {
		title = `{owner.name}'s plot`,
		stats = `+{NumberFormat.rate(PlayerData.incomePerSecond(data))}, {plural(data.rebirths, "rebirth")}, {plural(
			data.totalStolen,
			"steal"
		)}`,
		owned = true,
	}
end

local function defaults(): Deps
	return { Instance = Instance, Enum = Enum, UDim = UDim, UDim2 = UDim2, Color3 = Color3 }
end

local function place(deps: Deps, label: any, box: { number })
	label.Position = deps.UDim2.fromScale(box[1], box[2])
	label.Size = deps.UDim2.fromScale(box[3], box[4])
end

local function color(deps: Deps, c: { number }): any
	return deps.Color3.fromRGB(c[1], c[2], c[3])
end

-- Makes sure `sign` has a SurfaceGui with the board and its Title / Stats labels on each face; returns every
-- label (Title, Stats per face).
function PlotSigns.ensure(sign: Instance, deps: Deps?): { TextLabel }
	local d = deps or defaults()
	local labels = {}
	for _, face in PlotSigns.FACES do
		local name = PlotSigns.GUI_PREFIX .. face
		local gui = sign:FindFirstChild(name)
		if not gui then
			local created = d.Instance.new("SurfaceGui")
			created.Name = name
			created.Face = d.Enum.NormalId[face]
			created.SizingMode = d.Enum.SurfaceGuiSizingMode.PixelsPerStud
			created.PixelsPerStud = PlotSigns.PIXELS_PER_STUD
			created.LightInfluence = 0
			created.Parent = sign
			gui = created
		end
		local card = (gui :: Instance):FindFirstChild(GooBoard.CARD)
			or GooBoard.build(gui, d, PlotSigns.BOARD, PlotSigns.ASPECT)
		table.insert(labels, GooBoard.text(card, d, "Title", GooPalette.Ink))
		local stats = GooBoard.text(card, d, "Stats", GooPalette.Text, 3)
		place(d, stats, PlotSigns.TEXT.stats)
		table.insert(labels, stats)
	end
	return labels
end

function PlotSigns.apply(sign: Instance, lines: Lines, deps: Deps?)
	local d = deps or defaults()
	for _, text in PlotSigns.ensure(sign, d) do
		local want = if text.Name == "Title" then lines.title else lines.stats
		if text.Text == want then
			continue
		end
		text.Text = want
		local card = text.Parent :: Instance
		if text.Name == "Title" then
			-- Owned: Ink on the mint band. Free: white on the glass, no band.
			GooBoard.paint(card, d, if lines.owned then GooPalette.Mint else nil)
			place(d, text, if lines.owned then PlotSigns.TEXT.ownedTitle else PlotSigns.TEXT.freeTitle)
			text.TextColor3 = color(d, if lines.owned then GooPalette.Ink else GooPalette.Text)
		else
			text.TextColor3 = color(d, if lines.owned then GooPalette.Text else GooPalette.MutedWell)
		end
	end
end

return PlotSigns
