--!strict
local Config = require("../src/shared/Config")
local Leaderboard = require("../src/server/Leaderboard")
local PlayerData = require("../src/shared/PlayerData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function nameOf(userId: number): string
	return `N{userId}`
end

describe("Leaderboard", function()
	it("leaderstats are Cash, Rebirths and Steals", function()
		local data = PlayerData.new()
		data.cash = 12.7
		data.rebirths = 3
		data.totalStolen = 5
		expect(Leaderboard.STATS).toEqual({ "Cash", "Rebirths", "Steals" })
		expect(Leaderboard.stats(data)).toEqual({ Cash = 12, Rebirths = 3, Steals = 5 })
	end)
	it("a NaN totalEarned stores as 0", function()
		local data = PlayerData.new()
		data.totalEarned = 0 / 0
		expect(Leaderboard.storeValue(data)).toBe(0)
		data.totalEarned = math.huge
		expect(Leaderboard.storeValue(data)).toBe(Leaderboard.MAX_VALUE)
	end)
	it("stores totalEarned as a clamped integer", function()
		local data = PlayerData.new()
		data.totalEarned = 10.9
		expect(Leaderboard.storeValue(data)).toBe(10)
		data.totalEarned = 1e300
		expect(Leaderboard.storeValue(data)).toBe(Leaderboard.MAX_VALUE)
	end)
	it("builds ranked entries from a sorted page, skipping junk keys", function()
		local board = Leaderboard.fromPage({
			{ key = "u_10", value = 500 },
			{ key = "garbage", value = 400 },
			{ key = "u_20", value = 300 },
			"nope",
		}, nameOf)
		expect(board.stat).toBe("TotalEarned")
		expect(board.entries).toEqual({
			{ rank = 1, userId = 10, name = "N10", value = 500 },
			{ rank = 2, userId = 20, name = "N20", value = 300 },
		})
	end)
	it("caps the board at LEADERBOARD_SIZE", function()
		local page = {}
		for i = 1, Config.LEADERBOARD_SIZE + 5 do
			page[i] = { key = `u_{i}`, value = 1000 - i }
		end
		expect(#Leaderboard.fromPage(page, nameOf).entries).toBe(Config.LEADERBOARD_SIZE)
	end)
	it("memory mode ranks live sessions by totalEarned", function()
		local a, b = PlayerData.new(), PlayerData.new()
		a.totalEarned, b.totalEarned = 5, 50
		local page = Leaderboard.pageFromSessions({ [1] = { userId = 1, data = a }, [2] = { userId = 2, data = b } })
		expect(page[1].key).toBe("u_2")
		expect(page[2].value).toBe(5)
	end)
end)
