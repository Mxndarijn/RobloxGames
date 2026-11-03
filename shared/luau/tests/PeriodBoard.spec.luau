--!strict
local PeriodBoard = require("../src/ranking/PeriodBoard")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function entry(score: number, at: number, name: string?, hidden: boolean?): PeriodBoard.Entry
	return { score = score, at = at, name = name or "P", hidden = hidden == true }
end

-- A clock the specs move by hand.
local function clock(): ({ t: number }, () -> number)
	local c = { t = 1000 }
	return c, function()
		return c.t
	end
end

describe("PeriodBoard keys and names", function()
	it("round-trips a user id through its key and rejects other shapes", function()
		expect(PeriodBoard.key(42)).toBe("u_42")
		expect(PeriodBoard.userIdOf("u_42")).toBe(42)
		expect(PeriodBoard.userIdOf("u_")).toBe(nil)
		expect(PeriodBoard.userIdOf("h_42")).toBe(nil)
		expect(PeriodBoard.userIdOf(42)).toBe(nil)
	end)

	it("names one board per period, with an optional tag", function()
		expect(PeriodBoard.mapName("Obby", 981204, "1a2b3c4d")).toBe("Obby_981204_1a2b3c4d")
		expect(PeriodBoard.mapName("Obby", 981204.9)).toBe("Obby_981204")
	end)
end)

describe("PeriodBoard entries", function()
	it("cleans stored values: whole numbers, a capped name, junk -> nil", function()
		local e = PeriodBoard.clean({ score = 423.7, at = 61.2, name = string.rep("a", 60), hidden = true }) :: any
		expect(e.score).toBe(423)
		expect(e.at).toBe(61)
		expect(#e.name).toBe(PeriodBoard.MAX_NAME)
		expect(e.hidden).toBe(true)
		expect(PeriodBoard.clean({ score = -1, at = 0 })).toBe(nil)
		expect(PeriodBoard.clean({ score = 0 / 0, at = 0 })).toBe(nil)
		expect(PeriodBoard.clean({ score = 5, at = PeriodBoard.TIE_RANGE })).toBe(nil)
		expect(PeriodBoard.clean("x")).toBe(nil)
	end)

	it("sorts by score, then by who set it first", function()
		expect(PeriodBoard.sortKey(entry(423, 61))).toBe(423 * PeriodBoard.TIE_RANGE + 61)
		expect(PeriodBoard.beats(entry(400, 90), entry(401, 10))).toBe(true)
		expect(PeriodBoard.beats(entry(400, 10), entry(400, 90))).toBe(true)
		expect(PeriodBoard.beats(entry(400, 90), entry(400, 10))).toBe(false)
		expect(PeriodBoard.beats(entry(400, 10), nil)).toBe(true)
	end)

	it("the write keeps the better entry and refreshes the same run's name or hidden flag", function()
		local write = PeriodBoard.transform(entry(400, 50, "Mila"))
		local value, sortKey = write(nil, nil)
		expect((value :: any).score).toBe(400)
		expect(sortKey).toBe(400 * PeriodBoard.TIE_RANGE + 50)
		expect(write({ score = 390, at = 70, name = "Mila", hidden = false }, nil)).toBe(nil) -- a better time stays
		expect((write({ score = 410, at = 20, name = "Mila", hidden = false }, nil) :: any).score).toBe(400)
		expect(write({ score = 400, at = 50, name = "Mila", hidden = false }, nil)).toBe(nil) -- nothing changed
		local hide = PeriodBoard.transform(entry(400, 50, "Mila", true))
		expect((hide({ score = 400, at = 50, name = "Mila", hidden = false }, nil) :: any).hidden).toBe(true)
		expect(PeriodBoard.transform({ score = -3, at = 0, name = "", hidden = false } :: any)(nil, nil)).toBe(nil)
	end)
end)

describe("PeriodBoard rows", function()
	it("ranks store items best first, skips junk and lists a player once", function()
		local rows = PeriodBoard.rows({
			{ key = "u_2", value = entry(500, 1, "B") },
			{ key = "u_1", value = entry(400, 9, "A") },
			{ key = "bad", value = entry(1, 1) },
			{ key = "u_3", value = "junk" },
			{ key = "u_1", value = entry(450, 1, "A") },
		})
		expect(#rows).toBe(2)
		expect(rows[1].userId).toBe(1)
		expect(rows[1].score).toBe(400)
		expect(rows[1].rank).toBe(1)
		expect(rows[2].rank).toBe(2)
		expect(PeriodBoard.rankOf(rows, 2)).toBe(2)
		expect(PeriodBoard.rankOf(rows, 9)).toBe(nil)
	end)

	it("places a write on a local copy: better replaces, worse keeps, past the depth has no rank", function()
		local rows =
			PeriodBoard.rows({ { key = "u_1", value = entry(400, 9) }, { key = "u_2", value = entry(500, 1) } })
		local better, rank = PeriodBoard.place(rows, 2, entry(300, 20), 10)
		expect(rank).toBe(1)
		expect(better[2].userId).toBe(1)
		expect(rows[1].userId).toBe(1) -- the input list is left alone
		local same, kept = PeriodBoard.place(rows, 1, entry(450, 30), 10)
		expect(kept).toBe(1)
		expect(same[1].score).toBe(400)
		local _, none = PeriodBoard.place(rows, 3, entry(900, 1), 2)
		expect(none).toBe(nil)
	end)
end)

describe("PeriodBoard on a shared store", function()
	it("two servers on one store rank everyone together; ties go to who set it first", function()
		local c, now = clock()
		local store = PeriodBoard.memoryStore(now)
		local map = PeriodBoard.mapName("Obby", 7, "aa")
		-- server A posts for player 1, server B for players 2 and 3 (3 ties with 1 later)
		expect(PeriodBoard.post(store, map, 1, entry(420, 30, "One"), { expiration = 60 })).toBe(true)
		expect(PeriodBoard.post(store, map, 2, entry(410, 40, "Two"), { expiration = 60 })).toBe(true)
		expect(PeriodBoard.post(store, map, 3, entry(420, 50, "Three"), { expiration = 60 })).toBe(true)
		local rows = PeriodBoard.read(store, map, 10) :: { PeriodBoard.Row }
		expect(#rows).toBe(3)
		expect(rows[1].name).toBe("Two")
		expect(rows[2].name).toBe("One")
		expect(rows[3].name).toBe("Three")
		-- a worse time from another server never overwrites a better one
		PeriodBoard.post(store, map, 2, entry(480, 55, "Two"), { expiration = 60 })
		expect((PeriodBoard.read(store, map, 10) :: any)[1].score).toBe(410)
		-- the board goes away after its expiry
		c.t += 61
		expect(#(PeriodBoard.read(store, map, 10) :: any)).toBe(0)
	end)

	it("boards with another tag never mix", function()
		local store = PeriodBoard.memoryStore()
		PeriodBoard.post(store, PeriodBoard.mapName("Obby", 7, "aa"), 1, entry(420, 30), { expiration = 60 })
		PeriodBoard.post(store, PeriodBoard.mapName("Obby", 7, "bb"), 2, entry(410, 30), { expiration = 60 })
		local rows = PeriodBoard.read(store, PeriodBoard.mapName("Obby", 7, "aa"), 10) :: any
		expect(#rows).toBe(1)
		expect(rows[1].userId).toBe(1)
	end)

	it("retries a failing write with the injected waits, and reports the error once every try failed", function()
		local fails = 2
		local waits = {}
		local inner = PeriodBoard.memoryStore()
		local flaky: PeriodBoard.Store = {
			update = function(map, key, transform, expiration)
				if fails > 0 then
					fails -= 1
					error("busy")
				end
				return inner.update(map, key, transform, expiration)
			end,
			range = inner.range,
		}
		local wait = function(s: number)
			table.insert(waits, s)
		end
		expect(PeriodBoard.post(flaky, "m", 1, entry(1, 1), { expiration = 60, wait = wait })).toBe(true)
		expect(#waits).toBe(2)
		fails = 10
		local ok, reason = PeriodBoard.post(flaky, "m", 1, entry(1, 1), { expiration = 60, wait = wait })
		expect(ok).toBe(false)
		expect(string.find(reason :: string, "busy", 1, true) ~= nil).toBe(true)
		local broken: PeriodBoard.Store = {
			update = inner.update,
			range = function(_map, _count)
				error("down")
			end,
		}
		local rows, err = PeriodBoard.read(broken, "m", 10)
		expect(rows).toBe(nil)
		expect(string.find(err :: string, "down", 1, true) ~= nil).toBe(true)
	end)
end)
