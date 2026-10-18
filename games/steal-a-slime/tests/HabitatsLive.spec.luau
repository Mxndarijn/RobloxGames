--!nocheck
-- FEATURES.Habitats on, through the REAL server Script (tools/livetest/Runtime,
-- memory store): WorldView writes Habitat / HabitatFrom / HabitatAt on the
-- owner's Pad_<j> and flips it back to base when the slime is carried off.
-- The flag is switched on in the built place's Config source only; the
-- shipped Config keeps it off (Habitats.spec, LiveBoot.spec).
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
	mutation = "None",
	pad = 3,
	species = "cosmo",
})
rt:advance(1)
local placed = read(pad(3))
local placedAt = pad(3):GetAttribute("HabitatAt")
world.carriedBy.hab1 = 999 -- carried off by a thief
rt:advance(1)
local stolen = read(pad(3))

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
	world.carriedBy.hab1 = nil -- enters (lands on pad 3)
	rt:advance(0.5)
	fire()
	frames(0.4) -- mid-transform
	maxLooks, maxBursts = math.max(maxLooks, looksOf(part)), math.max(maxBursts, burstsOf(part))
	world.carriedBy.hab1 = 999 -- leaves
	rt:advance(0.5)
	fire()
	frames(0.3)
	maxLooks, maxBursts = math.max(maxLooks, looksOf(part)), math.max(maxBursts, burstsOf(part))
end
frames(1.5)
local settledLooks = looksOf(part)
world.carriedBy.hab1 = nil -- back on the pad, fully grown
rt:advance(0.5)
fire()
frames(1.5)
local grownLooks = looksOf(part)
local function lookOf(p, id)
	local root = rt.workspace:FindFirstChild("ClientHabitats")
	return root and root:FindFirstChild(`{p.Parent.Name}_{p.Name}_{id}`)
end
local grown = lookOf(part, "crystal_grotto")
local grownPlaceholder = { grown:FindFirstChild("Seat") ~= nil, grown:FindFirstChild("Mesh") ~= nil }
local grownHidden = part.Stand.LocalTransparencyModifier
part:SetAttribute("Habitat", "not_a_habitat") -- table drift / bad attribute
fire()
frames(1.5)
local driftLooks = looksOf(part)
local driftHidden = part.Stand.LocalTransparencyModifier
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

-- Same pad once habitat_crystal_grotto has a meshId (set on the runtime's
-- MeshAssets copy only for this case): one FileMesh piece.
meshAssets.entries.habitat_crystal_grotto.meshId = "rbxassetid://123"
part:SetAttribute("Habitat", "crystal_grotto")
local meshConns = HabitatFx.attach(plots)
local meshLook = lookOf(part, "crystal_grotto")
local meshPart = meshLook and meshLook:FindFirstChild("Mesh")
local special = meshPart and meshPart:FindFirstChildOfClass("SpecialMesh")
local meshShape = {
	meshLook and #meshLook:GetChildren(),
	special and special.MeshType == roblox.Enum.MeshType.FileMesh,
	special and tostring(special.MeshId),
	special and math.abs(special.Scale.Y - part.Size.Y / 2.4) < 1e-4,
	meshPart and math.abs(meshPart.Size.X - 7.8) < 1e-4,
}
for _, c in meshConns do
	c:Disconnect()
end
HabitatFx.clear()

local emitsLifecycle = emits
-- Morph behaviour (HabitatMorph through HabitatFx), placeholder looks, camera near the pad.
meshAssets.entries.habitat_crystal_grotto.meshId = nil
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
	return part.Stand.Color == standColor
		and part.Color == padColor
		and part.Stand.LocalTransparencyModifier == 0
		and looksOf(part) == 0
end
part:SetAttribute("Habitat", "base")
HabitatFx.attach(plots)
standColor, padColor = part.Stand.Color, part.Color
local partsAtBase, meshesAtBase = worldParts()
local emitsBefore = emits
setHabitat("crystal_grotto")
frames(0.2)
local early = lookOf(part, "crystal_grotto")
local stagger = { early.Seat.Size.Y > 0.5, early.Crystal4.Size.Y < 0.3 } -- seat up, last prop not started
local peak = 0
for _ = 1, 18 do
	frames(0.05)
	peak = math.max(peak, early.Seat.Size.Y)
end
local midTinted = part.Stand.Color ~= standColor
frames(1.5)
local enterSig = sig("crystal_grotto")
local enterSettled = { part.Stand.LocalTransparencyModifier, looksOf(part), emits - emitsBefore }
setHabitat("base")
frames(0.5)
local leaveMid = lookOf(part, "crystal_grotto")
local leaving = leaveMid ~= nil and leaveMid.Seat.Size.Y < 7.2 and part.Stand.LocalTransparencyModifier < 1
frames(1.2)
local leftBase = atBase()
local partsAfterLeave, meshesAfterLeave = worldParts()
-- Interrupt mid-tween both ways, then settle: still the exact static look, then the exact base pad.
setHabitat("crystal_grotto")
frames(0.4)
setHabitat("base")
frames(0.3)
setHabitat("crystal_grotto")
frames(0.2)
setHabitat("candy_patch")
frames(0.2)
setHabitat("crystal_grotto")
local interruptLooks = 0
for _ = 1, 40 do
	frames(0.05)
	interruptLooks = math.max(interruptLooks, looksOf(part))
end
local interruptSig = sig("crystal_grotto")
setHabitat("base")
frames(0.3)
setHabitat("crystal_grotto")
frames(0.1)
setHabitat("base")
frames(2)
local interruptBase = atBase()
local partsAfterInterrupt = worldParts()
-- Late joiner: first sight is the static final state, no puff.
HabitatFx.clear()
local colorsAfterClear = part.Stand.Color == standColor and part.Color == padColor
local emitsLate = emits
part:SetAttribute("Habitat", "crystal_grotto")
HabitatFx.attach(plots)
local lateSig, lateEmits = sig("crystal_grotto"), emits - emitsLate
HabitatFx.clear()
-- Far from the camera: the change snaps (final state at once, no puff), the leave too.
cameraAt(300)
part:SetAttribute("Habitat", "base")
HabitatFx.attach(plots)
emitsLate = emits
setHabitat("crystal_grotto")
local farSig, farEmits = sig("crystal_grotto"), emits - emitsLate
setHabitat("base")
local farLeft = atBase()
HabitatFx.clear()

describe("Habitat morph (HabitatFx + HabitatMorph, fake runtime)", function()
	it("rises with stagger and overshoots, tinting the pad on the way", function()
		expect(stagger).toEqual({ true, true })
		expect(peak > 7.2).toBe(true)
		expect(midTinted).toBe(true)
	end)
	it("settles to exactly the late-join static habitat", function()
		expect(enterSettled).toEqual({ 1, 1, 1 })
		expect(enterSig ~= "").toBe(true)
		expect(interruptSig).toBe(enterSig)
		expect(lateSig).toBe(enterSig)
		expect(lateEmits).toBe(0)
	end)
	it("leave goes back through a shrinking look to the exact base pad", function()
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
		expect(placed).toEqual({ "crystal_grotto", "base" })
		expect(type(placedAt)).toBe("number")
	end)
	it("reverts the pad to base when the slime is carried off", function()
		expect(stolen).toEqual({ "base", "crystal_grotto" })
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
	it("draws the placeholder for a mesh slot with no meshId in the repo", function()
		expect(grownPlaceholder).toEqual({ true, false })
	end)
	it("draws the slot mesh (FileMesh, seat fit to the pad) once a meshId exists", function()
		expect(meshShape).toEqual({ 1, true, "rbxassetid://123", true, true })
		expect(#rt.errors).toBe(0)
	end)
	it("shows the base pad for an unknown habitat id", function()
		expect(grownLooks).toBe(1)
		expect(grownHidden).toBe(1) -- Stand hidden under the look
		expect(driftLooks).toBe(0)
		expect(driftHidden).toBe(0) -- Stand shows again (old readId hid it for good)
	end)
	it("disconnects the pad's Habitat listener when the pad is removed", function()
		expect(before).toBe(1)
		expect(after).toBe(0)
		expect(afterCount).toBe(tracked - 1)
	end)
end)
