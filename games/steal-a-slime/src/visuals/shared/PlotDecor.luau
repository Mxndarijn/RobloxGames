--!strict
--[[
	PlotDecor (owner: Archer)

	Attribute-driven plot cosmetics. WorldLayout ships the parts (anchored,
	non-colliding, CanQuery off) in their neutral state; VisualsClient calls
	PlotDecor.apply(plot, workspace:GetServerTimeNow(), viewerUserId) a few times
	a second and only changes them locally (nothing replicates, no remotes).
	The shut door shows half see-through (OWNER_DOOR_TRANSPARENCY) to everyone who
	walks through it: the plot's owner (viewerUserId == OwnerUserId) and the players
	in its Guests list (friends let in, PlotGuests).

	Plot attributes read (CONTRACT.md §5.2 + new ones, all optional):
	  OwnerUserId    0 = free      -> no lock board
	  LockUntil      server time   -> LockBarrier stopper / ParkedStopper + the lock board
	  LockStartedAt  server time   -> how far the lock board's bar has drained
	  Locked         boolean (§8.4) -> used only when LockUntil is missing
	Rebirths never change the base.

	The lock board is a Goo board (shared/GooBoard, like the name board above it on the post) on the LockSign's
	Front face: a red LOCKED band, the time left and a bar that drains over the lock; a green OPEN band and
	"stealable!" while open. It is the only place other players see a lock's time.

	`opts.door = false` leaves the door looks (StopperShut / StopperParked meshes, DoorRing) alone: LockMotion moves
	them while it plays a lock or an open.

	PlotDecor.locked(lockUntil, now) / clock(seconds) are pure
	(Lune-safe, used by the render proof).
	PlotDecor.apply builds its SurfaceGuis on first use and only writes
	properties that changed, so calling it every frame is cheap.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local Constants = if script then require(script.Parent.Parent.Shared.Constants) else require("../../shared/Constants")
local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")
local GooBoard = if script then require(script.Parent.Parent.Shared.GooBoard) else require("../../shared/GooBoard")
local GooPalette = if script
	then require(script.Parent.Parent.Shared.GooPalette)
	else require("../../shared/GooPalette")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

local PlotDecor = {}

PlotDecor.LOCKED_COLOR = { 255, 70, 70 }
PlotDecor.UNLOCKED_COLOR = { 90, 220, 110 }
-- The locked door as the plot's owner and its guests see it: they pass through it, so it shows half see-through.
PlotDecor.OWNER_DOOR_TRANSPARENCY = 0.5

function PlotDecor.locked(lockUntil: number?, now: number): (boolean, number)
	local remaining = (lockUntil or 0) - now
	if remaining > 0 then
		return true, remaining
	end
	return false, 0
end

function PlotDecor.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function set(inst: Instance, prop: string, value: any)
	if (inst :: any)[prop] ~= value then
		(inst :: any)[prop] = value
	end
end

local function show(part: Instance?, visible: boolean, transparency: number?)
	if part and part:IsA("BasePart") then
		set(part, "Transparency", if visible then transparency or 0 else 1)
	end
end

PlotDecor.LOCK_BOARD_GUI = "LockBoard"
PlotDecor.LOCK_BOARD_PIXELS_PER_STUD = 50
-- The lock board's width / height, so the goo drops come out round.
PlotDecor.LOCK_BOARD_ASPECT = WorldLayout.LOCK_SIGN.width / WorldLayout.LOCK_SIGN.height
PlotDecor.LOCK_BOARD = table.freeze({
	band = 0.36,
	radius = 0.2,
	drips = table.freeze({
		-- clear of the time in the middle
		table.freeze({ x = 0.1, w = 0.035, len = 0.05 }),
		table.freeze({ x = 0.25, w = 0.04, len = 0.08 }),
		table.freeze({ x = 0.86, w = 0.03, len = 0.04 }),
	}),
	stroke = 6, -- px at LOCK_BOARD_PIXELS_PER_STUD
	glassTransparency = 0,
} :: GooBoard.Spec)
-- Boxes as fractions of the board { x, y, w, h }.
PlotDecor.LOCK_BOARD_TEXT = table.freeze({
	status = table.freeze({ 0.08, 0.05, 0.84, 0.27 }), -- LOCKED / OPEN, in the band
	time = table.freeze({ 0.1, 0.4, 0.8, 0.4 }), -- m:ss / stealable!
	bar = table.freeze({ 0.14, 0.83, 0.72, 0.07 }), -- the drain bar's track
})

local function globals(): GooBoard.Deps
	return { Instance = Instance, Enum = Enum, UDim = UDim, UDim2 = UDim2, Color3 = Color3 }
end

local function box(inst: GuiObject, b: { number })
	inst.Position = UDim2.fromScale(b[1], b[2])
	inst.Size = UDim2.fromScale(b[3], b[4])
end

type Board = { gui: SurfaceGui, card: Frame, status: TextLabel, time: TextLabel, track: Frame, fill: Frame }

-- The lock board on `sign`'s Front face, built on first use.
local function board(sign: Instance): Board
	local deps = globals()
	local gui = sign:FindFirstChild(PlotDecor.LOCK_BOARD_GUI) :: SurfaceGui?
	if not gui then
		local g = Instance.new("SurfaceGui")
		g.Name = PlotDecor.LOCK_BOARD_GUI
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = PlotDecor.LOCK_BOARD_PIXELS_PER_STUD
		g.LightInfluence = 0
		local card = GooBoard.build(g, deps, PlotDecor.LOCK_BOARD, PlotDecor.LOCK_BOARD_ASPECT)
		box(GooBoard.text(card, deps, "Status", GooPalette.White, 4), PlotDecor.LOCK_BOARD_TEXT.status)
		box(GooBoard.text(card, deps, "Time", GooPalette.Text, 3), PlotDecor.LOCK_BOARD_TEXT.time)
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.BorderSizePixel = 0
		track.BackgroundColor3 = rgb(GooPalette.Ink)
		box(track, PlotDecor.LOCK_BOARD_TEXT.bar)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = track
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(1, 1)
		corner:Clone().Parent = fill
		fill.Parent = track
		track.Parent = card
		g.Parent = sign
		gui = g
	end
	local g = gui :: SurfaceGui
	local card = g:FindFirstChild(GooBoard.CARD) :: Frame
	local track = card:FindFirstChild("Track") :: Frame
	return {
		gui = g,
		card = card,
		status = card:FindFirstChild("Status") :: TextLabel,
		time = card:FindFirstChild("Time") :: TextLabel,
		track = track,
		fill = track:FindFirstChild("Fill") :: Frame,
	}
end

-- The share of a lock still to run, 0..1 (1 when its start is unknown).
function PlotDecor.lockShare(lockStartedAt: number?, lockUntil: number?, now: number): number
	local untilTime = lockUntil or 0
	local started = lockStartedAt or 0
	if started <= 0 or untilTime <= started then
		return 1
	end
	return math.clamp((untilTime - now) / (untilTime - started), 0, 1)
end

-- Draws the lock board: hidden on a free plot (`owned` false), else locked with `remaining` s and `share` left, or open.
local function applyBoard(sign: Instance, owned: boolean, locked: boolean, remaining: number, share: number)
	local b = board(sign)
	set(b.gui, "Enabled", owned)
	if not owned then
		return
	end
	local color = if locked then PlotDecor.LOCKED_COLOR else PlotDecor.UNLOCKED_COLOR
	local status = if locked then "LOCKED" else "OPEN"
	if b.status.Text ~= status then
		GooBoard.paint(b.card, globals(), color)
		b.status.Text = status
		set(b.fill, "BackgroundColor3", rgb(color))
	end
	set(b.time, "Text", if locked then PlotDecor.clock(remaining) else "stealable!")
	set(b.track, "Visible", locked)
	set(b.fill, "Size", UDim2.fromScale(share, 1))
end

-- The swapped mesh under a jar tower look slot (server/MeshSwap names it "Mesh"), or nil before it lands.
function PlotDecor.lookMesh(plot: Instance, name: string): BasePart?
	local slot = plot:FindFirstChild(name)
	local mesh = slot and slot:FindFirstChild("Mesh")
	return if mesh and mesh:IsA("BasePart") then mesh else nil
end
local lookMesh = PlotDecor.lookMesh

local function applyLock(
	plot: Instance,
	owned: boolean,
	locked: boolean,
	remaining: number,
	share: number,
	mine: boolean,
	doorLooks: boolean
)
	local shut = owned and locked
	local door = if mine then PlotDecor.OWNER_DOOR_TRANSPARENCY else nil
	local barrier = plot:FindFirstChild("LockBarrier")
	-- With the stopper meshes in, they are the look (the Stopper box stays the invisible collider); before they land,
	-- the primitive stopper and parked stopper show.
	local meshes = lookMesh(plot, "StopperShut")
	if barrier then
		for _, part in barrier:GetChildren() do
			show(part, shut and meshes == nil, door)
		end
	end
	show(plot:FindFirstChild("ParkedStopper"), not shut and meshes == nil)
	if meshes and doorLooks then
		show(meshes, shut, door)
		show(lookMesh(plot, "StopperParked"), not shut)
	end
	local ring = lookMesh(plot, "DoorRing")
	if ring and doorLooks then
		set(ring, "Color", PlotDecor.ringColor(shut))
	end
	local sign = plot:FindFirstChild("LockSign")
	if sign then
		applyBoard(sign, owned, locked, remaining, share)
	end
end

-- Plot skins (FEATURES.PlotSkins, CONTRACT.md §15) ---------------------------------

PlotDecor.SKIN_DECOR_NAME = "SkinDecor"
local ORIG_COLOR, ORIG_MATERIAL, ORIG_TRANSPARENCY = "SkinOrigColor", "SkinOrigMaterial", "SkinOrigTransparency"

function PlotDecor.skin(id: any): Config.PlotSkin
	for _, skin in Config.PLOT_SKINS do
		if skin.id == id then
			return skin
		end
	end
	return Config.PLOT_SKINS[1]
end

-- Remembers a part's own look once, so a later "classic" can put it back.
local function remember(part: BasePart)
	if part:GetAttribute(ORIG_COLOR) == nil then
		part:SetAttribute(ORIG_COLOR, part.Color)
		part:SetAttribute(ORIG_MATERIAL, part.Material.Name)
	end
end

local function recall(part: BasePart)
	local color = part:GetAttribute(ORIG_COLOR)
	if typeof(color) == "Color3" then
		set(part, "Color", color)
		local material = part:GetAttribute(ORIG_MATERIAL)
		if type(material) == "string" then
			set(part, "Material", (Enum.Material :: any)[material])
		end
	end
end

-- The jar's cork and trim as they show: the bridge, the jar floor, the parked stopper and every jar lid (hidden
-- parts, like a lid under an upper jar, are skipped).
PlotDecor.TRIM_PARTS = table.freeze({ "Bridge", "JarFloor", "ParkedStopper" })
PlotDecor.RING_COLOR = { 168, 148, 110 } -- the door's lock ring while open (ranch_metal brass)
local function eachTrimPart(plot: Instance, visit: (BasePart) -> ())
	for _, name in PlotDecor.TRIM_PARTS do
		local part = plot:FindFirstChild(name)
		if part and part:IsA("BasePart") and part.Transparency < 1 then
			visit(part)
		end
	end
	for _, d in plot:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("JarLid") ~= nil and d.Transparency < 1 then
			visit(d)
		end
	end
end

-- Floor colour / material, cork and trim tint and the decor mesh of one plot for skin `id`.
-- `slot` = the plot's Mailbox_<i> kit slot (Map.Decor) and `templates` =
-- ReplicatedStorage.PlotSkinMeshes: the skin decor is a clone of its template standing where the
-- slot's own mesh stands (that mesh is only hidden), so no world mesh slot is added. Idempotent;
-- only writes what changed. "classic" puts back whatever a skin changed.
function PlotDecor.applySkin(plot: Instance, id: any, slot: Instance?, templates: Instance?)
	local skin = PlotDecor.skin(id)
	local base = plot:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		local floor = skin.floor
		if floor then
			remember(base)
			set(base, "Color", rgb(floor.color))
			set(base, "Material", (Enum.Material :: any)[floor.material])
		else
			recall(base)
		end
	end
	local tint = skin.trim
	eachTrimPart(plot, function(part)
		if tint then
			remember(part)
			local own = part:GetAttribute(ORIG_COLOR)
			if part:IsA("MeshPart") then
				-- A kit mesh keeps its vertex colours; Color multiplies them.
				set(part, "Color", rgb(tint))
			elseif typeof(own) == "Color3" then
				set(part, "Color", Color3.new(own.R * tint[1] / 255, own.G * tint[2] / 255, own.B * tint[3] / 255))
			end
		else
			recall(part)
		end
	end)
	PlotDecor.applySkinDecor(slot, skin.decor, templates)
end

-- The decor mesh over `slot` (a BasePart): `meshName` from `templates`, or none (slot back as built).
function PlotDecor.applySkinDecor(slot: Instance?, meshName: string?, templates: Instance?)
	if not slot or not slot:IsA("BasePart") then
		return
	end
	local current = slot:FindFirstChild(PlotDecor.SKIN_DECOR_NAME)
	local template = if meshName and templates then templates:FindFirstChild(meshName) else nil
	local own = slot:FindFirstChild("Mesh") -- the slot's kit mesh (MeshSwap), or the slot itself while not loaded
	local hideTarget: BasePart = if own and own:IsA("BasePart") then own else slot
	if not (template and template:IsA("BasePart")) then
		if current then
			current:Destroy()
		end
		local was = hideTarget:GetAttribute(ORIG_TRANSPARENCY)
		if type(was) == "number" then
			set(hideTarget, "Transparency", was)
			hideTarget:SetAttribute(ORIG_TRANSPARENCY, nil)
		end
		return
	end
	if hideTarget:GetAttribute(ORIG_TRANSPARENCY) == nil then
		hideTarget:SetAttribute(ORIG_TRANSPARENCY, hideTarget.Transparency)
	end
	set(hideTarget, "Transparency", 1)
	if current and current:GetAttribute("Skin") ~= meshName then
		current:Destroy()
		current = nil
	end
	if not current then
		local mesh = template:Clone()
		mesh.Name = PlotDecor.SKIN_DECOR_NAME
		mesh:SetAttribute("Skin", meshName)
		-- The slot is the mailbox at its RanchProps scale: the skin decor stands on the same
		-- bottom at the same scale, turned like every kit mesh (MeshAssets.IMPORT_YAW).
		local mailbox = MeshAssets.get("ranch_mailbox")
		local scale = if mailbox and mailbox.size then slot.Size.Y / mailbox.size[2] else 1
		mesh.Size = (template :: BasePart).Size * scale
		mesh.CFrame = slot.CFrame
			* CFrame.new(0, -slot.Size.Y / 2 + mesh.Size.Y / 2, 0)
			* CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)
		mesh.Parent = slot
	end
end

-- True when `viewerUserId` walks through the plot's shut door: its owner, or a player in its Guests list.
function PlotDecor.passes(plot: Instance, owner: any, viewerUserId: number?): boolean
	if viewerUserId == nil then
		return false
	end
	if owner == viewerUserId then
		return true
	end
	local guests = plot:GetAttribute(Constants.PLOT_GUESTS_ATTRIBUTE)
	return type(guests) == "string" and string.find(guests, `,{viewerUserId},`, 1, true) ~= nil
end

export type Lock = { owned: boolean, locked: boolean, remaining: number, shut: boolean, see: boolean }

-- A plot's lock as player `viewerUserId` sees it at server time `now`: `shut` = the door is shut (owned and locked),
-- `see` = the viewer walks through it, so the shut door shows half see-through to them.
function PlotDecor.lockOf(plot: Instance, now: number, viewerUserId: number?): Lock
	local owner = plot:GetAttribute("OwnerUserId")
	local owned = type(owner) == "number" and owner ~= 0
	local lockUntil = plot:GetAttribute("LockUntil")
	local locked, remaining = PlotDecor.locked(if type(lockUntil) == "number" then lockUntil else 0, now)
	if type(lockUntil) ~= "number" and plot:GetAttribute(Constants.PLOT_LOCKED_ATTRIBUTE) == true then
		locked = true
	end
	return {
		owned = owned,
		locked = locked,
		remaining = remaining,
		shut = owned and locked,
		see = owned and PlotDecor.passes(plot, owner, viewerUserId),
	}
end

-- The door's lock ring colour: red while shut, brass while open.
function PlotDecor.ringColor(shut: boolean): Color3
	return rgb(if shut then PlotDecor.LOCKED_COLOR else PlotDecor.RING_COLOR)
end

export type Options = { door: boolean? }

-- Applies every cosmetic of one Plot_<i> model for server time `now`, as player `viewerUserId` sees it.
function PlotDecor.apply(plot: Instance, now: number, viewerUserId: number?, opts: Options?)
	local lock = PlotDecor.lockOf(plot, now, viewerUserId)
	local startedAt = plot:GetAttribute(Constants.PLOT_LOCK_STARTED_AT_ATTRIBUTE)
	local lockUntil = plot:GetAttribute("LockUntil")
	local share = PlotDecor.lockShare(
		if type(startedAt) == "number" then startedAt else nil,
		if type(lockUntil) == "number" then lockUntil else nil,
		now
	)
	local doorLooks = opts == nil or opts.door ~= false
	applyLock(plot, lock.owned, lock.locked, lock.remaining, share, lock.see, doorLooks)
end

return table.freeze(PlotDecor)
