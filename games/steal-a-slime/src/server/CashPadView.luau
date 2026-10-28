--!strict
--[[
	CashPadView (Roblox adapter, FEATURES.CashPads, contract/cash-pads.md)

	Keeps one raised gold coin ("CashPad", under each Pad_<j>) on every owned plot's pads that have a slime or a pile.
	Everyone sees it. Its top shows CashPads.face: the amount plus COLLECT while cash waits, a dimmed "$0" when empty,
	and "+$X" in green for CASH_PAD.FLASH_SECONDS after the owner collects. Size, distance and height come per floor
	from CashPads.floorLook. A player who steps onto a coin calls CashPadService.touch once per step-on (not every tick
	while standing). Coins are rebuilt and relabelled at most every CASH_PAD.SYNC_SECONDS, and properties are written
	only when they change. Holds no rules: who may collect is CashPadService's call.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashPadService = require(script.Parent.CashPadService)
local CashPads = require(ReplicatedStorage.Shared.CashPads)
local Config = require(ReplicatedStorage.Shared.Config)
local World = require(script.Parent.World)
local WorldView = require(script.Parent.WorldView)

type Look = { face: Color3, base: Color3, amount: Color3 }

local LOOK = table.freeze({
	waiting = table.freeze({
		face = Color3.fromRGB(226, 178, 52),
		base = Color3.fromRGB(176, 128, 28),
		amount = Color3.fromRGB(60, 36, 0),
	}) :: Look,
	empty = table.freeze({
		face = Color3.fromRGB(150, 132, 92),
		base = Color3.fromRGB(110, 96, 64),
		amount = Color3.fromRGB(70, 60, 40),
	}) :: Look,
	collected = table.freeze({
		face = Color3.fromRGB(226, 178, 52),
		base = Color3.fromRGB(176, 128, 28),
		amount = Color3.fromRGB(20, 120, 50),
	}) :: Look,
	collect = Color3.fromRGB(110, 70, 0), -- the COLLECT word
	stroke = Color3.fromRGB(255, 240, 190), -- light outline round the amount
	faceThickness = 0.04, -- studs: the printed top
	baseThickness = 0.16, -- studs: the raised edge under it
	baseExtra = 0.18, -- studs the edge sticks out past the top (across)
	pixelsPerStud = 60,
	font = Enum.Font.FredokaOne,
	-- Text boxes as fractions of the coin's top: the amount sits higher when COLLECT is under it.
	amountSize = UDim2.fromScale(0.84, 0.34),
	amountWith = UDim2.fromScale(0.08, 0.24),
	amountAlone = UDim2.fromScale(0.08, 0.33),
	collectSize = UDim2.fromScale(0.6, 0.14),
	collectAt = UDim2.fromScale(0.2, 0.6),
})

type Disc = {
	plotIndex: number,
	pad: number,
	diameter: number,
	part: BasePart, -- the printed top; Position is the touch centre
	base: BasePart,
	amount: TextLabel,
	collect: TextLabel,
	state: string,
	text: string,
	flashUntil: number,
	paid: number,
}

type Bounds = { x0: number, x1: number, z0: number, z1: number }

export type State = {
	discs: { [string]: Disc }, -- "plot|pad"
	bounds: { [number]: Bounds }, -- plotIndex -> flat box round its coins (touch pre-check)
	standing: { [number]: { [string]: boolean } }, -- userId -> coins they stood on at the last step
	nags: CashPadService.Nags,
	syncedAt: number,
}

local CashPadView = {}

function CashPadView.new(): State
	return { discs = {}, bounds = {}, standing = {}, nags = {}, syncedAt = -math.huge }
end

local function key(plotIndex: number, pad: number): string
	return `{plotIndex}|{pad}`
end

local function cylinder(name: string, thickness: number, diameter: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(thickness, diameter, diameter)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	return part
end

local function text(name: string, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = LOOK.font
	label.TextScaled = true
	label.Parent = parent
	return label
end

local function build(pad: BasePart, plotIndex: number, j: number): Disc
	local diameter = CashPads.floorLook(j).diameter
	local part = cylinder("CashPad", LOOK.faceThickness, diameter)
	local base = cylinder("Base", LOOK.baseThickness, diameter + LOOK.baseExtra)
	base.Parent = part
	-- The printed top: the cylinder's +X points up (coinFrames), so the Right face is the top.
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Right
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = LOOK.pixelsPerStud
	gui.Parent = part
	local amount = text("Amount", gui)
	amount.Size = LOOK.amountSize
	local stroke = Instance.new("UIStroke")
	stroke.Color = LOOK.stroke
	stroke.Thickness = 2
	stroke.Parent = amount
	local collect = text("Collect", gui)
	collect.Size = LOOK.collectSize
	collect.Position = LOOK.collectAt
	collect.Text = "COLLECT"
	collect.TextColor3 = LOOK.collect
	part.Parent = pad
	return {
		plotIndex = plotIndex,
		pad = j,
		diameter = diameter,
		part = part,
		base = base,
		amount = amount,
		collect = collect,
		state = "",
		text = "",
		flashUntil = 0,
		paid = 0,
	}
end

-- The coin's top and raised edge, flat on that floor's walk surface, CashPads.floorLook(j).front studs in front of the
-- pad (the pad's -Z faces the jar), turned so the text reads for a player facing the slime.
local function coinFrames(pad: BasePart, j: number): (CFrame, CFrame)
	local look = CashPads.floorLook(j)
	local bottom = -pad.Size.Y / 2 + look.lift
	local turn = CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(90), 0, 0)
	local face = pad.CFrame * CFrame.new(0, bottom + LOOK.baseThickness + LOOK.faceThickness / 2, -look.front) * turn
	local base = pad.CFrame * CFrame.new(0, bottom + LOOK.baseThickness / 2, -look.front) * turn
	return face, base
end

local function setFace(disc: Disc, face: CashPads.Face)
	if disc.state ~= face.state then
		disc.state = face.state
		local look: Look = (LOOK :: any)[face.state]
		disc.part.Color = look.face
		disc.base.Color = look.base
		disc.amount.TextColor3 = look.amount
		disc.collect.Visible = face.collect
		disc.amount.Position = if face.collect then LOOK.amountWith else LOOK.amountAlone
	end
	if disc.text ~= face.amount then
		disc.text = face.amount
		disc.amount.Text = face.amount
	end
end

-- Builds, places and labels every coin; drops coins of plots that lost their owner or pads that are gone.
function CashPadView.sync(state: State, world: World.World, now: number)
	local c = Config.CASH_PAD
	if now - state.syncedAt < c.SYNC_SECONDS then
		return
	end
	state.syncedAt = now
	local seen: { [string]: boolean } = {}
	table.clear(state.bounds)
	for plotIndex = 1, world.plotCount do
		local ownerId = world.plots[plotIndex]
		local owner = if ownerId then World.session(world, ownerId) else nil
		if owner then
			local data = owner.data
			local pads = WorldView.pads(plotIndex) -- one scan of the plot's children
			local slimes: { [number]: any } = {}
			for _, slime in data.slimes do
				if slime.pad then
					slimes[slime.pad] = slime
				end
			end
			local box: Bounds? = nil
			for j = 1, data.padsUnlocked do
				local pad = pads[j]
				local pile = CashPads.pile(data, j)
				local slime = slimes[j]
				if pad and (slime ~= nil or pile >= 1) then
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
					local face, baseFrame = coinFrames(pad, j)
					if disc.part.CFrame ~= face then
						disc.part.CFrame = face
						disc.base.CFrame = baseFrame
					end
					setFace(disc, CashPads.face(pile, now < disc.flashUntil, disc.paid))
					local at = face.Position
					if box then
						box.x0, box.x1 = math.min(box.x0, at.X), math.max(box.x1, at.X)
						box.z0, box.z1 = math.min(box.z0, at.Z), math.max(box.z1, at.Z)
					else
						box = { x0 = at.X, x1 = at.X, z0 = at.Z, z1 = at.Z }
					end
				end
			end
			if box then
				state.bounds[plotIndex] = box
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

-- A player who steps onto a coin touches it once (CashPadService.touch); the owner's collect flashes the
-- counter. Standing still on it does nothing more until they step off and back on.
function CashPadView.step(state: State, world: World.World, now: number)
	local c = Config.CASH_PAD
	for _, player in Players:GetPlayers() do
		local userId = player.UserId
		local was = state.standing[userId]
		local root = WorldView.rootPart(player)
		local on: { [string]: boolean }? = nil
		if root then
			local p = root.Position
			for k, disc in state.discs do
				local box = state.bounds[disc.plotIndex]
				local reach = disc.diameter / 2 + c.TOUCH_SLACK
				local near = box ~= nil
					and p.X >= box.x0 - reach
					and p.X <= box.x1 + reach
					and p.Z >= box.z0 - reach
					and p.Z <= box.z1 + reach
				local d = disc.part.Position
				if near and CashPads.touching(p.X - d.X, p.Y - d.Y, p.Z - d.Z, disc.diameter) then
					local hits: { [string]: boolean } = on or {}
					hits[k] = true
					on = hits
					if not (was and was[k]) then
						local paid = CashPadService.touch(world, state.nags, userId, disc.plotIndex, disc.pad, now)
						if paid > 0 then
							disc.flashUntil = now + c.FLASH_SECONDS
							disc.paid = paid
							setFace(disc, CashPads.face(0, true, paid))
						end
					end
				end
			end
		end
		if on then
			state.standing[userId] = on
		else
			state.standing[userId] = nil
		end
	end
end

-- Forgets a leaving player's nag timer and standing spot.
function CashPadView.forget(state: State, userId: number)
	CashPadService.forget(state.nags, userId)
	state.standing[userId] = nil
end

return CashPadView
