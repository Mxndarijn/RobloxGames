--!strict
-- Guards CONTRACT.md: remote definitions, Request actions and design values.
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local Remotes = require("../src/shared/Remotes")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Remotes", function()
	it("has unique names with a known class and direction", function()
		local seen = {}
		for _, def in Remotes.DEFINITIONS do
			expect(seen[def.name]).toBeNil()
			seen[def.name] = true
			expect(def.class == "RemoteEvent" or def.class == "RemoteFunction").toBeTruthy()
			expect(def.direction == "ClientToServer" or def.direction == "ServerToClient").toBeTruthy()
		end
	end)
	it("defines Request as a client->server RemoteFunction", function()
		local def = Remotes.definition(Constants.REQUEST)
		expect(def and def.class).toBe("RemoteFunction")
		expect(def and def.direction).toBe("ClientToServer")
	end)
	it("defines State, Notify and Leaderboard as server->client events", function()
		for _, name in { Constants.STATE, Constants.NOTIFY, "Leaderboard" } do
			local def = Remotes.definition(name)
			expect(def and def.class).toBe("RemoteEvent")
			expect(def and def.direction).toBe("ServerToClient")
		end
	end)
	it("has a rate limit for every action except Sync", function()
		for action in Remotes.ACTIONS do
			if action ~= "Sync" then
				expect(Validate.ACTIONS[action] ~= nil).toBeTruthy()
			end
		end
		for action in Validate.ACTIONS do
			expect(Remotes.ACTIONS[action] ~= nil).toBeTruthy()
		end
	end)
end)

describe("Config matches the design", function()
	it("locks for 45 s on join, 60 s per button press, +10 s per rebirth", function()
		expect(Config.JOIN_LOCK_SECONDS).toBe(45)
		expect(Config.LOCK_SECONDS).toBe(60)
		expect(Config.LOCK_SECONDS_PER_REBIRTH).toBe(10)
	end)
	it("gives escape timers between 15 and 25 s, shorter for rarer slimes", function()
		local last = math.huge
		for _, rarity in Config.RARITIES do
			expect(rarity.escapeTime >= 15 and rarity.escapeTime <= 25).toBeTruthy()
			expect(rarity.escapeTime <= last).toBeTruthy()
			last = rarity.escapeTime
		end
	end)
	it("keeps the original mutation ids and adds Rainbow, Crystal, Eclipse in multiplier order", function()
		local names = {}
		for _, m in Config.MUTATIONS do
			table.insert(names, m.name)
		end
		expect(names).toEqual({ "Glow", "Lava", "Galaxy", "Rainbow", "Gold", "Crystal", "Eclipse" })
	end)
	it("runs Slime Rain hourly for 3 minutes on 8 pads", function()
		expect(Config.RAIN_INTERVAL).toBe(3600)
		expect(Config.RAIN_DURATION).toBe(180)
		expect(Config.PADS_MAX).toBe(8)
	end)
	it("caps offline income", function()
		expect(Config.OFFLINE_CAP_SECONDS > 0).toBeTruthy()
		expect(Config.OFFLINE_RATE > 0 and Config.OFFLINE_RATE <= 1).toBeTruthy()
	end)
end)

describe("Instance attributes", function()
	it("names the GrabPrompt owner-hide attribute (CONTRACT.md §5.2)", function()
		expect(Constants.PROMPT_HIDE_ATTRIBUTE).toBe("HideFromUserId")
	end)
	it("names the slime prompt GrabPrompt, as src/ui PromptHide expects", function()
		expect(Constants.GRAB_PROMPT_NAME).toBe("GrabPrompt")
	end)
	it("names the server status attributes (CONTRACT.md §2)", function()
		expect(Constants.DATASTORE_STATUS_ATTRIBUTE).toBe("DataStoreStatus")
		expect(Constants.SLIME_LOOK_ATTRIBUTE).toBe("SlimeLook")
	end)
end)

describe("UI gaps closed (docs/archive/UI-CONTRACT-GAPS.md)", function()
	it("has a Request action for every ShopCatalog item", function()
		local ShopCatalog = require("../src/ui/ShopCatalog")
		for _, item in ShopCatalog.ITEMS do
			expect(Remotes.ACTIONS[item.action] ~= nil).toBeTruthy()
		end
	end)
	it("names the rain attributes the HUD reads", function()
		local RainTimer = require("../src/ui/RainTimer")
		expect({
			Constants.RAIN_ACTIVE_ATTRIBUTE,
			Constants.RAIN_ENDS_AT_ATTRIBUTE,
			Constants.RAIN_NEXT_AT_ATTRIBUTE,
		}).toEqual(RainTimer.ATTRIBUTES)
	end)
	it("names the props, the tool and the player attributes", function()
		expect(Constants.SHOP_STAND).toBe("ShopStand")
		expect(Constants.LEADERBOARD_BOARD).toBe("LeaderboardBoard")
		expect(Constants.TUTORIAL_NPC).toBe("TutorialNpc")
		expect(Constants.SPEED_COIL_TOOL).toBe("SpeedCoil")
		expect(Constants.TUTORIAL_STEP_ATTRIBUTE).toBe("TutorialStep")
		expect(Constants.SPEED_COIL_ATTRIBUTE).toBe("SpeedCoil")
	end)
	it("names the plot attributes Archer's PlotDecor reads (CONTRACT.md §8.4)", function()
		local source = (require("@lune/fs") :: any).readFile("src/visuals/shared/PlotDecor.luau")
		for _, name in
			{
				Constants.PLOT_DEX_COUNT_ATTRIBUTE,
				Constants.PLOT_DEX_TOTAL_ATTRIBUTE,
				Constants.PLOT_DEX_TIER_MASK_ATTRIBUTE,
			}
		do
			expect(string.find(source, `"{name}"`, 1, true) ~= nil).toBe(true)
		end
	end)
end)
