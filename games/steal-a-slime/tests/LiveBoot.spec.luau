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
	it("gives every spawn exactly one non-droppable, collision-free Bat; a swing at nothing is harmless", function()
		local player = rt.players[1]
		local function bats(): { any }
			local found = {}
			for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
				for _, child in container:GetChildren() do
					if child.Name == "Bat" then
						table.insert(found, child)
					end
				end
			end
			return found
		end
		local before = #rt.errors
		expect(#bats()).toBe(1)
		local bat = bats()[1]
		expect(bat.ClassName).toBe("Tool")
		expect(bat.CanBeDropped).toBe(false)
		local handle = bat:FindFirstChild("Handle")
		expect(handle ~= nil).toBe(true)
		expect(handle.CanCollide).toBe(false)
		expect(handle.CanTouch).toBe(false)
		expect(handle.CanQuery).toBe(false)
		Runtime.signalOf(bat, "Activated"):Fire() -- nobody to hit
		rt:advance(0.5)
		-- Respawn: the CharacterAdded give replaces, never duplicates.
		local character = player.Character
		Runtime.signalOf(player, "CharacterAdded"):Fire(character)
		rt:advance(0.5)
		expect(#bats()).toBe(1)
		expect(#rt.errors).toBe(before)
	end)
	it("places the shop stands, LeaderboardBoard and TutorialNpc", function()
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
	it("one ShopPrompt on each shop stand, one 'Talk' prompt on the Guide NPC", function()
		local prompts = {}
		for _, d in rt.workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				local model = d:FindFirstAncestorWhichIsA("Model")
				local owner = if model then model.Name else "?"
				prompts[owner] = prompts[owner] or {}
				table.insert(prompts[owner], d)
			end
		end
		local guide = prompts[Constants.TUTORIAL_NPC] or {}
		-- CONTRACT.md §27.3: one ShopPrompt on each stand's Counter
		local rows: { any } = {
			{ Constants.SHOP_STAND_ITEM, "ItemShop", "Item Shop", "Browse items" },
			{ Constants.SHOP_STAND_UPGRADE, "UpgradeShop", "Upgrade Shop", "Browse upgrades" },
		}
		for _, row in rows do
			local name, shopId, objectText, actionText = row[1], row[2], row[3], row[4]
			local shop = prompts[name] or {}
			expect(#shop).toBe(1)
			expect(shop[1].Name).toBe(Constants.SHOP_PROMPT_NAME)
			expect(shop[1].ObjectText).toBe(objectText)
			expect(shop[1].ActionText).toBe(actionText)
			expect(shop[1].HoldDuration).toBe(0)
			expect(shop[1].MaxActivationDistance).toBe(12)
			expect(shop[1].KeyboardKeyCode.Name).toBe("E")
			expect(shop[1].Parent.Name).toBe("Counter")
			expect(shop[1].Parent.Parent:GetAttribute(Constants.SHOP_ID_ATTRIBUTE)).toBe(shopId)
		end
		expect(#guide).toBe(1)
		expect(guide[1].Name).toBe(Constants.GUIDE_PROMPT_NAME)
		expect(guide[1].ActionText).toBe("Talk")
	end)
	it("gives Professor Goo a View leaderboards prompt and a ClickDetector", function()
		local professor = rt.workspace.Map:FindFirstChild(Constants.PROFESSOR_GOO)
		expect(professor ~= nil).toBe(true)
		local prompt = professor:FindFirstChild(Constants.LEADERBOARD_PROMPT_NAME, true)
		expect(prompt ~= nil and prompt.ClassName).toBe("ProximityPrompt")
		expect(prompt.ActionText).toBe("View leaderboards")
		expect(prompt.KeyboardKeyCode.Name).toBe("E")
		local click = professor:FindFirstChild(Constants.LEADERBOARD_CLICK_NAME)
		expect(click ~= nil and click.ClassName).toBe("ClickDetector")
	end)
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
