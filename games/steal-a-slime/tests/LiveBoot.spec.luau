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
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local Habitats = require("../src/shared/Habitats")
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
	it("has no BuyStand and no ClaimPrompt anywhere in the live world (C6 v30)", function()
		local bad = {}
		for _, d in rt.workspace:GetDescendants() do
			if d.Name == "BuyStand" or d.Name == "ClaimPrompt" then
				table.insert(bad, d:GetFullName())
			end
		end
		expect(#bad).toBe(0)
	end)
	it(
		"v28: one 'Open Shop' prompt on the ShopStand, one 'Talk' prompt on the Guide NPC, no per-item prompts",
		function()
			local prompts = {}
			for _, d in rt.workspace:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					local model = d:FindFirstAncestorWhichIsA("Model")
					local owner = if model then model.Name else "?"
					prompts[owner] = prompts[owner] or {}
					table.insert(prompts[owner], d)
				end
			end
			local shop = prompts[Constants.SHOP_STAND] or {}
			local guide = prompts[Constants.TUTORIAL_NPC] or {}
			expect(#shop).toBe(1)
			expect(shop[1].Name).toBe(Constants.SHOP_PROMPT_NAME)
			expect(shop[1].ActionText).toBe("Open Shop")
			expect(shop[1].KeyboardKeyCode.Name).toBe("E")
			expect(#guide).toBe(1)
			expect(guide[1].Name).toBe(Constants.GUIDE_PROMPT_NAME)
			expect(guide[1].ActionText).toBe("Talk")
			for _, d in rt.workspace:GetDescendants() do
				expect(string.find(d.Name, "ShopPrompt_", 1, true)).toBeNil()
			end
		end
	)
	it("with FEATURES.Habitats on, every pad carries a known habitat id and the server builds no looks", function()
		local found = {}
		local pads = 0
		for _, d in rt.workspace:GetDescendants() do
			local id = d:GetAttribute("Habitat")
			if id ~= nil then
				pads += 1
				if Habitats.resolve(id) ~= id then
					table.insert(found, `{d:GetFullName()}.Habitat={tostring(id)}`)
				end
			end
			if d.Name == "ClientHabitats" or d.Name == "HabitatBurst" then
				table.insert(found, d:GetFullName())
			end
		end
		if #found > 0 then
			print(`    {table.concat(found, ", ")}`)
		end
		expect(Config.FEATURES.Habitats).toBe(true)
		expect(pads > 0).toBe(true)
		expect(#found).toBe(0)
	end)
end)
