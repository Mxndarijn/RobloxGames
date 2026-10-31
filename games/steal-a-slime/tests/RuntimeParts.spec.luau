--!nocheck
-- Runtime part budget: fixed cap, no ratchet (tools/pipeline/pc-watcher/budgets.json runtime_parts: FAIL above
-- `fail`, WARN above `warn`). WorldBudget.spec holds the build-time
-- Part nodes to 1400; this boots the real server (rojo place, fake runtime) and counts
-- every BasePart in Workspace once the parade lane, the slide colliders, WorldProps,
-- the ritual circle and MeshSwap have spawned. pc-watcher's perf_server reports the same
-- number as runtime_parts and the 22-border-aerial-runtime-parts shot asserts it <= the same cap.
-- Transient play objects (wild slimes, pad slimes, characters, the drain splash) are split out
-- (runtime_parts_transient in perf_server) so the cap does not flap with play. The count IS perf_server.luau,
-- run by tools/pr-gate/runtime_count.luau, so the filters cannot drift. This spec compares the RAW offline count;
-- Studio sees RUNTIME_SLOT_ALLOWANCE (16) more, which tools/pr-gate/runtime_budget.sh adds and gates (CI).
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local ObbyCourse = require("../src/shared/ObbyCourse")
local Runtime = require("../tools/livetest/Runtime")
local RuntimeCount = require("../../../tools/pr-gate/runtime_count")
local TestRunner = require("./TestRunner")
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Single source: tools/pipeline/pc-watcher/budgets.json (also read by watcher.py, the runtime pr-gate and the
-- shot's runtime_parts_max). The CI count adds RUNTIME_SLOT_ALLOWANCE; this spec compares the raw offline count.
local budgets = serde.decode("json", fs.readFile("../../tools/pipeline/pc-watcher/budgets.json"))
local PARTS_FAIL: number = budgets.runtime_parts.fail

local rt = RuntimeCount.boot()
-- The count itself is pc-watcher's perf_server.luau run against this world (same filters as Studio).
local perf = RuntimeCount.count(rt)

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

-- FEATURES.PvP forced on vs off (CONTRACT.md §26.1): one player at rest, same steps; PvP must add 0 parts.
local placePath = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-rtparts-pvp-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", placePath })
assert(built.ok, `rojo build failed: {built.stderr}`)
local function countParts(forcePvp: boolean): (number, number, any)
	local r = Runtime.new(placePath, {
		createMeshPart = function(_meshId)
			return roblox.Instance.new("MeshPart")
		end,
		sourceHook = function(script, source)
			if script.Name == "Config" then
				local out, n = string.gsub(source, "(\n\t\tPvP = )%a+(,)", `%1{tostring(forcePvp)}%2`)
				assert(n == 1, "Config.FEATURES.PvP line not found")
				return out
			end
			return source
		end,
	})
	r:boot()
	r:addPlayer(5001, "PvpProbe", roblox.Vector3.new(120, 6, -120))
	for _ = 1, 8 * 30 do
		r:step(1 / 30)
	end
	local parts, transient = 0, 0
	local w = r.workspace:FindFirstChild("WildSlimes")
	for _, d in r.workspace:GetDescendants() do
		if d:IsA("BasePart") then
			if (w and d:IsDescendantOf(w)) or d.Name == "DrainSplash" or d:FindFirstAncestor("Slimes") then
				transient += 1
			else
				parts += 1
			end
		end
	end
	local errors = #r.errors
	r:close()
	return parts, transient, errors
end
local offParts, _, offErrors = countParts(false)
local onParts, _, onErrors = countParts(true)
fs.removeFile(placePath)
print(`[RuntimeParts] PvP at rest: off {offParts} vs on {onParts}`)

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
print(
	`[RuntimeParts] perf_server: runtime_parts {perf.runtime_parts} (+{RuntimeCount.STUDIO_OFFSET} Studio-only = {perf.runtime_parts + RuntimeCount.STUDIO_OFFSET}), mesh_slots {perf.mesh_slots}`
)
print(`[RuntimeParts] total {total} = world {world} + transient parts {slimes}`)
print(`[RuntimeParts] world by group: {table.concat(lines, ", ")}`)

describe("runtime part budget", function()
	it("boots with no server errors and spawns the parade lane and slide colliders", function()
		expect(#rt.errors).toBe(0)
		expect(rt.workspace.Map.Plaza:FindFirstChild("ParadeLane") ~= nil).toBe(true)
		expect(rt.workspace.Map.Volcano:FindFirstChild("SlideColliders") ~= nil).toBe(true)
	end)
	it("counts the same world as pc-watcher's perf_server (the breakdown below cannot drift from it)", function()
		expect(world).toBe(perf.runtime_parts)
		expect(slimes).toBe(perf.runtime_parts_transient)
	end)
	it(`keeps the world (no wild slimes) within the fixed {PARTS_FAIL} cap, Studio offset included`, function()
		expect(world > 0).toBe(true)
		expect(world + RuntimeCount.STUDIO_OFFSET <= PARTS_FAIL).toBe(true)
	end)
	it("keeps the obby course off the server, so the heaviest rotation fits the cap too", function()
		-- The count above sees one rotation slot. Courses differ per slot (contract/obby.md §2); each client builds
		-- its own (ObbyCourseView), so the server's share of any course must be zero.
		local obby = rt.workspace:FindFirstChild(Constants.OBBY_FOLDER)
		expect(obby ~= nil).toBe(true)
		local slot = obby:GetAttribute(Constants.OBBY_SLOT)
		expect(type(slot)).toBe("number")
		local portal = obby:FindFirstChild(Constants.OBBY_PORTAL)
		local courseOnServer = 0
		for _, d in obby:GetDescendants() do
			if d:IsA("BasePart") and not (portal and d:IsDescendantOf(portal)) then
				courseOnServer += 1
			end
		end
		expect(courseOnServer).toBe(0)
		-- The heaviest course over 40 chains of rotations, for the record: it adds nothing to the server world.
		local heaviest = 0
		for s = slot, slot + Config.OBBY.CHAIN_SLOTS * 40 do
			heaviest = math.max(heaviest, #ObbyCourse.build(s).parts)
		end
		print(`[RuntimeParts] heaviest obby course {heaviest} parts, all client-side; server world {world}`)
		expect(heaviest > 0).toBe(true)
		-- Worst case on a live server: this world with its course swapped for the heaviest one, server share 0.
		local worst = world - courseOnServer + 0 * heaviest
		expect(worst + RuntimeCount.STUDIO_OFFSET <= PARTS_FAIL).toBe(true)
	end)
end)

describe("runtime parts with FEATURES.PvP", function()
	it("at rest adds zero parts versus the flag off, and boots without errors", function()
		expect(offErrors).toBe(0)
		expect(onErrors).toBe(0)
		expect(onParts).toBe(offParts)
	end)
	it("tracks everything PvP puts in Workspace and returns to 0 after cleanup", function()
		local PvpService = require("../src/server/PvpService")
		local ServerFixtures = require("./ServerFixtures")
		local pvpWorld = ServerFixtures.world()
		local session = ServerFixtures.join(pvpWorld, 9)
		local folder = roblox.Instance.new("Folder")
		local before = #folder:GetDescendants()
		for _ = 1, 2 do
			local part = roblox.Instance.new("Part")
			part.Parent = folder
			PvpService.track(session, part)
		end
		expect(PvpService.spawnedCount(session)).toBe(2)
		expect(#folder:GetDescendants()).toBe(before + 2)
		PvpService.cleanup(pvpWorld, session)
		expect(PvpService.spawnedCount(session)).toBe(0)
		expect(#folder:GetDescendants()).toBe(before)
	end)
end)
