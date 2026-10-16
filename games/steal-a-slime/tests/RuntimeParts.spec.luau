--!nocheck
-- Runtime part budget (target 1800, ratchet 2230: only ever lower it). WorldBudget.spec holds the build-time
-- Part nodes to 1400; this boots the real server (rojo place, fake runtime) and counts
-- every BasePart in Workspace once the parade lane, the slide colliders, WorldProps,
-- the ritual circle and MeshSwap have spawned. pc-watcher's perf_server reports the same
-- number as runtime_parts and the 22-border-aerial-runtime-parts shot asserts it <= RUNTIME_PARTS_MAX.
-- Transient play objects (wild slimes, pad slimes, characters, the drain splash) are split out
-- (runtime_parts_transient in perf_server) so the cap does not flap with play; keep both filters in sync.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local RUNTIME_PARTS_MAX = 1800 -- the target
-- Ratchet (same number as the pc-watcher runtime_part_budget and the shot's runtime_parts_max): the
-- fake-runtime world measured 2272 BaseParts when this test landed. Only ever lower it; target 1800.
local WORLD_RATCHET = 2230

local placePath = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-rtparts-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", placePath })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(placePath, {
	createMeshPart = function(_meshId)
		return roblox.Instance.new("MeshPart")
	end,
})
fs.removeFile(placePath)
rt:boot()
for _ = 1, 15 * 30 do
	rt:step(1 / 30)
end

local wild = rt.workspace:FindFirstChild("WildSlimes")
local total, world, slimes = 0, 0, 0
local breakdown: { [string]: number } = {}
for _, d in rt.workspace:GetDescendants() do
	if d:IsA("BasePart") then
		total += 1
		if (wild and d:IsDescendantOf(wild)) or d.Name == "DrainSplash" or d:FindFirstAncestor("Slimes") then
			slimes += 1
		else
			world += 1
			-- bucket: Map.<child> for the map, else the top-level child of Workspace
			local key = d.Name
			local top = d
			while top.Parent and top.Parent ~= rt.workspace do
				top = top.Parent
			end
			key = top.Name
			if top.Name == "Map" then
				local sub = d
				while sub.Parent and sub.Parent ~= top do
					sub = sub.Parent
				end
				key = `Map.{sub.Name}`
			end
			breakdown[key] = (breakdown[key] or 0) + 1
		end
	end
end

local keys = {}
for k in breakdown do
	table.insert(keys, k)
end
table.sort(keys, function(a, b)
	return breakdown[a] > breakdown[b]
end)
local lines = {}
for _, k in keys do
	table.insert(lines, `{k}={breakdown[k]}`)
end
print(`[RuntimeParts] total {total} = world {world} + transient parts {slimes}`)
print(`[RuntimeParts] world by group: {table.concat(lines, ", ")}`)

describe("runtime part budget", function()
	it("boots with no server errors and spawns the parade lane and slide colliders", function()
		expect(#rt.errors).toBe(0)
		expect(rt.workspace.Map.Plaza:FindFirstChild("ParadeLane") ~= nil).toBe(true)
		expect(rt.workspace.Map.Volcano:FindFirstChild("SlideColliders") ~= nil).toBe(true)
	end)
	it(`keeps the world (no wild slimes) under the {WORLD_RATCHET} ratchet`, function()
		expect(world > 0).toBe(true)
		expect(world <= WORLD_RATCHET).toBe(true)
	end)
	it(`reports the gap to the {RUNTIME_PARTS_MAX} target`, function()
		print(
			`[RuntimeParts] world {world} vs target {RUNTIME_PARTS_MAX}: over by {math.max(0, world - RUNTIME_PARTS_MAX)}`
		)
		expect(RUNTIME_PARTS_MAX < WORLD_RATCHET).toBe(true)
	end)
end)
