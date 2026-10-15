--!nocheck
-- Headless boot of the REAL server Script: builds the place with Rojo, runs
-- ServerScriptService.Server from the place file in tools/livetest/Runtime
-- (fake clock, stubbed engine services) for 30 s of server time and checks
-- what a player would see: no script errors, world props, wild slimes, then
-- joins one fake player and checks the plot Signs.
-- The pure-module specs can't catch this class of bug: under Lune `script` is
-- nil, so every `if script then require(script...)` Roblox path goes untested.
local fs = require("@lune/fs")
local process = require("@lune/process")

local Checks = require("../tools/livetest/Checks")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-liveboot-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {})
fs.removeFile(path)
rt:boot()
rt:advance(30)
local slimes = Checks.wildSlimes(rt, 1)
local freeSigns = Checks.plotSigns(rt, nil)
rt:addPlayer(1001, "Merijn")
rt:advance(2)
local ownerSigns = Checks.plotSigns(rt, "Merijn")

local function show(check)
	if not check.ok then
		print(`    {check.detail}`)
	end
end

describe("LiveBoot (server Script in the fake runtime)", function()
	it("boots without script errors", function()
		local check = Checks.noErrors(rt)
		show(check)
		expect(#rt.errors).toBe(0)
	end)
	it("places the ShopStand, LeaderboardBoard and TutorialNpc", function()
		local check = Checks.props(rt)
		show(check)
		expect(check.ok).toBe(true)
	end)
	it("drops wild slimes from the fountain within 30 s", function()
		show(slimes)
		expect(slimes.ok).toBe(true)
	end)
	it("keeps wild slimes on the ground", function()
		local check = Checks.slimePlacement(rt)
		show(check)
		expect(check.ok).toBe(true)
	end)
	it("labels every free plot Sign (no blank boards)", function()
		show(freeSigns)
		expect(freeSigns.ok).toBe(true)
	end)
	it("writes the owner's name on their plot Sign after joining", function()
		show(ownerSigns)
		expect(ownerSigns.ok).toBe(true)
	end)
end)
