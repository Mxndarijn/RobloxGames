--!strict
-- Void fix proof: builds the place with Rojo and runs scripts/PlaceCheck on it
-- (static floor, anchored world, SpawnLocation on solid ground, WorldLayout match).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local PlaceCheck = require("../scripts/PlaceCheck")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function buildPlace(): any
	local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-staticworld-{os.time()}.rbxlx`
	local result = process.exec("rojo", { "build", "-o", path })
	assert(result.ok, `rojo build failed: {result.stderr}`)
	local game = PlaceCheck.load(path)
	fs.removeFile(path)
	return game
end

local game = buildPlace()

describe("StaticWorld (built place)", function()
	it("passes every PlaceCheck", function()
		local failures = PlaceCheck.run(game)
		for _, failure in failures do
			print(`    {failure}`)
		end
		expect(#failures).toBe(0)
	end)
	it("ships the hub SpawnLocation, Map and Plots in Workspace", function()
		local workspace = game:GetService("Workspace")
		local spawn = workspace:FindFirstChild(StaticWorld.SPAWN_NAME)
		expect(spawn and spawn.ClassName).toBe("SpawnLocation")
		expect(workspace:FindFirstChild("Map") ~= nil).toBeTruthy()
		expect(workspace:FindFirstChild("Plots") ~= nil).toBeTruthy()
	end)
	it("flags an unanchored world part and a missing SpawnLocation", function()
		local workspace = game:GetService("Workspace")
		local ground = workspace.Map.Ground
		local spawn = workspace:FindFirstChild(StaticWorld.SPAWN_NAME)
		ground.Anchored = false
		spawn.Parent = nil
		local failures = table.concat(PlaceCheck.run(game), "\n")
		ground.Anchored = true
		spawn.Parent = workspace
		expect(string.find(failures, "unanchored", 1, true) ~= nil).toBeTruthy()
		expect(string.find(failures, "no SpawnLocation", 1, true) ~= nil).toBeTruthy()
	end)
	it("ignores unanchored slime parts", function()
		local slimes = game:GetService("Workspace").Plots.Plot_1.Slimes
		local part = roblox.Instance.new("Part")
		part.Anchored = false
		part.Parent = slimes
		local failures = PlaceCheck.run(game)
		part.Parent = nil
		expect(#failures).toBe(0)
	end)
end)

describe("StaticWorld (generator)", function()
	it("matches the committed world/*.rbxmx (rerun lune run scripts/gen-world)", function()
		for _, instance in StaticWorld.build() do
			local committed = fs.readFile(`world/{instance.Name}.rbxmx`)
			expect(roblox.serializeModel({ instance }, true) == committed).toBeTruthy()
		end
	end)
end)
