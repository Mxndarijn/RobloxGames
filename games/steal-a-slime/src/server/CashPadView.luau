--!strict
--[[
	CashPadView (Roblox adapter, FEATURES.CashPads, contract/cash-pads.md)

	Keeps one gold disc ("CashPad", under each Pad_<j>) on every owned plot's pads that have a slime or a pile, with a
	BillboardGui counter showing the pile (CashPads.label), and turns players standing on a disc into
	CashPadService.touch calls. The owner's collect flashes "+$X" on the counter for FLASH_SECONDS. Text and
	transparency are written only when they change. Holds no rules: who may collect is CashPadService's call.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashPadService = require(script.Parent.CashPadService)
local CashPads = require(ReplicatedStorage.Shared.CashPads)
local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local World = require(script.Parent.World)
local WorldView = require(script.Parent.WorldView)

local LOOK = table.freeze({
	disc = Color3.fromRGB(255, 200, 40),
	text = Color3.fromRGB(255, 255, 255),
	stroke = Color3.fromRGB(60, 40, 0),
	full = Color3.fromRGB(255, 214, 64),
	flash = Color3.fromRGB(120, 255, 150),
	rim = Color3.fromRGB(176, 120, 10),
	rimExtra = 0.3, -- studs the rim sticks out past the disc
	labelSize = UDim2.fromOffset(190, 46),
	labelLift = 3.2, -- studs above the disc
	signSize = UDim2.fromScale(1, 1),
	font = Enum.Font.FredokaOne,
})
local FLASH_SECONDS = 1.2

type Disc = {
	plotIndex: number,
	pad: number,
	part: BasePart,
	rim: BasePart,
	sign: SurfaceGui,
	label: TextLabel,
	text: string,
	shown: boolean,
	flashUntil: number,
}

export type State = {
	discs: { [string]: Disc }, -- "plot|pad"
	nags: CashPadService.Nags,
}

local CashPadView = {}

function CashPadView.new(): State
	return { discs = {}, nags = {} }
end

local function key(plotIndex: number, pad: number): string
	return `{plotIndex}|{pad}`
end

local function build(pad: BasePart, plotIndex: number, j: number): Disc
	local c = Config.CASH_PAD
	local part = Instance.new("Part")
	part.Name = "CashPad"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(c.HEIGHT, c.RADIUS * 2, c.RADIUS * 2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = LOOK.disc
	part.Transparency = 1
	local rim = Instance.new("Part")
	rim.Name = "Rim"
	rim.Shape = Enum.PartType.Cylinder
	rim.Size = Vector3.new(c.HEIGHT * 0.6, (c.RADIUS + LOOK.rimExtra) * 2, (c.RADIUS + LOOK.rimExtra) * 2)
	rim.Anchored = true
	rim.CanCollide = false
	rim.CanQuery = false
	rim.CanTouch = false
	rim.CastShadow = false
	rim.Material = Enum.Material.SmoothPlastic
	rim.Color = LOOK.rim
	rim.Transparency = 1
	rim.Parent = part
	-- A "$" on the top face (the cylinder's +X points up, see discCFrame).
	local top = Instance.new("SurfaceGui")
	top.Name = "Sign"
	top.Face = Enum.NormalId.Right
	top.LightInfluence = 0
	top.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	top.PixelsPerStud = 40
	top.Parent = part
	local dollar = Instance.new("TextLabel")
	dollar.BackgroundTransparency = 1
	dollar.Size = LOOK.signSize
	dollar.Font = LOOK.font
	dollar.TextScaled = true
	dollar.Text = "$"
	dollar.TextColor3 = LOOK.rim
	dollar.Parent = top
	local gui = Instance.new("BillboardGui")
	gui.Name = "CashPadLabel"
	gui.Size = LOOK.labelSize
	gui.StudsOffsetWorldSpace = Vector3.new(0, LOOK.labelLift, 0)
	gui.MaxDistance = c.LABEL_DISTANCE
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = LOOK.font
	label.TextScaled = true
	label.TextColor3 = LOOK.text
	local stroke = Instance.new("UIStroke")
	stroke.Color = LOOK.stroke
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Text = ""
	label.Parent = gui
	part.Parent = pad
	return {
		plotIndex = plotIndex,
		pad = j,
		part = part,
		rim = rim,
		sign = top,
		label = label,
		text = "",
		shown = false,
		flashUntil = 0,
	}
end

-- Disc frame: flat, LIFT studs above the pad's bottom and FRONT studs in front of the pad (the pad's -Z faces the jar).
local function discCFrame(pad: BasePart): CFrame
	local c = Config.CASH_PAD
	return pad.CFrame
		* CFrame.new(0, -pad.Size.Y / 2 + c.LIFT + c.HEIGHT / 2, -c.FRONT)
		* CFrame.Angles(0, 0, math.rad(90))
end

local function setText(disc: Disc, text: string, color: Color3)
	if disc.text ~= text then
		disc.text = text
		disc.label.Text = text
	end
	if disc.label.TextColor3 ~= color then
		disc.label.TextColor3 = color
	end
end

local function setShown(disc: Disc, shown: boolean)
	if disc.shown ~= shown then
		disc.shown = shown
		disc.part.Transparency = if shown then 0 else 1
		disc.rim.Transparency = if shown then 0 else 1
		disc.sign.Enabled = shown
		disc.label.Visible = shown
	end
end

-- Builds, places and labels every disc; drops discs of plots that lost their owner or pads that are gone.
function CashPadView.sync(state: State, world: World.World, now: number)
	local seen: { [string]: boolean } = {}
	for plotIndex = 1, world.plotCount do
		local ownerId = world.plots[plotIndex]
		local owner = if ownerId then World.session(world, ownerId) else nil
		if owner then
			local data = owner.data
			for j = 1, data.padsUnlocked do
				local pad = WorldView.pad(plotIndex, j)
				local pile = CashPads.pile(data, j)
				local wanted = pad ~= nil and (PlayerData.slimeOnPad(data, j) ~= nil or pile >= 1)
				if pad and wanted then
					local k = key(plotIndex, j)
					seen[k] = true
					local old = state.discs[k]
					local disc: Disc
					if old and old.part.Parent == pad then
						disc = old
					else
						if old then
							old.part:Destroy()
						end
						disc = build(pad, plotIndex, j)
						state.discs[k] = disc
					end
					local frame = discCFrame(pad)
					if disc.part.CFrame ~= frame then
						disc.part.CFrame = frame
						disc.rim.CFrame = frame * CFrame.new(-Config.CASH_PAD.HEIGHT * 0.2, 0, 0)
					end
					setShown(disc, true)
					if now >= disc.flashUntil then
						local full = CashPads.full(data, j)
						setText(disc, CashPads.label(pile, full), if full then LOOK.full else LOOK.text)
					end
				end
			end
		end
	end
	for k, disc in state.discs do
		if not seen[k] then
			disc.part:Destroy()
			state.discs[k] = nil
		end
	end
end

-- Every player standing on a shown disc touches it (CashPadService.touch); the owner's collect flashes the counter.
function CashPadView.step(state: State, world: World.World, now: number)
	for _, player in Players:GetPlayers() do
		local root = WorldView.rootPart(player)
		if root then
			local p = root.Position
			for _, disc in state.discs do
				local d = disc.part.Position
				if disc.shown and CashPads.touching(p.X - d.X, p.Y - d.Y, p.Z - d.Z) then
					local paid = CashPadService.touch(world, state.nags, player.UserId, disc.plotIndex, disc.pad, now)
					if paid > 0 then
						disc.flashUntil = now + FLASH_SECONDS
						setText(disc, `+${Economy.formatNumber(paid)}`, LOOK.flash)
					end
				end
			end
		end
	end
end

-- Forgets a leaving player's nag timer.
function CashPadView.forget(state: State, userId: number)
	CashPadService.forget(state.nags, userId)
end

return CashPadView
