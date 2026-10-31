--!nocheck
-- FEATURES.Habitats on, through the REAL server Script (tools/livetest/Runtime,
-- memory store): WorldView writes Habitat / HabitatFrom / HabitatAt on the
-- owner's Pad_<j>, keeps it while a thief carries the slime off and flips it
-- back to base once the slime is gone from the plot.
-- The shipped Config has the flag on; the spec checks the built place's
-- Config source before it runs.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-habitats-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory")
local config = rt.game:GetService("ReplicatedStorage").Shared.Config
assert(string.find(config.Source, "Habitats = true,", 1, true), "FEATURES.Habitats not on in Config")
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__habitats = { world = world }\n"
rt:boot()
rt:advance(1)
rt:addPlayer(2002, "Keeper")
rt:advance(2)
-- selene: allow(global_usage)
local world = _G.__habitats.world -- same export as tools/livetest/session.luau
local session = world.sessions[2002]
assert(session, "player did not load")

local function pad(j)
	for _, d in rt.workspace:GetDescendants() do
		if d.Name == `Pad_{j}` and d.Parent and d.Parent:GetAttribute("PlotIndex") == session.plotIndex then
			return d
		end
	end
	return nil
end

local function read(part)
	return { part:GetAttribute("Habitat"), part:GetAttribute("HabitatFrom") }
end

local empty = read(pad(3))
table.insert(session.data.slimes, {
	id = "hab1",
	name = "Cosmo",
	tier = 6,
	color = { 200, 180, 255 },
	size = 1,
	pattern = "Plain",
	eyes = "Round",
	mouth = "Smile",
	pad = 3,
	species = "cosmo",
})
rt:advance(1)
local placed = read(pad(3))
local placedAt = pad(3):GetAttribute("HabitatAt")
world.carriedBy.hab1 = 999 -- carried off by a thief: the habitat stays
rt:advance(1)
local carried = read(pad(3))
world.carriedBy.hab1 = nil
local hab1
local function takeAway() -- the slime leaves the plot (steal completed, sold, merged)
	for i, slime in session.data.slimes do
		if slime.id == "hab1" then
			hab1 = table.remove(session.data.slimes, i)
			return
		end
	end
end
local function putBack() -- lands on pad 3 again
	table.insert(session.data.slimes, hab1)
end
takeAway()
rt:advance(1)
local gone = read(pad(3))

-- Client lifecycle smoke (HabitatFx, the VisualsClient module) on the same
-- runtime. The fake runtime doesn't fire attribute / descendant signals by
-- itself, so the test fires them the way the engine would.
local signalOf = Runtime.signalOf
local emits = 0
roblox.implementMethod("ParticleEmitter", "Emit", function() -- engine-only; counted here
	emits += 1
end)
-- Clear habitat meshIds so the placeholder path still runs even after uploads.
local meshAssets = rt:require(rt.game:GetService("ReplicatedStorage").Shared.MeshAssets)
for name, entry in meshAssets.entries do
	if string.sub(name, 1, 8) == "habitat_" then
		entry.meshId = nil
	end
end
local HabitatFx = rt:require(rt.game:GetService("StarterPlayer").StarterPlayerScripts.VisualsClient.HabitatFx)
local plots = rt.workspace:FindFirstChild("Plots")
HabitatFx.attach(plots)
local tracked = HabitatFx.count()
local part = pad(3)
-- The fake camera sits far from the plots (quality snap beyond SNAP_BEYOND): put it by the pad.
local camera = rt.workspace.CurrentCamera
local function cameraAt(distance)
	camera.CFrame = roblox.CFrame.new(part.CFrame.Position + roblox.Vector3.new(0, 0, distance))
end
cameraAt(20)
local function frames(seconds)
	for _ = 1, math.round(seconds / 0.05) do
		HabitatFx.step(0.05)
	end
	rt:runDue()
end
local function fire()
	signalOf(part, "Attr:Habitat"):Fire()
	rt:runDue()
end
local function looksOf(p)
	local n = 0
	local root = rt.workspace:FindFirstChild("ClientHabitats")
	for _, m in if root then root:GetChildren() else {} do
		local prefix = `{p.Parent.Name}_{p.Name}_` -- HabitatFx look name: <plot>_<pad>_<id>
		if m.Name:sub(1, #prefix) == prefix then
			n += 1
		end
	end
	return n
end
local function burstsOf(p)
	local n = 0
	for _, c in p:GetChildren() do
		if c.Name == "HabitatBurst" then
			n += 1
		end
	end
	return n
end
local maxLooks, maxBursts = 0, 0
for _ = 1, 5 do
	putBack() -- enters
	rt:advance(0.5)
	fire()
	frames(0.4) -- mid-transform
	maxLooks, maxBursts = math.max(maxLooks, looksOf(part)), math.max(maxBursts, burstsOf(part))
	takeAway() -- leaves
	rt:advance(0.5)
	fire()
	frames(0.3)
	maxLooks, maxBursts = math.max(maxLooks, looksOf(part)), math.max(maxBursts, burstsOf(part))
end
frames(1.5)
local settledLooks = looksOf(part)
putBack() -- back on the pad, fully grown
rt:advance(0.5)
fire()
frames(1.5)
local grownLooks = looksOf(part)
local function lookOf(p, id)
	local root = rt.workspace:FindFirstChild("ClientHabitats")
	return root and root:FindFirstChild(`{p.Parent.Name}_{p.Name}_{id}`)
end
-- The Stand's LocalTransparencyModifier: HabitatFx never sets it, and the fake
-- runtime has no default for an unset one, so unset reads as 0 (shown).
local function standHidden()
	local ok, v = pcall(function()
		return part.Stand.LocalTransparencyModifier
	end)
	return if ok then v else 0
end
local COSMO = "space.6.cosmo" -- the slime on pad 3: Starry Space, Mythic frame, telescope
local grown = lookOf(part, COSMO)
local grownPlaceholder = {
	grown:FindFirstChild("Frame1") ~= nil,
	grown:FindFirstChild("Prop1") ~= nil,
	grown:FindFirstChild("frame") ~= nil,
	grown:FindFirstChild("prop") ~= nil,
	grown:FindFirstChild("Bed") ~= nil,
}
local grownHidden = standHidden()
part:SetAttribute("Habitat", "not_a_habitat") -- table drift / bad attribute
fire()
frames(1.5)
local driftLooks = looksOf(part)
local driftHidden = standHidden()
local function listeners(p)
	local n = 0
	for _, h in signalOf(p, "Attr:Habitat").handlers do
		if h.connected then
			n += 1
		end
	end
	return n
end
local before = listeners(part)
signalOf(plots, "DescendantRemoving"):Fire(part)
rt:runDue()
local after = listeners(part)
local afterCount = HabitatFx.count()
HabitatFx.clear()

-- Same pad once its three layers have a meshId (entries added to the runtime's
-- MeshAssets copy only for this case): placeholders until the server's
-- templates land in ReplicatedStorage.HabitatMeshes, then one clone of each
-- MeshPart at native size: frame and theme centred with their bottom on the
-- dish rim, the signature prop on the front of the rim.
local LAYER_MESHES = {
	habitat_frame_6 = { 7.5, 0.42, 7.5 },
	habitat_theme_space = { 7.6, 2.4, 7.6 },
	habitat_prop_cosmo = { 1.5, 1.3, 1 },
}
for name, size in LAYER_MESHES do
	meshAssets.entries[name] = { meshId = "rbxassetid://123", size = size }
end
local replicated = rt.game:GetService("ReplicatedStorage")
local layout = rt:require(replicated.Visuals.WorldLayout)
local habitatsMod = rt:require(replicated.Shared.Habitats)
local deck = layout.PAD_DECK
local deckY = deck.y
-- One strip of the placeholder's octagon ring at full size: the octagon's side at the dish edge (HabitatFx's
-- FRAME_SIDES 8 strips reach out to deck.half).
local FRAME_LEN = 2 * deck.half * math.tan(math.pi / 8)
part:SetAttribute("Habitat", COSMO)
local meshConns = HabitatFx.attach(plots)
local beforeTemplate = lookOf(part, COSMO)
local waitedPlaceholder =
	{ beforeTemplate:FindFirstChild("Frame1") ~= nil, beforeTemplate:FindFirstChild("frame") ~= nil }
-- The booted server already made the folder (MeshSwap.publishHabitatTemplates;
-- no CreateMeshPartAsync here, so it stays empty).
local templates = replicated:FindFirstChild("HabitatMeshes")
local serverFolder = templates ~= nil
if not templates then
	templates = roblox.Instance.new("Folder")
	templates.Name = "HabitatMeshes"
	templates.Parent = replicated
end
local made = {}
for name, size in LAYER_MESHES do
	local template = roblox.Instance.new("MeshPart")
	template.Name = name
	template.Size = roblox.Vector3.new(size[1], size[2], size[3])
	template.Parent = templates
	signalOf(replicated, "DescendantAdded"):Fire(template)
	rt:runDue()
	table.insert(made, template)
end
local meshLook = lookOf(part, COSMO)
local deckTop = part.CFrame.Position.Y - part.Size.Y / 2 + deckY
local function layerShape(kind: string, mesh: string)
	local m = meshLook and meshLook:FindFirstChild(kind)
	local size = LAYER_MESHES[mesh]
	if not m then
		return false
	end
	local fromCentre = m.CFrame.Position - part.CFrame.Position
	local flat = math.sqrt(fromCentre.X ^ 2 + fromCentre.Z ^ 2)
	local wantFlat = if kind == "prop" then habitatsMod.PROP_RADIUS else 0
	return m.ClassName == "MeshPart"
		and math.abs(m.Size.X - size[1]) < 1e-4
		and math.abs(m.CFrame.Position.Y - m.Size.Y / 2 - deckTop) < 1e-4
		and math.abs(flat - wantFlat) < 1e-3
		and m.CanCollide == false
		and m.CanQuery == false
end
local meshShape = {
	meshLook and #meshLook:GetChildren(),
	layerShape("frame", "habitat_frame_6"),
	layerShape("theme", "habitat_theme_space"),
	layerShape("prop", "habitat_prop_cosmo"),
}
for _, c in meshConns do
	c:Disconnect()
end
HabitatFx.clear()
for _, t in made do
	t:Destroy()
end
for name in LAYER_MESHES do
	meshAssets.entries[name] = nil
end

local emitsLifecycle = emits
-- Morph behaviour (HabitatMorph through HabitatFx), placeholder looks, camera near the pad.
cameraAt(20)
local standColor, padColor
local function worldParts()
	local n, meshes = 0, 0
	for _, d in rt.workspace:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
			if d:IsA("MeshPart") or d:FindFirstChildOfClass("SpecialMesh") then
				meshes += 1
			end
		end
	end
	return n, meshes
end
local function sig(id)
	local m = lookOf(part, id)
	local out = {}
	if m then
		for _, c in m:GetChildren() do
			table.insert(out, `{c.Name}:{c.Size}:{c.CFrame.Position}:{c.Transparency}`)
		end
		table.sort(out)
	end
	return table.concat(out, "|")
end
local function setHabitat(id)
	part:SetAttribute("Habitat", id)
	fire()
end
local function atBase()
	return part.Stand.Color == standColor and part.Color == padColor and standHidden() == 0 and looksOf(part) == 0
end
part:SetAttribute("Habitat", "base")
HabitatFx.attach(plots)
standColor, padColor = part.Stand.Color, part.Color
local partsAtBase, meshesAtBase = worldParts()
local emitsBefore = emits
setHabitat(COSMO)
frames(0.2)
local early = lookOf(part, COSMO)
local stagger = { early.Frame1.Size.X > FRAME_LEN * 0.4, early.Prop3.Size.Y < 0.3 } -- frame up, last prop not started
local peak = 0
for _ = 1, 18 do
	frames(0.05)
	peak = math.max(peak, early.Frame1.Size.X)
end
local midUntouched = part.Stand.Color == standColor and part.Color == padColor and standHidden() == 0
frames(1.5)
local enterSig = sig(COSMO)
local enterSettled = { standHidden(), looksOf(part), emits - emitsBefore }
setHabitat("base")
frames(0.5)
local leaveMid = lookOf(part, COSMO)
local leaving = leaveMid ~= nil and leaveMid.Frame1.Size.X < FRAME_LEN and standHidden() == 0
frames(1.2)
local leftBase = atBase()
local partsAfterLeave, meshesAfterLeave = worldParts()
-- Interrupt mid-tween both ways, then settle: still the exact static look, then the exact base pad.
setHabitat(COSMO)
frames(0.4)
setHabitat("base")
frames(0.3)
setHabitat(COSMO)
frames(0.2)
setHabitat("ember.4.blaze")
frames(0.2)
setHabitat(COSMO)
local interruptLooks = 0
for _ = 1, 40 do
	frames(0.05)
	interruptLooks = math.max(interruptLooks, looksOf(part))
end
local interruptSig = sig(COSMO)
setHabitat("base")
frames(0.3)
setHabitat(COSMO)
frames(0.1)
setHabitat("base")
frames(2)
local interruptBase = atBase()
local partsAfterInterrupt = worldParts()
-- Late joiner: first sight is the static final state, no puff.
HabitatFx.clear()
local colorsAfterClear = part.Stand.Color == standColor and part.Color == padColor
local emitsLate = emits
part:SetAttribute("Habitat", COSMO)
HabitatFx.attach(plots)
local lateSig, lateEmits = sig(COSMO), emits - emitsLate
HabitatFx.clear()
-- Far from the camera: the change snaps (final state at once, no puff), the leave too.
cameraAt(300)
part:SetAttribute("Habitat", "base")
HabitatFx.attach(plots)
emitsLate = emits
setHabitat(COSMO)
local farSig, farEmits = sig(COSMO), emits - emitsLate
setHabitat("base")
local farLeft = atBase()
HabitatFx.clear()

describe("Habitat morph (HabitatFx + HabitatMorph, fake runtime)", function()
	it("rises with stagger and overshoots while the pad itself never changes", function()
		expect(stagger).toEqual({ true, true })
		expect(peak > FRAME_LEN).toBe(true)
		expect(midUntouched).toBe(true)
	end)
	it("settles to exactly the late-join static habitat", function()
		expect(enterSettled).toEqual({ 0, 1, 1 })
		expect(enterSig ~= "").toBe(true)
		expect(interruptSig).toBe(enterSig)
		expect(lateSig).toBe(enterSig)
		expect(lateEmits).toBe(0)
	end)
	it("leave goes back through a sinking overlay to the bare base pad", function()
		expect(leaving).toBe(true)
		expect(leftBase).toBe(true)
		expect(interruptBase).toBe(true)
		expect(colorsAfterClear).toBe(true)
	end)
	it("leaves no parts behind and builds no mesh", function()
		local partsNow, meshesNow = worldParts()
		expect(partsAfterLeave).toBe(partsAtBase)
		expect(partsAfterInterrupt).toBe(partsAtBase)
		expect(meshesAfterLeave).toBe(meshesAtBase)
		expect(meshesNow).toBe(meshesAtBase)
		expect(partsNow).toBe(partsAtBase)
	end)
	it("keeps one look per habitat through interrupts (at most grown + shrinking + new)", function()
		expect(interruptLooks <= 3).toBe(true)
	end)
	it("snaps with no puff when far from the camera", function()
		expect(farSig).toBe(enterSig)
		expect(farEmits).toBe(0)
		expect(farLeft).toBe(true)
	end)
end)

describe("Habitats live (FEATURES.Habitats on, fake runtime)", function()
	it("boots without script errors", function()
		expect(#rt.errors).toBe(0)
	end)
	it("marks empty pads base", function()
		expect(empty).toEqual({ "base", "base" })
	end)
	it("writes the slime's habitat on its pad with a server-time stamp", function()
		expect(placed).toEqual({ "space.6.cosmo", "base" })
		expect(type(placedAt)).toBe("number")
	end)
	it("keeps the habitat while a thief carries the slime off", function()
		expect(carried).toEqual({ COSMO, "base" })
	end)
	it("reverts the pad to base once the slime is gone from the plot", function()
		expect(gone).toEqual({ "base", COSMO })
		expect(pad(3):GetAttribute("HabitatAt") > placedAt).toBe(true)
	end)
end)

describe("HabitatFx client lifecycle (fake runtime)", function()
	it("tracks every pad from one pass over Plots", function()
		expect(tracked > 0).toBe(true)
	end)
	it("5x enter / leave leaves at most 1 look and 1 burst per pad", function()
		expect(maxLooks <= 2).toBe(true) -- 1 growing + 0 or 1 shrinking mid-swap
		expect(maxBursts).toBe(1)
		expect(emitsLifecycle).toBe(12) -- 10 transforms + grow again + the drift to base
		expect(settledLooks).toBe(0) -- ended at base: no look left
		expect(#rt.errors).toBe(0)
	end)
	it("draws the bed, the frame and theme placeholders, and no signature prop, while nothing is uploaded", function()
		expect(grownPlaceholder).toEqual({ true, true, false, false, true })
	end)
	it("keeps the placeholders until the server's templates arrive", function()
		expect(waitedPlaceholder).toEqual({ true, false })
		expect(serverFolder).toBe(true)
	end)
	it("then draws one template clone per layer: frame and theme on the deck, the prop on the front rim", function()
		expect(meshShape).toEqual({ 4, true, true, true }) -- the bed disc plus one clone per mesh layer
		expect(#rt.errors).toBe(0)
	end)
	it("shows the bare base pad for an unknown habitat id", function()
		expect(grownLooks).toBe(1)
		expect(grownHidden).toBe(0) -- the Stand stays under the overlay
		expect(driftLooks).toBe(0)
		expect(driftHidden).toBe(0)
	end)
	it("disconnects the pad's Habitat listener when the pad is removed", function()
		expect(before).toBe(1)
		expect(after).toBe(0)
		expect(afterCount).toBe(tracked - 1)
	end)
end)
