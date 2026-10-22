--!nocheck
-- A pad slime whose pad is not built yet when its model is made (a player joins with slimes on upper floors: the
-- slime models are made before BaseFloors builds those floors) must still end up on its pad once it is built,
-- never left at the model's build spot, the world origin (inside the fountain).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-padjoin-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {
	createMeshPart = function()
		return roblox.Instance.new("MeshPart")
	end,
})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory") -- in-memory store only (CLAUDE.md hard rule)
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__padJoinSpec = { world = world, WorldView = WorldView }\n"
rt:boot()
rt:advance(2)
-- selene: allow(global_usage)
local S = _G.__padJoinSpec
local world = S.world
local shared = rt.game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local Genome = rt:require(shared:FindFirstChild("Genome"))
local PlayerData = rt:require(shared:FindFirstChild("PlayerData"))
local World = rt:require(server:FindFirstChild("World"))

local USER = 4101
rt:addPlayer(USER, "PadJoiner")
rt:advance(3)
local session = world.sessions[USER]
local topPad = Config.PADS_MAX
local padBuiltBefore = S.WorldView.pad(session.plotIndex, topPad) ~= nil
-- What a join with a saved high-floor slime looks like to the next refresh: the slime and its unlocked floors arrive
-- in the same step, before the floors are built.
session.data.padsUnlocked = topPad
local slime = Genome.generate(world.rng, { id = "padjoin-1", tier = 5 })
assert(PlayerData.addSlime(session.data, slime, topPad), "addSlime")
World.markDirty(session)
rt:advance(3)

local function findModel(name: string)
	for _, d in rt.workspace:GetDescendants() do
		if d.Name == name and d:IsA("Model") then
			return d
		end
	end
	return nil
end
local model = findModel("Slime_padjoin-1")
local pad = S.WorldView.pad(session.plotIndex, topPad)

describe("a pad slime made before its pad is built", function()
	it("starts from a pad that is not built yet (the join order)", function()
		expect(padBuiltBefore).toBe(false)
		expect(pad ~= nil).toBe(true)
	end)
	it("sits on its pad once the pad is built, not at the world origin in the fountain", function()
		expect(model ~= nil).toBe(true)
		expect(model.Parent ~= nil).toBe(true)
		local at = model:FindFirstChild("Body").CFrame.Position
		local padAt = pad.CFrame.Position
		local flat = math.sqrt((at.X - padAt.X) ^ 2 + (at.Z - padAt.Z) ^ 2)
		expect(flat < 0.5).toBe(true) -- centred on the pad
		expect(at.Y > padAt.Y).toBe(true) -- on top of it
		expect(math.sqrt(at.X ^ 2 + at.Z ^ 2) > 30).toBe(true) -- nowhere near the fountain axis
	end)
end)
