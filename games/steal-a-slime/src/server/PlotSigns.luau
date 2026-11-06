--!strict
--[[
	PlotSigns (Roblox adapter + pure text)

	Draws each plot's `Sign` by the bridge: the jar's slime mascot peeking over a glass nameplate with the owner's
	name, income, rebirths and steals (shared/MascotSign). The mascot wears the owner's plot theme (PlotSkins);
	a free plot shows "Plot n", "Empty plot" and a pale mascot asleep. The static world (world/Plots.rbxmx,
	WorldLayout.NAME_BOARD) ships the Sign as an invisible board with no SurfaceGui, so the server adds one on its
	Front face (facing out of the jar) and one on its Back face (read from inside the plot). Server-side so it
	replicates to every client.

	PlotSigns.lines(plotIndex, owner?, income?) -> Lines            -- pure
	PlotSigns.ensure(sign, deps?) -> MascotSign.Sign per face      -- idempotent
	PlotSigns.apply(sign, lines, deps?)                             -- writes on change

	`deps` (MascotSign.Deps) defaults to the Roblox globals; Lune tests pass @lune/roblox's.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local MascotSign = if Shared then require(Shared.MascotSign) else require("../shared/MascotSign")
local NumberFormat = if Shared then require(Shared.NumberFormat) else require("../shared/NumberFormat")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local PlotSkins = if Shared then require(Shared.PlotSkins) else require("../shared/PlotSkins")
local WorldText = if script then require(script.Parent.WorldText) else require("./WorldText")

-- MascotSign.Look plus the title and stats as Localize messages (`titleText`, `statsText`; `title` / `stats` are
-- their English).
export type Lines = MascotSign.Look & { titleText: any, statsText: any }
export type Owner = { name: string, data: PlayerData.Data } -- reads slimes, rebirths, totalStolen, the plot skin
type Deps = MascotSign.Deps

local PlotSigns = {}

PlotSigns.GUI_PREFIX = "SignGui"
PlotSigns.FACES = table.freeze({ "Front", "Back" }) -- the same sign both ways: out of the plot and from inside it
PlotSigns.PIXELS_PER_STUD = MascotSign.PIXELS_PER_STUD
PlotSigns.MAX_DISTANCE = 250 -- studs: find a friend's plot from the plaza

-- "1 rebirth" / "2 rebirths": the count key `key`.one / .other with the short number.
local function plural(n: number, key: string): any
	return WorldText.msg(`{key}.{if n == 1 then "one" else "other"}`, { count = NumberFormat.short(n) })
end

local function makeLines(title: any, stats: any, owned: boolean, skin: string?): Lines
	return {
		title = WorldText.english(title),
		stats = WorldText.english(stats),
		titleText = title,
		statsText = stats,
		owned = owned,
		skin = skin,
	}
end

-- `income` is the owner's income per second as the HUD shows it (World.incomeOf); without it, the plot's
-- full income (PlayerData.incomePerSecond). `skin` is the owner's plot theme (the default while
-- FEATURES.PlotSkins is off).
function PlotSigns.lines(plotIndex: number, owner: Owner?, income: number?): Lines
	if not owner then
		return makeLines(
			WorldText.msg("world.sign.plot_number", { number = plotIndex }),
			WorldText.msg("world.sign.empty_plot"),
			false,
			nil
		)
	end
	local data = owner.data
	return makeLines(
		WorldText.msg("world.sign.owner_plot", { name = owner.name }),
		WorldText.msg("world.sign.plot_stats", {
			income = `+{NumberFormat.rate(income or PlayerData.incomePerSecond(data))}`,
			rebirths = plural(data.rebirths, "world.sign.rebirths"),
			steals = plural(data.totalStolen, "world.sign.steals"),
		}),
		true,
		if Config.FEATURES.PlotSkins then PlotSkins.current(data) else Config.PLOT_SKIN_DEFAULT
	)
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

-- Makes sure `sign` has a SurfaceGui with the mascot sign on each face; returns each face's sign.
function PlotSigns.ensure(sign: Instance, deps: Deps?): { MascotSign.Sign }
	local d = deps or defaults()
	local out = {}
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
			created.MaxDistance = PlotSigns.MAX_DISTANCE
			created.Parent = sign
			gui = created
		end
		table.insert(out, MascotSign.build(gui, d))
	end
	return out
end

PlotSigns.PAINTED_ATTRIBUTE = "Painted" -- on each SurfaceGui: the look last painted, so a reconcile that changes nothing writes nothing

function PlotSigns.apply(sign: Instance, lines: Lines, deps: Deps?)
	local key = `{lines.title}|{lines.stats}|{lines.owned}|{lines.skin or ""}`
	local d = deps or defaults()
	for i, face in PlotSigns.ensure(sign, d) do
		local gui = sign:FindFirstChild(PlotSigns.GUI_PREFIX .. PlotSigns.FACES[i]) :: Instance
		if gui:GetAttribute(PlotSigns.PAINTED_ATTRIBUTE) ~= key then
			MascotSign.paint(face, d, lines)
			if lines.titleText then
				WorldText.setMessage(face.title, "Text", lines.titleText)
				WorldText.setMessage(face.stats, "Text", lines.statsText)
			end
			gui:SetAttribute(PlotSigns.PAINTED_ATTRIBUTE, key)
		end
	end
end

return PlotSigns
