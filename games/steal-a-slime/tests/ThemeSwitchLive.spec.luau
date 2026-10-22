--!nocheck
-- Equipping a tower theme (CONTRACT.md §15) fetches the theme's meshes side by side, not one after another
-- (MeshSwap.themePlot, what PlotThemeView runs when Plot_<i>.PlotSkin changes): through the REAL server Script (tools/livetest/Runtime, memory store), where every CreateMeshPartAsync takes FETCH_SECONDS
-- of virtual time, the owner equips a theme on a full 4-jar tower and every themed slot shows its theme's mesh in a
-- fraction of the one-at-a-time time.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local MeshAssets = require("../src/shared/MeshAssets")
local PlotSkins = require("../src/shared/PlotSkins")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local FETCH_SECONDS = 1
local SKIN = "crystal"

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-theme-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)

local run = { live = 0, peak = 0, themed = {} }
local rt
rt = Runtime.new(path, {
	createMeshPart = function()
		run.live += 1
		run.peak = math.max(run.peak, run.live)
		rt:wait(FETCH_SECONDS)
		run.live -= 1
		return roblox.Instance.new("MeshPart")
	end,
})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory")
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__themeswitch = { world = world }\n"
rt:boot()
for _ = 1, 600 do
	rt:advance(0.5)
	if rt.workspace:GetAttribute(Constants.WORLD_MESHES_READY_ATTRIBUTE) == true then
		break
	end
end
rt:addPlayer(2004, "Painter")
rt:advance(2)
-- selene: allow(global_usage)
local world = _G.__themeswitch.world
local session = world.sessions[2004]
assert(session, "player did not load")
session.data.padsUnlocked = Config.PADS_MAX
rt:advance(10) -- the upper jars build and get their (classic) meshes

local plot
for _, d in rt.workspace:GetDescendants() do
	if d.Name == `Plot_{session.plotIndex}` then
		plot = d
	end
end

-- Slots showing the theme's mesh, and slots that have a themed mesh at all (the rest stay classic in every theme).
local function themedSlots(): (number, number)
	local done, total = 0, 0
	for _, d in plot:GetDescendants() do
		local name = d:GetAttribute("MeshAsset")
		local mesh = d:FindFirstChild("Mesh")
		if type(name) == "string" and mesh and MeshAssets.meshId(`{name}@{SKIN}`) then
			total += 1
			if mesh:GetAttribute("MeshLook") == `{name}@{SKIN}` then
				done += 1
			end
		end
	end
	return done, total
end

local skin = assert(PlotSkins.get(SKIN))
for _, id in PlotSkins.slimes(skin) do
	session.data.found[id] = true
end
assert(PlotSkins.equip(session.data, SKIN))
rt:advance(1) -- WorldView writes Plot_<i>.PlotSkin
-- In Roblox the attribute's change signal runs PlotThemeView, which runs MeshSwap.themePlot; the fake runtime has no
-- attribute signals, so run the same swap here.
local MeshSwap = rt:require(rt.game:GetService("ServerScriptService").Server.MeshSwap)
run.peak = 0
local start = rt.T
rt:spawn(MeshSwap.themePlot, plot)
local switchedAt
for _ = 1, 400 do
	rt:advance(0.25)
	local done, total = themedSlots()
	if total > 0 and done == total then
		switchedAt = rt.T - start
		break
	end
end
local done, total = themedSlots()

describe("tower theme switch", function()
	it("puts the theme's mesh on every themed slot of a 4-jar tower", function()
		expect(total > 40).toBe(true)
		expect(done).toBe(total)
	end)
	it(
		"fetches the theme's meshes side by side: the whole switch takes a few fetches' time, not one per slot",
		function()
			expect(switchedAt ~= nil).toBe(true)
			expect(run.peak > 4).toBe(true)
			expect(switchedAt < 6 * FETCH_SECONDS).toBe(true)
			print(
				`[ThemeSwitch] {total} slots themed in {switchedAt}s of virtual time, peak {run.peak} fetches at once`
			)
		end
	)
end)
