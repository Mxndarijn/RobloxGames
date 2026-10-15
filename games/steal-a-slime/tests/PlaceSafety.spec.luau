--!nocheck
-- Void / anchor safety of the place the server actually runs (v8 had
-- players falling into the void). `rojo build`s the real place, loads it
-- with @lune/roblox, runs ReplicatedStorage.Visuals.WorldBuilder.build into
-- its Workspace like WorldView.setup does on server start (CONTRACT.md
-- §5.3), then checks:
--   * every structural BasePart (anything not inside a Slimes / WildSlimes
--     folder) is Anchored; unanchored slime parts are only listed;
--   * Workspace has at least one SpawnLocation;
--   * each SpawnLocation, and each plot spawn (Base top + 4, see
--     WorldView.plotSpawn), has an anchored CanCollide part right below it.
-- FallbackWorld needs a live `game` with ModuleScript require, so only the
-- WorldBuilder path is covered here.
-- The place is cached at tests/.cache/PlaceSafety.rbxl (git-ignored).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Constants = require("../src/shared/Constants")
local TestRunner = require("./TestRunner")
local WorldBuilder = require("../src/visuals/shared/WorldBuilder")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local CACHE_DIR = "tests/.cache"
local PLACE_PATH = `{CACHE_DIR}/PlaceSafety.rbxl`
local SPAWN_HEIGHT = 4 -- WorldView.plotSpawn: Base top + 4
local MAX_DROP = 12 -- studs of free fall allowed from a spawn's bottom to the ground

-- Roblox globals WorldBuilder uses at call time; swapped in only while building.
local GLOBALS = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

local function withRobloxGlobals<T>(fn: () -> T): T
	local env = getfenv(WorldBuilder.build)
	local saved = {}
	for name, value in GLOBALS do
		saved[name] = env[name]
		env[name] = value
	end
	local ok, result = pcall(fn)
	for name in GLOBALS do
		env[name] = saved[name]
	end
	if not ok then
		error(result, 0)
	end
	return result
end

local function buildPlace(): any
	if not fs.isDir(CACHE_DIR) then
		fs.writeDir(CACHE_DIR)
	end
	local result = process.exec("rojo", { "build", "default.project.json", "-o", PLACE_PATH })
	if not result.ok then
		error(`rojo build failed ({result.code}): {result.stderr}`)
	end
	local game = roblox.deserializePlace(fs.readFile(PLACE_PATH))
	local workspace = game:GetService("Workspace")
	withRobloxGlobals(function()
		WorldBuilder.build(workspace)
		return nil
	end)
	return workspace
end

local placeWorkspace: any = nil
local function world(): any
	if not placeWorkspace then
		placeWorkspace = buildPlace()
	end
	return placeWorkspace
end

local function path(instance: any): string
	return instance:GetFullName()
end

-- Inside a per-plot Slimes folder or the wild slimes folder: slime models,
-- moved by the server, may legitimately carry unanchored parts.
local function isSlimePart(instance: any): boolean
	local node = instance.Parent
	while node do
		if node:IsA("Folder") and (node.Name == Constants.PLOT_SLIMES_FOLDER or node.Name == Constants.WILD_FOLDER) then
			return true
		end
		node = node.Parent
	end
	return false
end

local function baseParts(workspace: any): { any }
	local parts = {}
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Distance along a straight-down ray from `origin` to `part`'s box (slab
-- test in the part's object space), or nil if it misses. Balls / cylinders
-- are treated as their bounding box, close enough for floors.
local function rayDownHit(origin: any, part: any): number?
	local cf, half = part.CFrame, part.Size / 2
	local o = cf:PointToObjectSpace(origin)
	local d = cf:VectorToObjectSpace(roblox.Vector3.new(0, -1, 0))
	local tMin, tMax = 0, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local oa, da, h = o[axis], d[axis], half[axis]
		if math.abs(da) < 1e-9 then
			if math.abs(oa) > h then
				return nil
			end
		else
			local t1, t2 = (-h - oa) / da, (h - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin, tMax = math.max(tMin, t1), math.min(tMax, t2)
			if tMin > tMax then
				return nil
			end
		end
	end
	return tMin
end

-- First CanCollide part straight below `origin` (ignoring `ignore`), and its distance.
local function groundBelow(workspace: any, origin: any, ignore: any?): (any?, number?)
	local best, bestDistance = nil, math.huge
	for _, part in baseParts(workspace) do
		if part ~= ignore and part.CanCollide then
			local distance = rayDownHit(origin, part)
			if distance and distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best, if best then bestDistance else nil
end

-- Problem string for a spawn point whose feet are `feetDrop` studs above `origin`'s ground, or nil.
local function groundProblem(workspace: any, label: string, origin: any, feetDrop: number, ignore: any?): string?
	local ground, distance = groundBelow(workspace, origin, ignore)
	if not ground then
		return `{label}: nothing CanCollide below {origin} (void)`
	elseif not ground.Anchored then
		return `{label}: ground {path(ground)} is not Anchored`
	elseif distance - feetDrop > MAX_DROP then
		return `{label}: ground {path(ground)} is {distance - feetDrop} studs below (max {MAX_DROP})`
	end
	return nil
end

local function report(title: string, lines: { string })
	if #lines > 0 then
		warn(`[PlaceSafety] {title} ({#lines}):\n  {table.concat(lines, "\n  ")}`)
	end
end

describe("Place safety (rojo build + WorldBuilder.build)", function()
	it("builds Map and Plots into the place's Workspace", function()
		local workspace = world()
		expect(workspace:FindFirstChild(Constants.MAP_FOLDER) ~= nil).toBe(true)
		expect(workspace:FindFirstChild(Constants.PLOTS_FOLDER) ~= nil).toBe(true)
	end)

	it("anchors every structural BasePart under Workspace", function()
		local structural, slimes = {}, {}
		for _, part in baseParts(world()) do
			if not part.Anchored then
				table.insert(if isSlimePart(part) then slimes else structural, path(part))
			end
		end
		table.sort(structural)
		table.sort(slimes)
		report("unanchored slime parts (allowed)", slimes)
		report("UNANCHORED structural parts", structural)
		expect(table.concat(structural, ", ")).toBe("")
	end)

	it("has at least one SpawnLocation under Workspace", function()
		local count = 0
		for _, descendant in world():GetDescendants() do
			if descendant:IsA("SpawnLocation") then
				count += 1
			end
		end
		if count == 0 then
			report("spawn", { "no SpawnLocation under Workspace: players spawn at the engine default" })
		end
		expect(count > 0).toBe(true)
	end)

	it("puts solid anchored ground under every SpawnLocation", function()
		local workspace = world()
		local problems = {}
		for _, spawn in workspace:GetDescendants() do
			if spawn:IsA("SpawnLocation") then
				-- Look past the spawn pad itself: a floating pad is still a walk-off into the void.
				local problem = groundProblem(workspace, path(spawn), spawn.CFrame.Position, spawn.Size.Y / 2, spawn)
				if problem then
					table.insert(problems, problem)
				end
			end
		end
		report("SpawnLocation ground", problems)
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("puts solid anchored ground under every plot spawn (Base top + 4)", function()
		local workspace = world()
		local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
		local problems, checked = {}, 0
		for _, plot in if plots then plots:GetChildren() else {} do
			local base = plot:FindFirstChild("Base")
			if base and base:IsA("BasePart") then
				checked += 1
				local origin = (base.CFrame * roblox.CFrame.new(0, base.Size.Y / 2 + SPAWN_HEIGHT, 0)).Position
				local problem = groundProblem(workspace, `{path(plot)} spawn`, origin, SPAWN_HEIGHT)
				if problem then
					table.insert(problems, problem)
				end
			else
				table.insert(problems, `{path(plot)}: no Base part`)
			end
		end
		report("plot spawn ground", problems)
		expect(checked > 0).toBe(true)
		expect(table.concat(problems, "; ")).toBe("")
	end)
end)
