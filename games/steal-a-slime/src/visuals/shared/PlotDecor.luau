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
	  OwnerUserId    0 = free
	  LockUntil      server time   -> LockBarrier stopper / ParkedStopper and the door looks
	  Locked         boolean (§8.4) -> used only when LockUntil is missing
	Rebirths never change the base.

	`opts.door = false` leaves the door looks (StopperShut / StopperParked meshes, DoorRing) alone: LockMotion moves
	them while it plays a lock or an open.

	PlotDecor.locked(lockUntil, now) is pure
	(Lune-safe, used by the render proof).
	PlotDecor.apply only writes properties that changed, so calling it every
	frame is cheap.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local Constants = if script then require(script.Parent.Parent.Shared.Constants) else require("../../shared/Constants")
local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")

local PlotDecor = {}

PlotDecor.LOCKED_COLOR = { 255, 70, 70 }
-- The locked door as the plot's owner and its guests see it: they pass through it, so it shows half see-through.
PlotDecor.OWNER_DOOR_TRANSPARENCY = 0.5

function PlotDecor.locked(lockUntil: number?, now: number): (boolean, number)
	local remaining = (lockUntil or 0) - now
	if remaining > 0 then
		return true, remaining
	end
	return false, 0
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

-- The swapped mesh under a jar tower look slot (server/MeshSwap names it "Mesh"), or nil before it lands.
function PlotDecor.lookMesh(plot: Instance, name: string): BasePart?
	local slot = plot:FindFirstChild(name)
	local mesh = slot and slot:FindFirstChild("Mesh")
	return if mesh and mesh:IsA("BasePart") then mesh else nil
end
local lookMesh = PlotDecor.lookMesh

local function applyLock(plot: Instance, owned: boolean, locked: boolean, mine: boolean, doorLooks: boolean)
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
	local doorLooks = opts == nil or opts.door ~= false
	applyLock(plot, lock.owned, lock.locked, lock.see, doorLooks)
end

return table.freeze(PlotDecor)
