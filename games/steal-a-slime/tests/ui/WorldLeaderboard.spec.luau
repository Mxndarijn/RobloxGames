--!strict
-- In-world leaderboard matching + row sync (src/ui/WorldLeaderboard.luau).
local StaticWorld = require("../../scripts/StaticWorld")
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
	it("shows my own line only when I am not in the top 10", function()
		local rows = WorldLeaderboard.rows(board, 20)
		expect(WorldLeaderboard.youText(rows, "TotalEarned", 1500)).toBeNil() -- user 20 is on the board
		local others = WorldLeaderboard.rows(board, 99)
		expect(WorldLeaderboard.youText(others, "TotalEarned", 1500)).toBe("$1.5K")
		expect(WorldLeaderboard.youText(others, "Merges", 1500)).toBe("1.5K")
		expect(WorldLeaderboard.youText(others, "Merges", nil)).toBeNil()
	end)
	it("labels my line with my rank", function()
		expect(WorldLeaderboard.youLabel(48)).toBe("You #48")
		expect(WorldLeaderboard.youLabel(-1000)).toBe("You #1000+")
		expect(WorldLeaderboard.youLabel(nil)).toBe("You")
	end)
	it("survives bad payloads", function()
		expect(#WorldLeaderboard.rows(nil, 1)).toBe(0)
		expect(#WorldLeaderboard.rows({ entries = "x" }, 1)).toBe(0)
		local rows = WorldLeaderboard.rows({ stat = "TotalEarned", entries = { { rank = 1 }, "junk" } }, 1)
		expect(#rows).toBe(1)
		expect(rows[1].name).toBe("?")
		expect(rows[1].value).toBe("$0")
		expect(WorldLeaderboard.rows({ entries = { { rank = 1 } } }, 1)[1].value).toBe("0") -- no stat: a plain count
	end)
end)

-- B2 (2026-10-18): the list is drawn straight on the board skin's warm cream face, no backing panel.
local function luminance(c: { number }): number
	local function lin(v: number): number
		v /= 255
		return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end

local function contrast(a: { number }, b: { number }): number
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

describe("Top Earners board palette (B2)", function()
	local Props = StaticWorld.visual("Props")
	local palette = WorldLeaderboard.PALETTE

	it("is the same palette the server-built board uses", function()
		for _, key in { "RowAlt", "Me", "Text", "Muted", "Value" } do
			expect(table.concat((palette :: any)[key], ",")).toBe(table.concat((Props.BOARD_PALETTE :: any)[key], ","))
		end
		for i = 1, 3 do
			expect(table.concat(palette.Rank[i], ",")).toBe(table.concat(Props.BOARD_PALETTE.Rank[i], ","))
		end
	end)

	it("tints the top three cards in their rank colour, mine mint, the rest plain", function()
		local fill, edge = WorldLeaderboard.rowStyle(1, false)
		expect(table.concat(fill, ",")).toBe("77,61,19")
		expect(edge).toBe(palette.Rank[1])
		expect(WorldLeaderboard.MEDAL_TINT).toBe(Props.MEDAL_TINT)
		local mine, mineEdge = WorldLeaderboard.rowStyle(2, true)
		expect(mine).toBe(palette.Me)
		expect(mineEdge).toBe(palette.Value)
		local plain, none = WorldLeaderboard.rowStyle(7, false)
		expect(plain).toBe(palette.RowAlt)
		expect(none).toBeNil()
	end)

	it("reads at 4.5:1 or better on the dark face, every row card and my row", function()
		local face = Props.BOARD_PALETTE.Face
		local inks = { "Text", "Value" }
		local cards = { face, palette.RowAlt, palette.Me }
		for rank = 1, 3 do
			table.insert(cards, (WorldLeaderboard.rowStyle(rank, false)))
		end
		for _, key in inks do
			for _, bg in cards do
				local ratio = contrast((palette :: any)[key], bg)
				if ratio < 4.5 then
					error(`{key} on {table.concat(bg, ",")} is only {ratio}:1`)
				end
			end
		end
		-- Muted (#8A6A4A, the large no-entries text, mockup b2_board_palette) only sits on the face: 3:1 large-text bar
		expect(contrast(palette.Muted, face) >= 3).toBe(true)
		for i = 1, 3 do
			for _, bg in { face, palette.RowAlt, palette.Me } do
				local ratio = contrast(palette.Rank[i], bg)
				-- the mockup's rank colours are bold large text: #1 #8A5800 on the tan stripe is 4.41:1
				if ratio < 4 then
					error(`rank {i} on {table.concat(bg, ",")} is only {ratio}:1`)
				end
			end
		end
		expect(contrast({ 255, 255, 255 }, Props.BOARD_PALETTE.Title) >= 4.5).toBe(true) -- white title on the bar
	end)
end)
