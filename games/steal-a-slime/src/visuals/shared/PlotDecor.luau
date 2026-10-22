--!strict
--[[
	PlotDecor (owner: Archer)

	Attribute-driven plot cosmetics. WorldLayout ships the parts (anchored,
	non-colliding, CanQuery off) in their neutral state; VisualsClient calls
	PlotDecor.apply(plot, workspace:GetServerTimeNow(), viewerUserId) a few times
	a second and only changes them locally (nothing replicates, no remotes).
	The shut door shows half see-through (OWNER_DOOR_TRANSPARENCY) to the plot's
	owner only (viewerUserId == OwnerUserId), who walks through it.

	Plot attributes read (CONTRACT.md §5.2 + new ones, all optional):
	  OwnerUserId  0 = free      -> LockSign shows no text
	  LockUntil    server time   -> LockBarrier stopper / ParkedStopper + LockSign "LOCKED m:ss" / "UNLOCKED"
	  Locked       boolean (§8.4) -> used only when LockUntil is missing
	  Rebirths                   -> RebirthDecor by PlotDecor.band (bands start at
	                                the §8.8 ranks Goo Getter / Slime Wrangler /
	                                Goo Tycoon / Slime Sovereign / Mythic Monarch)

	PlotDecor.locked(lockUntil, now) / band(rebirths) / clock(seconds) are pure
	(Lune-safe, used by the render proof).
	PlotDecor.apply builds its SurfaceGuis on first use and only writes
	properties that changed, so calling it every frame is cheap.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local Constants = if script then require(script.Parent.Parent.Shared.Constants) else require("../../shared/Constants")
local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")

local PlotDecor = {}

PlotDecor.LOCKED_COLOR = { 255, 70, 70 }
PlotDecor.UNLOCKED_COLOR = { 90, 220, 110 }
PlotDecor.FREE_COLOR = { 255, 205, 60 }
-- The locked door as the plot's owner sees it: they pass through it, so it shows half see-through.
PlotDecor.OWNER_DOOR_TRANSPARENCY = 0.5

-- Rebirth bands: { min rebirths, trim colour, name }. Band k shows:
-- 1 trim, 2 + pillars, 3 + banners and glowing caps, 4 + crown, neon trim, glow,
-- 5 the same in mythic magenta with a stronger glow.
PlotDecor.BANDS = table.freeze({
	{ min = 1, color = { 205, 127, 50 }, name = "Bronze" },
	{ min = 3, color = { 205, 215, 230 }, name = "Silver" },
	{ min = 6, color = { 255, 200, 60 }, name = "Gold" },
	{ min = 10, color = { 120, 230, 255 }, name = "Diamond" },
	{ min = 20, color = { 255, 90, 220 }, name = "Mythic" },
})

function PlotDecor.locked(lockUntil: number?, now: number): (boolean, number)
	local remaining = (lockUntil or 0) - now
	if remaining > 0 then
		return true, remaining
	end
	return false, 0
end

function PlotDecor.band(rebirths: number?): number
	local band = 0
	for k, b in PlotDecor.BANDS do
		if (rebirths or 0) >= b.min then
			band = k
		end
	end
	return band
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

-- SurfaceGui (Face Front) with one TextLabel per line, stacked top-down.
local function labels(part: Instance, rows: { number }): { TextLabel }
	local gui = part:FindFirstChild("DecorGui")
	if not gui then
		local g = Instance.new("SurfaceGui")
		g.Name = "DecorGui"
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 40
		g.LightInfluence = 0
		local y = 0
		for k, height in rows do
			local l = Instance.new("TextLabel")
			l.Name = `Line{k}`
			l.BackgroundTransparency = 1
			l.Position = UDim2.fromScale(0.04, y)
			l.Size = UDim2.fromScale(0.92, height)
			l.TextScaled = true
			l.Font = Enum.Font.FredokaOne
			l.TextColor3 = Color3.new(1, 1, 1)
			l.TextStrokeTransparency = 0.4
			l.Text = ""
			l.Parent = g
			y += height
		end
		g.Parent = part
		gui = g
	end
	local out = {}
	for k in rows do
		out[k] = (gui :: Instance):FindFirstChild(`Line{k}`) :: TextLabel
	end
	return out
end

-- The swapped mesh under a jar tower look slot (server/MeshSwap names it "Mesh"), or nil before it lands.
local function lookMesh(plot: Instance, name: string): BasePart?
	local slot = plot:FindFirstChild(name)
	local mesh = slot and slot:FindFirstChild("Mesh")
	return if mesh and mesh:IsA("BasePart") then mesh else nil
end

local function applyLock(plot: Instance, owned: boolean, locked: boolean, remaining: number, mine: boolean)
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
	if meshes then
		show(meshes, shut, door)
		show(lookMesh(plot, "StopperParked"), not shut)
	end
	local ring = lookMesh(plot, "DoorRing")
	if ring then
		set(ring, "Color", if shut then rgb(PlotDecor.LOCKED_COLOR) else rgb(PlotDecor.RING_COLOR))
	end
	local sign = plot:FindFirstChild("LockSign")
	if not sign then
		return
	end
	local color = if not owned
		then PlotDecor.FREE_COLOR
		elseif locked then PlotDecor.LOCKED_COLOR
		else PlotDecor.UNLOCKED_COLOR
	local lamp = sign:FindFirstChild("Lamp")
	if lamp and lamp:IsA("BasePart") then
		set(lamp, "Color", rgb(color))
	end
	local lines = labels(sign, { 0.55, 0.45 })
	set(lines[1], "Text", if not owned then "" elseif locked then "LOCKED" else "UNLOCKED")
	set(lines[1], "TextColor3", rgb(color))
	set(lines[2], "Text", if not owned then "" elseif locked then PlotDecor.clock(remaining) else "stealable!")
end

local function applyRebirth(plot: Instance, band: number)
	local decor = plot:FindFirstChild("RebirthDecor")
	if not decor then
		return
	end
	local color = if band > 0 then rgb(PlotDecor.BANDS[band].color) else nil
	for _, part in decor:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local name = part.Name
		local visible = if string.find(name, "^Trim_")
			then band >= 1
			elseif string.find(name, "^Pillar_") then band >= 2
			elseif string.find(name, "^PillarCap_") or string.find(name, "^Banner_") then band >= 3
			elseif name == "Crown" then band >= 4
			else false
		show(part, visible)
		if color then
			set(part, "Color", color)
		end
		if string.find(name, "^Trim_") then
			set(part, "Material", if band >= 4 then Enum.Material.Neon else Enum.Material.Metal)
		end
	end
	local crown = decor:FindFirstChild("Crown")
	if crown then
		local glow = crown:FindFirstChild("RebirthGlow") :: PointLight?
		if band >= 4 and not glow then
			local l = Instance.new("PointLight")
			l.Name = "RebirthGlow"
			l.Range = 24
			l.Parent = crown
			glow = l
		end
		if glow then
			set(glow, "Enabled", band >= 4)
			set(glow, "Brightness", if band >= 5 then 4 else 2)
			if color then
				set(glow, "Color", color)
			end
		end
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

-- Applies every cosmetic of one Plot_<i> model for server time `now`, as player `viewerUserId` sees it.
function PlotDecor.apply(plot: Instance, now: number, viewerUserId: number?)
	local owner = plot:GetAttribute("OwnerUserId")
	local owned = type(owner) == "number" and owner ~= 0
	local lockUntil = plot:GetAttribute("LockUntil")
	local locked, remaining = PlotDecor.locked(if type(lockUntil) == "number" then lockUntil else 0, now)
	if type(lockUntil) ~= "number" and plot:GetAttribute(Constants.PLOT_LOCKED_ATTRIBUTE) == true then
		locked = true
	end
	local rebirths = plot:GetAttribute("Rebirths")
	applyLock(plot, owned, locked, remaining, owned and owner == viewerUserId)
	applyRebirth(plot, if owned and type(rebirths) == "number" then PlotDecor.band(rebirths) else 0)
end

return table.freeze(PlotDecor)
