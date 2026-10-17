--!nocheck
-- Shared runtime counter for Steal a Slime: boots the rojo place in the fake server
-- (tools/livetest/Runtime.luau) and runs tools/pipeline/pc-watcher/luau/perf_server.luau
-- ITSELF against the booted world, so Studio's perf step and this offline count share one
-- source of truth for the exclusions (WildSlimes, DrainSplash, Slimes folders, characters).
-- Used by tests/RuntimeParts.spec and tools/pr-gate/runtime_budget.luau.
--
-- Calibration: the fake runtime builds 16 fewer MeshParts than Studio
-- (RUNTIME_SLOT_ALLOWANCE, see tools/pr-gate/README.md), so Studio-equivalent
-- runtime_parts = offline runtime_parts + RuntimeCount.STUDIO_OFFSET.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Runtime = require("../../games/steal-a-slime/tools/livetest/Runtime")
local WorldLayout = require("../../games/steal-a-slime/src/visuals/shared/WorldLayout")

local RuntimeCount = {}

-- Relative to the game dir (cwd). PR_GATE_PERF_SERVER overrides: runtime_budget.sh points the base-tree
-- count at HEAD's probe so both sides are counted by the same code.
RuntimeCount.PERF_SERVER = process.env.PR_GATE_PERF_SERVER or "../../tools/pipeline/pc-watcher/luau/perf_server.luau"
RuntimeCount.STEP_SECONDS = 15 -- same as tests/RuntimeParts.spec: parade lane, slide colliders, MeshSwap have run
RuntimeCount.STEP_HZ = 30
-- MeshParts (and so parts) Studio has that the fake runtime does not: 16, WorldLayout.RUNTIME_SLOT_ALLOWANCE
-- (one source of truth with budget_counts.luau). Most likely the podium R15 rig PodiumRigs builds with
-- Players:CreateHumanoidModelFromDescriptionAsync (15 R15 MeshParts + HumanoidRootPart + one accessory
-- handle replaces a 1-Part placeholder: +16 parts, +16 MeshParts), which the fake runtime cannot build.
RuntimeCount.STUDIO_OFFSET = WorldLayout.RUNTIME_SLOT_ALLOWANCE

-- rojo build the place in the current directory (the game dir), boot it, step it.
function RuntimeCount.boot()
	local placePath = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-rtcount-{os.time()}-{math.random(1, 1e9)}.rbxlx`
	local built = process.exec("rojo", { "build", "-o", placePath })
	assert(built.ok, `rojo build failed: {built.stderr}`)
	local rt = Runtime.new(placePath, {
		createMeshPart = function(meshId)
			local part = roblox.Instance.new("MeshPart")
			part.MeshId = meshId -- CreateMeshPartAsync's result carries it; perf_server reads it for unique_meshes
			return part
		end,
	})
	fs.removeFile(placePath)
	rt:boot()
	for _ = 1, RuntimeCount.STEP_SECONDS * RuntimeCount.STEP_HZ do
		rt:step(1 / RuntimeCount.STEP_HZ)
	end
	return rt
end

-- Run perf_server.luau (RuntimeCount.PERF_SERVER) against the booted world.
function RuntimeCount.count(rt, perfServerPath: string?)
	local chunk = luau.load(fs.readFile(perfServerPath or RuntimeCount.PERF_SERVER), {
		debugName = "perf_server.luau",
		environment = { game = rt.game, workspace = rt.workspace },
	})
	local result = chunk()
	assert(type(result) == "table" and result.runtime_parts, "perf_server.luau returned no runtime_parts")
	return result
end

return RuntimeCount
