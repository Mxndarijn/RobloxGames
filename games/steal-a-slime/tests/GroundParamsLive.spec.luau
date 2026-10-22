--!nocheck
-- Returning slimes ray-cast the ground under them every Heartbeat (WorldView.followReturn). Through the REAL server
-- Script (tools/livetest/Runtime, memory store): the RaycastParams they use are built once per short interval, not once
-- per ray, and the rays still run.
--# selene: allow(global_usage)
local fs = require("@lune/fs")
local process = require("@lune/process")

local ParadeLane = require("../src/shared/ParadeLane")
local Runtime = require("../tools/livetest/Runtime")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local roblox = require("@lune/roblox")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local RETURNERS = 10
local FRAMES = 60

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-groundparams-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory")
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__groundparams = { world = world }\n"
local view = rt.game:GetService("ServerScriptService").Server:FindFirstChild("WorldView", true)
assert(view, "WorldView module not found")
-- Count RaycastParams.new calls made by WorldView.
view.Source = "local __rp = RaycastParams\nlocal RaycastParams = { new = function() _G.__rpNew = (_G.__rpNew or 0) + 1 return __rp.new() end }\n"
	.. view.Source
-- Count the rays too.
local hook = "local function surfaceBelow(origin: Vector3, depth: number): CFrame?\n"
local at = string.find(view.Source, hook, 1, true)
assert(at, "surfaceBelow not found")
view.Source = string.sub(view.Source, 1, at + #hook - 1)
	.. "\t_G.__rayCount = (_G.__rayCount or 0) + 1\n"
	.. string.sub(view.Source, at + #hook)
rt:boot()
rt:advance(1)
rt:addPlayer(2004, "Walker")
rt:advance(2)
local world = _G.__groundparams.world
assert(world.sessions[2004], "player did not load")

local function raycasts(): number
	return _G.__rayCount or 0
end

local now = rt.workspace:GetServerTimeNow()
local lateral = ParadeLane.wildLateral(10)
local walking = 0
for _ = 1, RETURNERS do
	local id = Spawner.spawnSlime(world, now)
	local wild = world.wild[id]
	local plan = ParadeLane.returnPlan(ParadeLane.LENGTH / 3, 15, lateral, 100, now - 10)
	if plan then
		wild.position = roblox.Vector3.new(ParadeLane.LENGTH / 3, 5, 15)
		wild.returning = plan
		walking += 1
	end
end
rt:advance(1)
_G.__rpNew = 0
_G.__rayCount = 0
rt:advance(FRAMES / 60)
local paramsBuilt, rays = _G.__rpNew or 0, raycasts()
print(`  RaycastParams built / rays over {FRAMES} frames with {walking} returners: {paramsBuilt} / {rays}`)

describe("ground rays of returning slimes", function()
	it("has returners to measure", function()
		expect(walking).toBe(RETURNERS)
		expect(rays > 0).toBe(true)
	end)
	it("builds far fewer RaycastParams than rays", function()
		expect(paramsBuilt * 5 < rays).toBe(true)
	end)
end)
