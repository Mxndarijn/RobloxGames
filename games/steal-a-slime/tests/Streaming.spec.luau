--!nocheck
-- StreamingEnabled: the place streams, and the real server Script (booted in tools/livetest/Runtime) marks what
-- clients need whole or always: the fountain is Persistent, every slime model is Atomic.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Checks = require("../tools/livetest/Checks")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Enum = roblox.Enum

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-streaming-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local place = roblox.deserializePlace(fs.readFile(path))
local rt = Runtime.new(path, {})
fs.removeFile(path)
rt:boot()
rt:advance(30)
rt:addPlayer(1001, "Merijn")
rt:advance(2)

describe("StreamingEnabled", function()
	it("the place streams, with the minimum radius inside the target radius", function()
		local ws = place:GetService("Workspace")
		expect(ws.StreamingEnabled).toBe(true)
		expect(ws.StreamingMinRadius < ws.StreamingTargetRadius).toBe(true)
	end)

	it("the server boots clean with streaming on and a player joined", function()
		expect(#rt.errors).toBe(0)
	end)

	it("keeps the fountain on every client (Persistent)", function()
		local volcano = rt.workspace:FindFirstChild("Map"):FindFirstChild("Volcano")
		expect(volcano.ModelStreamingMode).toBe(Enum.ModelStreamingMode.Persistent)
	end)

	it("streams every wild slime whole (Atomic)", function()
		local wild = rt.workspace:FindFirstChild(Checks.WILD_FOLDER)
		local models = 0
		local atomic = 0
		for _, model in wild:GetChildren() do
			if model:IsA("Model") then
				models += 1
				if model.ModelStreamingMode == Enum.ModelStreamingMode.Atomic then
					atomic += 1
				end
			end
		end
		expect(models > 0).toBe(true)
		expect(atomic).toBe(models)
	end)
end)
