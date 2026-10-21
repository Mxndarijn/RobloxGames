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
	it("caps offline income", function()
		expect(Config.OFFLINE_CAP_SECONDS > 0).toBeTruthy()
		expect(Config.OFFLINE_RATE > 0 and Config.OFFLINE_RATE <= 1).toBeTruthy()
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
