--!strict
--[[
	PlotSigns (Roblox adapter + pure text)

	Writes the owner and stats onto each plot's `Sign` part: the name plank of the ranch sign by the bridge
	(shared/RanchSign; the lock plate hangs under it on the LockSign, drawn by each client). The static world
	(world/Plots.rbxmx, WorldLayout.NAME_BOARD) ships the Sign as an invisible board with no SurfaceGui, so the server
	adds one on its Front face (facing out of the jar) and draws the plank on it: the owner's name carved in, their
	income, rebirths and steals under it; a free plot shows "Plot n" and "Empty plot". No Back face: it lies against
	the glass. Server-side so the text replicates to every client.

	PlotSigns.lines(plotIndex, owner?, income?) -> { title, stats, owned }   -- pure
	PlotSigns.ensure(sign, deps?) -> { TextLabel }                  -- idempotent
	PlotSigns.apply(sign, lines, deps?)                             -- writes on change

	`deps` (RanchSign.Deps) defaults to the Roblox globals; Lune tests pass @lune/roblox's.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local NumberFormat = if Shared then require(Shared.NumberFormat) else require("../shared/NumberFormat")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local RanchSign = if Shared then require(Shared.RanchSign) else require("../shared/RanchSign")
local WorldLayout = if Shared
	then require(Shared.Parent.Visuals.WorldLayout)
	else require("../visuals/shared/WorldLayout")

export type Lines = { title: string, stats: string, owned: boolean }
export type Owner = { name: string, data: PlayerData.Data } -- reads slimes, rebirths, totalStolen
type Deps = RanchSign.Deps

local PlotSigns = {}

PlotSigns.GUI_PREFIX = "SignGui"
PlotSigns.FACES = table.freeze({ "Front" })
PlotSigns.PIXELS_PER_STUD = RanchSign.PIXELS_PER_STUD
-- The name board's width / height (round nails).
PlotSigns.ASPECT = WorldLayout.NAME_BOARD.width / WorldLayout.NAME_BOARD.height

local function plural(n: number, word: string): string
	return `{NumberFormat.short(n)} {word}{if n == 1 then "" else "s"}`
end

-- `income` is the owner's income per second as the HUD shows it (World.incomeOf); without it, the plot's
-- full income (PlayerData.incomePerSecond).
function PlotSigns.lines(plotIndex: number, owner: Owner?, income: number?): Lines
	if not owner then
		return { title = `Plot {plotIndex}`, stats = "Empty plot", owned = false }
	end
	local data = owner.data
	return {
		title = `{owner.name}'s plot`,
		stats = `+{NumberFormat.rate(income or PlayerData.incomePerSecond(data))}, {plural(data.rebirths, "rebirth")}, {plural(
			data.totalStolen,
			"steal"
		)}`,
		owned = true,
	}
end

local function defaults(): Deps
	return {
		Instance = Instance,
		Enum = Enum,
		UDim = UDim,
		UDim2 = UDim2,
		Color3 = Color3,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
	}
end

-- Makes sure `sign` has a SurfaceGui with the plank and its Title / Stats labels on each face; returns every
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
		local plank = RanchSign.plank(gui, d, PlotSigns.ASPECT)
		table.insert(labels, plank.title)
		table.insert(labels, plank.stats)
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
		if text.Name == "Title" then
			local frame = text.Parent :: Instance
			RanchSign.paintPlank({ frame = frame, title = text, stats = frame:FindFirstChild("Stats") }, d, lines.owned)
		end
	end
end

return PlotSigns
