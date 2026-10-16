--!strict
--[[
	PlotSigns (Roblox adapter + pure text)

	Writes the owner and stats onto each plot's `Sign` part. The static world
	(world/Plots.rbxmx, WorldLayout) ships the Sign as a bare board with no
	SurfaceGui, so the server adds one on its Front face (the gate board's
	cream face, out of the entrance) with a Title and a Stats TextLabel and
	updates them from the plot's session. No Back face: behind the board is
	the gate beam, and text there floated off the mesh (v28 playtest).
	Server-side so the text replicates to every client.

	PlotSigns.lines(plotIndex, session?) -> { title, stats }   -- pure
	PlotSigns.ensure(sign, deps?) -> { TextLabel }             -- idempotent
	PlotSigns.apply(sign, lines, deps?)                        -- writes on change

	`deps` ({ Instance, Enum, UDim2, Color3 }) defaults to the Roblox globals; Lune tests pass
	@lune/roblox's.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")

export type Lines = { title: string, stats: string }
export type Owner = { name: string, data: PlayerData.Data } -- reads cash, rebirths, totalStolen
type Deps = { Instance: any, Enum: any, UDim2: any, Color3: any }

local PlotSigns = {}

PlotSigns.GUI_PREFIX = "SignGui"
PlotSigns.FACES = table.freeze({ "Front" })
PlotSigns.PIXELS_PER_STUD = 50

local function plural(n: number, word: string): string
	return `{Economy.formatNumber(n)} {word}{if n == 1 then "" else "s"}`
end

function PlotSigns.lines(plotIndex: number, owner: Owner?): Lines
	if not owner then
		return { title = `Plot {plotIndex}`, stats = "Empty plot" }
	end
	local data = owner.data
	return {
		title = `{owner.name}'s Plot`,
		stats = `${Economy.formatNumber(data.cash)}  •  {plural(data.rebirths, "Rebirth")}  •  {plural(
			data.totalStolen,
			"Steal"
		)}`,
	}
end

local function defaults(): Deps
	return { Instance = Instance, Enum = Enum, UDim2 = UDim2, Color3 = Color3 }
end

local function label(gui: Instance, deps: Deps, name: string, y: number, height: number, rgb: { number }): TextLabel
	local text = gui:FindFirstChild(name) :: TextLabel?
	if text then
		return text
	end
	local made = deps.Instance.new("TextLabel")
	made.Name = name
	made.BackgroundTransparency = 1
	made.Position = deps.UDim2.fromScale(0.04, y)
	made.Size = deps.UDim2.fromScale(0.92, height)
	made.Font = deps.Enum.Font.FredokaOne
	made.TextScaled = true
	made.TextColor3 = deps.Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	made.Text = ""
	made.Parent = gui
	return made
end

-- Makes sure `sign` has a SurfaceGui with Title / Stats labels on each face;
-- returns every label (Title, Stats per face).
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
		table.insert(labels, label(gui :: Instance, d, "Title", 0.06, 0.52, { 70, 45, 25 }))
		table.insert(labels, label(gui :: Instance, d, "Stats", 0.6, 0.32, { 40, 120, 60 }))
	end
	return labels
end

function PlotSigns.apply(sign: Instance, lines: Lines, deps: Deps?)
	for _, text in PlotSigns.ensure(sign, deps) do
		local want = if text.Name == "Title" then lines.title else lines.stats
		if text.Text ~= want then
			text.Text = want
		end
	end
end

return PlotSigns
