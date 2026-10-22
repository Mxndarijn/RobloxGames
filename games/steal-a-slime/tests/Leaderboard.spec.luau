--!strict
local Config = require("../src/shared/Config")
local Leaderboard = require("../src/server/Leaderboard")
local Leaderboards = require("../src/shared/Leaderboards")
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
		expect(Leaderboard.storeValue("TotalEarned", data, 1)).toBe(0)
		data.totalEarned = math.huge
		expect(Leaderboard.storeValue("TotalEarned", data, 1)).toBe(Leaderboard.MAX_VALUE)
	end)
	it("stores totalEarned as a clamped integer", function()
		local data = PlayerData.new()
		data.totalEarned = 10.9
		expect(Leaderboard.storeValue("TotalEarned", data, 1)).toBe(10)
		data.totalEarned = 1e300
		expect(Leaderboard.storeValue("TotalEarned", data, 1)).toBe(Leaderboard.MAX_VALUE)
	end)
	it("stores each board's own stat", function()
		local data = PlayerData.new()
		data.totalEarned = 900
		data.totalStolen = 7
		data.stats.merges = 12
		data.found = {}
		expect(Leaderboard.storeValue("Steals", data, 1)).toBe(7)
		expect(Leaderboard.storeValue("Merges", data, 1)).toBe(12)
		expect(Leaderboard.storeValue("Dex", data, 1)).toBe(PlayerData.dexCount(data))
	end)
	it("counts weekly earnings from the start of the week only", function()
		local data = PlayerData.new()
		data.totalEarned = 1000
		Leaderboards.rollWeek(data, 50)
		expect(Leaderboard.storeValue("WeeklyEarned", data, 50)).toBe(0)
		data.totalEarned = 1250
		expect(Leaderboard.storeValue("WeeklyEarned", data, 50)).toBe(250)
		expect(Leaderboard.storeValue("WeeklyEarned", data, 51)).toBe(0) -- not seen in week 51 yet
		Leaderboards.rollWeek(data, 51)
		data.totalEarned = 1300
		expect(Leaderboard.storeValue("WeeklyEarned", data, 51)).toBe(50)
		Leaderboards.rollWeek(data, 51) -- the same week keeps its start
		expect(Leaderboard.storeValue("WeeklyEarned", data, 51)).toBe(50)
	end)
	it("writes the board only after a save that went through, and only when the value moved", function()
		expect(Leaderboard.shouldWrite(true, false, nil, 10)).toBe(true)
		expect(Leaderboard.shouldWrite(true, false, 5, 10)).toBe(true)
		expect(Leaderboard.shouldWrite(true, false, 10, 10)).toBe(false) -- unchanged autosave
		expect(Leaderboard.shouldWrite(false, false, nil, 10)).toBe(false) -- failed or lost-session save
		expect(Leaderboard.shouldWrite(true, true, nil, 10)).toBe(false) -- read-only session
	end)
	it("builds ranked entries from a sorted page, skipping junk keys", function()
		local board = Leaderboard.fromPage({
			{ key = "u_10", value = 500 },
			{ key = "garbage", value = 400 },
			{ key = "u_20", value = 300 },
			"nope",
		}, nameOf, "Steals")
		expect(board.stat).toBe("Steals")
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
		expect(#Leaderboard.fromPage(page, nameOf, "TotalEarned").entries).toBe(Config.LEADERBOARD_SIZE)
	end)
	it("memory mode ranks live sessions by the board's stat", function()
		local a, b = PlayerData.new(), PlayerData.new()
		a.totalEarned, b.totalEarned = 5, 50
		a.totalStolen, b.totalStolen = 9, 1
		local sessions = { [1] = { userId = 1, data = a }, [2] = { userId = 2, data = b } }
		local page = Leaderboard.pageFromSessions(sessions, "TotalEarned", 1)
		expect(page[1].key).toBe("u_2")
		expect(page[2].value).toBe(5)
		local steals = Leaderboard.pageFromSessions(sessions, "Steals", 1)
		expect(steals[1].key).toBe("u_1")
		expect(steals[1].value).toBe(9)
	end)
	it("formats cash boards with $ and count boards without", function()
		local cash = Leaderboard.boardRows({
			stat = "WeeklyEarned",
			entries = { { rank = 1, userId = 1, name = "A", value = 1500 } },
		})
		expect(cash[1].value).toBe("$1.5K")
		local count =
			Leaderboard.boardRows({ stat = "Merges", entries = { { rank = 1, userId = 1, name = "A", value = 1500 } } })
		expect(count[1].value).toBe("1.5K")
	end)
end)
