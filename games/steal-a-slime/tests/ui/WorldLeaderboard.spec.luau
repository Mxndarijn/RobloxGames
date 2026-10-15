--!strict
-- In-world leaderboard matching + row sync (src/ui/WorldLeaderboard.luau).
local TestRunner = require("../TestRunner")
local WorldLeaderboard = require("../../src/ui/WorldLeaderboard")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("WorldLeaderboard.matches", function()
	it("binds SurfaceGuis named Leaderboard or inside a leaderboard model", function()
		expect(WorldLeaderboard.matches("SurfaceGui", "Leaderboard", nil)).toBe(true)
		expect(WorldLeaderboard.matches("SurfaceGui", "BoardGui", "LeaderboardBoard")).toBe(true)
		expect(WorldLeaderboard.matches("SurfaceGui", "Gui", "Leaderboard")).toBe(true)
	end)
	it("ignores other guis and classes", function()
		expect(WorldLeaderboard.matches("SurfaceGui", "BoardGui", "ShopStand")).toBe(false)
		expect(WorldLeaderboard.matches("SurfaceGui", "Sign", nil)).toBe(false)
		expect(WorldLeaderboard.matches("BillboardGui", "Leaderboard", nil)).toBe(false)
	end)
end)

describe("WorldLeaderboard.rows", function()
	local board = {
		stat = "TotalEarned",
		entries = {
			{ rank = 2, userId = 20, name = "Bo", value = 1500 },
			{ rank = 1, userId = 10, name = "Al", value = 2500000 },
			{ rank = 3, userId = 30, name = "Cy", value = 12 },
		},
	}
	it("sorts by rank, formats cash and flags the local player", function()
		local rows = WorldLeaderboard.rows(board, 20)
		expect(#rows).toBe(3)
		expect(rows[1].name).toBe("Al")
		expect(rows[1].value).toBe("$2.5M")
		expect(rows[2].isMe).toBe(true)
		expect(rows[1].isMe).toBe(false)
	end)
	it("caps the row count", function()
		expect(#WorldLeaderboard.rows(board, nil, 2)).toBe(2)
		local many = { entries = {} }
		for i = 1, 25 do
			table.insert(many.entries, { rank = i, userId = i, name = `P{i}`, value = i })
		end
		expect(#WorldLeaderboard.rows(many, nil)).toBe(WorldLeaderboard.MAX_ROWS)
	end)
	it("survives bad payloads", function()
		expect(#WorldLeaderboard.rows(nil, 1)).toBe(0)
		expect(#WorldLeaderboard.rows({ entries = "x" }, 1)).toBe(0)
		local rows = WorldLeaderboard.rows({ entries = { { rank = 1 }, "junk" } }, 1)
		expect(#rows).toBe(1)
		expect(rows[1].name).toBe("?")
		expect(rows[1].value).toBe("$0")
	end)
end)
