--!nocheck
-- MeshSwap fetches the world's mesh templates side by side, not one after another, and marks the world ready for
-- the client's loading screen once the slots and vats are dressed (or the fetches failed). Booted in the fake
-- runtime, where every CreateMeshPartAsync takes FETCH_SECONDS of virtual time.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Constants = require("../src/shared/Constants")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local FETCH_SECONDS = 1
-- MeshSwap.PREFETCH_WORKERS (MeshSwap needs Roblox services, so the spec can't require it).
local WORKERS = 8

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-prefetch-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)

local function boot(loads: boolean)
	local run = { asked = {}, live = 0, peak = 0, readyAt = nil }
	local rt
	rt = Runtime.new(path, {
		createMeshPart = function(meshId, options)
			local key = `{meshId}|{tostring(options and options.CollisionFidelity)}`
			run.asked[key] = (run.asked[key] or 0) + 1
			run.live += 1
			run.peak = math.max(run.peak, run.live)
			rt:wait(FETCH_SECONDS)
			run.live -= 1
			if loads then
				return roblox.Instance.new("MeshPart")
			end
			error(`livetest: CreateMeshPartAsync({meshId}) failed`)
		end,
	})
	rt:boot()
	run.readyBeforeFetches = rt.workspace:GetAttribute(Constants.WORLD_MESHES_READY_ATTRIBUTE)
	for _ = 1, 600 do
		rt:advance(0.5)
		if rt.workspace:GetAttribute(Constants.WORLD_MESHES_READY_ATTRIBUTE) == true then
			run.readyAt = rt.T
			break
		end
	end
	run.rt = rt
	run.fetches = 0
	for _, n in run.asked do
		run.fetches += n
	end
	return run
end

local loaded = boot(true)
local failed = boot(false)
fs.removeFile(path)

describe("mesh prefetch", function()
	it("boots clean", function()
		expect(#loaded.rt.errors).toBe(0)
		expect(#failed.rt.errors).toBe(0)
	end)
	it("fetches at least PREFETCH_WORKERS templates at once", function()
		-- the template publishers and ParadeView fetch on their own threads beside the prefetch workers
		expect(loaded.fetches > WORKERS).toBe(true)
		expect(loaded.peak >= WORKERS).toBe(true)
		print(
			`[MeshPrefetch] {loaded.fetches} fetches of {FETCH_SECONDS}s, ready at t={loaded.readyAt}, peak {loaded.peak}`
		)
	end)
	it("asks for each template once, even when two callers want it at the same time", function()
		for key, n in loaded.asked do
			if n ~= 1 then
				error(`{key} fetched {n} times`)
			end
		end
	end)
	it("dresses the world in a fraction of the one-at-a-time time", function()
		expect(loaded.readyAt ~= nil).toBe(true)
		expect(loaded.readyAt < loaded.fetches * FETCH_SECONDS / 3).toBe(true)
	end)
	it("marks the world ready only after the meshes are placed", function()
		expect(loaded.readyBeforeFetches).toBe(nil)
		local meshes = 0
		for _, d in loaded.rt.workspace:FindFirstChild(Constants.MAP_FOLDER):GetDescendants() do
			if d.ClassName == "MeshPart" and d.Name == "Mesh" then
				meshes += 1
			end
		end
		expect(meshes > 0).toBe(true)
	end)
	it("still marks the world ready when every fetch fails", function()
		expect(failed.readyAt ~= nil).toBe(true)
	end)
end)
