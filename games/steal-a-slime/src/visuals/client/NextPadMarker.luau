--!strict
--[[
	NextPadMarker (VisualsClient module)

	On your own plot, the next pad you can buy (the one carrying your enabled BuyPadPrompt) gets a soft mint
	outline and a Goo price tag over it: mint "Buy pad $X" once you can afford it, else an Ink glass
	"Next pad $X" with the price in gold. Look and text live in Visuals.NextPad; this file only builds
	Instances. Reads attributes, the prompt and your leaderstats Cash only; never fires remotes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local GooPalette = require(Shared:WaitForChild("GooPalette"))
local HomePlotMarker = require(script.Parent:WaitForChild("HomePlotMarker"))
local Look = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("NextPad"))

local NextPadMarker = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local MINT, INK, GOLD, WHITE = rgb(GooPalette.Mint), rgb(GooPalette.Ink), rgb(GooPalette.Gold), rgb(GooPalette.White)
local GOLD_HEX = string.format("#%02X%02X%02X", GooPalette.Gold[1], GooPalette.Gold[2], GooPalette.Gold[3])

type Marker = { pad: BasePart, highlight: Highlight, tag: BillboardGui, pill: Frame, text: TextLabel }

local marker: Marker? = nil

local function clear()
	if marker then
		marker.highlight:Destroy()
		marker.tag:Destroy()
		marker = nil
	end
end

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	inst.Parent = parent
	return inst
end

-- What players see of the pad: the pad part is an invisible box, its mesh skin (MeshSwap) is a descendant.
local function visibleOf(pad: BasePart): Instance
	for _, d in pad:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			return d
		end
	end
	return pad
end

local function build(pad: BasePart): Marker
	local L = Look.LOOK
	local highlight = make("Highlight", {
		Name = "NextPadHighlight",
		Adornee = visibleOf(pad),
		FillColor = MINT,
		FillTransparency = L.fillTransparency,
		OutlineColor = MINT,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
	}, pad)
	local tag = make("BillboardGui", {
		Name = "NextPadTag",
		Adornee = pad,
		AlwaysOnTop = false,
		LightInfluence = 0,
		MaxDistance = L.maxDistance,
		Size = UDim2.fromOffset(L.tagW, L.tagH),
		StudsOffsetWorldSpace = Vector3.new(0, L.tagHeight, 0),
		ResetOnSpawn = false,
	}, pad)
	local pill = make("Frame", {
		Name = "Pill",
		Size = UDim2.new(1, -L.stroke * 2, 1, -L.stroke * 2),
		Position = UDim2.fromOffset(L.stroke, L.stroke),
		BorderSizePixel = 0,
	}, tag)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)
	make("UIStroke", { Color = INK, Thickness = L.stroke }, pill)
	local text = make("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.FredokaOne,
		TextSize = L.textSize,
		RichText = true,
	}, pill)
	make("UIStroke", { Name = "TextStroke", Color = INK, Thickness = L.textStroke }, text)
	return { pad = pad, highlight = highlight, tag = tag, pill = pill, text = text }
end

local function paint(m: Marker, t: Look.Tag)
	local L = Look.LOOK
	m.pill.BackgroundColor3 = if t.affordable then MINT else INK
	m.pill.BackgroundTransparency = if t.affordable then 0 else L.glassTransparency
	local stroke = m.text:FindFirstChild("TextStroke") :: UIStroke
	if t.affordable then
		m.text.Text = t.text
		m.text.TextColor3 = INK
		stroke.Enabled = false
	else
		m.text.Text = `{t.verb} <font color="{GOLD_HEX}">{t.price}</font>`
		m.text.TextColor3 = WHITE
		stroke.Enabled = true
	end
	m.highlight.OutlineColor = if t.affordable then MINT else GOLD
	m.highlight.FillColor = m.highlight.OutlineColor
end

-- The pad carrying the local player's enabled BuyPadPrompt on `plot` (the server moves it to the next pad).
local function nextPad(plot: Model, userId: number): BasePart?
	for _, d in plot:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == Constants.BUY_PAD_PROMPT_NAME and d.Enabled then
			local shownTo = d:GetAttribute(Constants.PROMPT_OWNER_ATTRIBUTE)
			local pad = d.Parent
			if (shownTo == nil or shownTo == 0 or shownTo == userId) and pad and pad:IsA("BasePart") then
				return pad
			end
		end
	end
	return nil
end

local function cash(player: Player): number?
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash")
	return if value and value:IsA("ValueBase") then (value :: any).Value else nil
end

local function refresh()
	local player = Players.LocalPlayer
	local plot = HomePlotMarker.ownPlot()
	local pad = if plot and player then nextPad(plot, player.UserId) else nil
	local t = if pad and plot
		then Look.tag(plot:GetAttribute(Constants.PLOT_NEXT_PAD_COST_ATTRIBUTE) :: number?, cash(player))
		else nil
	if not (pad and t) then
		clear()
		return
	end
	if not marker or marker.pad ~= pad or not marker.tag.Parent then
		clear()
		marker = build(pad)
	end
	paint(marker :: Marker, t)
end

function NextPadMarker.start(): () -> ()
	local running = true
	task.spawn(function()
		while running do
			local ok, err = pcall(refresh)
			if not ok then
				warn(`[VisualsClient] next pad marker: {err}`)
			end
			task.wait(Look.POLL)
		end
	end)
	return function()
		running = false
		clear()
	end
end

return NextPadMarker
