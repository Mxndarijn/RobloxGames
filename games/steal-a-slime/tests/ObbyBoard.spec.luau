--!strict
-- The obby course board (src/server/ObbyBoard.luau, contract/obby.md §7): two servers on one shared store rank
-- everyone together, ties go to who set it first, other course code never mixes in, and the world board's text.
local Config = require("../src/shared/Config")
local ObbyBoard = require("../src/server/ObbyBoard")
local ObbyCourse = require("../src/shared/ObbyCourse")
local ObbyRules = require("../src/shared/ObbyRules")
local PeriodBoard = require("../../../shared/luau/src/ranking/PeriodBoard")
local PlayerSettings = require("../src/shared/PlayerSettings")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local BOARD = Config.OBBY.BOARD

local SLOT = ObbyCourse.slot(ServerFixtures.T0) + 1
local T = ObbyCourse.slotStart(SLOT) + 10
local COURSE = ObbyCourse.build(SLOT)

local function named(userId: number): string
	return `P{userId}`
end

-- One "server": a world with these players and its own copy of the board.
local function server(userIds: { number }): (any, ObbyBoard.State)
	local world = ServerFixtures.world(T)
	for _, userId in userIds do
		ServerFixtures.join(world, userId, nil, 0, T)
	end
	world.obby = COURSE
	local board = ObbyBoard.new("Memory", named)
	world.obbyBoard = board
	ObbyBoard.sync(board, COURSE)
	return world, board
end

-- A new best on `world` for `userId`: what ObbyService does after a counted finish.
local function best(world: any, board: ObbyBoard.State, userId: number, tenths: number, at: number): number
	local session = world.sessions[userId]
	session.obbyBest = { slot = SLOT, seconds = tenths / 10 }
	return ObbyBoard.record(board, COURSE, session, tenths, at)
end

describe("ObbyCourse.hash", function()
	it("two builds of a slot hash the same; another slot or a moved part hashes differently", function()
		local again = ObbyCourse.build(SLOT)
		expect(ObbyCourse.hash(again)).toBe(ObbyCourse.hash(COURSE))
		expect(#ObbyCourse.hash(COURSE)).toBe(8)
		expect(ObbyCourse.hash(ObbyCourse.build(SLOT + 1)) ~= ObbyCourse.hash(COURSE)).toBe(true)
		local moved = ObbyCourse.build(SLOT)
		local part = moved.parts[#moved.parts // 2]
		part.pos = { part.pos[1] + 0.05, part.pos[2], part.pos[3] }
		expect(ObbyCourse.hash(moved) ~= ObbyCourse.hash(COURSE)).toBe(true)
		local tiny = ObbyCourse.build(SLOT)
		local p = tiny.parts[1]
		p.pos = { p.pos[1] + 0.001, p.pos[2], p.pos[3] } -- under the 0.01 rounding
		expect(ObbyCourse.hash(tiny)).toBe(ObbyCourse.hash(COURSE))
	end)

	it("names the board after the slot and the hash", function()
		local _, board = server({})
		local course = board.course :: ObbyBoard.Course
		expect(course.map).toBe(`Obby_{SLOT}_{ObbyCourse.hash(COURSE)}`)
	end)
end)

describe("ObbyBoard across servers", function()
	it("two servers on one store rank everyone together, ties to who set it first", function()
		local store = PeriodBoard.memoryStore()
		local a, boardA = server({ 1, 2 })
		local b, boardB = server({ 3 })
		best(a, boardA, 1, 452, T + 30)
		best(b, boardB, 3, 452, T + 40) -- the same tenth, ten seconds later
		best(a, boardA, 2, 470, T + 50)
		expect(#ObbyBoard.flush(boardA, store, T + 60)).toBe(0)
		expect(#ObbyBoard.flush(boardB, store, T + 60)).toBe(0)
		ObbyBoard.refresh(boardA, store, a, T + 61)
		ObbyBoard.refresh(boardB, store, b, T + 61)
		for _, board in { boardA, boardB } do
			expect(#board.rows).toBe(3)
			expect(board.rows[1].userId).toBe(1)
			expect(board.rows[2].userId).toBe(3)
			expect(board.rows[3].userId).toBe(2)
		end
		expect(ObbyBoard.rank(boardB, b.sessions[3], SLOT)).toBe(2)
		local view = ObbyBoard.boardView(boardB, b, T + 61)
		expect(view.rows[1].name).toBe("P1")
		expect(view.rows[1].value).toBe("0:45.2")
		expect(view.rows[3].rank).toBe("#3")
	end)

	it("a worse time from another server never replaces a better one", function()
		local store = PeriodBoard.memoryStore()
		local a, boardA = server({ 1 })
		local b, boardB = server({ 1 }) -- the same player, after a server hop
		best(a, boardA, 1, 400, T + 20)
		ObbyBoard.flush(boardA, store, T + 30)
		best(b, boardB, 1, 480, T + 40) -- b hasn't read the board yet
		ObbyBoard.flush(boardB, store, T + 50)
		ObbyBoard.refresh(boardB, store, b, T + 51)
		expect(boardB.rows[1].score).toBe(400)
	end)

	it("servers building other course code post to their own board", function()
		local store = PeriodBoard.memoryStore()
		local a, boardA = server({ 1 })
		local b, boardB = server({ 2 })
		local course = boardB.course :: ObbyBoard.Course
		boardB.course = { slot = course.slot, hash = "00000000", map = ObbyBoard.name(course.slot, "00000000") }
		best(a, boardA, 1, 400, T + 20)
		best(b, boardB, 2, 300, T + 20)
		ObbyBoard.flush(boardA, store, T + 30)
		ObbyBoard.flush(boardB, store, T + 30)
		ObbyBoard.refresh(boardA, store, a, T + 31)
		expect(#boardA.rows).toBe(1)
		expect(boardA.rows[1].userId).toBe(1)
	end)

	it("a rejoin gets its best back from the board", function()
		local store = PeriodBoard.memoryStore()
		local a, boardA = server({ 1 })
		best(a, boardA, 1, 512, T + 20)
		ObbyBoard.flush(boardA, store, T + 30)
		local b, boardB = server({ 1 })
		expect(b.sessions[1].obbyBest).toBeNil()
		ObbyBoard.refresh(boardB, store, b, T + 31)
		expect(b.sessions[1].obbyBest.slot).toBe(SLOT)
		expect(ObbyRules.tenths(b.sessions[1].obbyBest.seconds)).toBe(512)
		expect(b.sessions[1].dirty).toBe(true)
	end)

	it("a new best shows on this server's board at once, before the next read", function()
		local a, boardA = server({ 1 })
		local version = boardA.version
		expect(best(a, boardA, 1, 600, T + 20)).toBe(1)
		expect(boardA.version > version).toBe(true)
		expect(ObbyBoard.boardView(boardA, a, T + 20).rows[1].name).toBe("P1")
	end)

	it("past the depth the board reads, the rank is #100+", function()
		local a, boardA = server({ 1 })
		local items = {}
		for k = 1, BOARD.RANK_DEPTH do
			table.insert(items, { key = PeriodBoard.key(1000 + k), value = { score = 300 + k, at = 1, name = "x" } })
		end
		boardA.rows = PeriodBoard.rows(items, BOARD.RANK_DEPTH)
		local rank = best(a, boardA, 1, 999, T + 20)
		expect(rank).toBe(BOARD.RANK_DEPTH + 1)
		expect(ObbyRules.rankText(rank)).toBe(`#{BOARD.RANK_DEPTH}+`)
		expect(ObbyBoard.rank(boardA, a.sessions[1], SLOT)).toBe(BOARD.RANK_DEPTH + 1)
	end)
end)

describe("ObbyBoard hidden players and the world board", function()
	it("a hidden player shows as Hidden player, and turning it on later updates the stored entry", function()
		local store = PeriodBoard.memoryStore()
		local a, boardA = server({ 1 })
		local session = a.sessions[1]
		best(a, boardA, 1, 400, T + 20)
		ObbyBoard.flush(boardA, store, T + 30)
		session.data.settings = { showOnBoards = false }
		-- shown hidden at once on this server, and the next read sends the change
		expect(ObbyBoard.boardView(boardA, a, T + 31).rows[1].name).toBe(PlayerSettings.HIDDEN_NAME)
		ObbyBoard.refresh(boardA, store, a, T + 31)
		expect(#boardA.pending).toBe(1)
		ObbyBoard.flush(boardA, store, T + 32)
		local other, boardB = server({})
		ObbyBoard.refresh(boardB, store, other, T + 33)
		expect(boardB.rows[1].hidden).toBe(true)
		local view = ObbyBoard.boardView(boardB, other, T + 33)
		expect(view.rows[1].name).toBe(PlayerSettings.HIDDEN_NAME)
		for _, row in view.rows do
			for _, value in row :: any do
				expect(value ~= "1").toBe(true) -- no user id in the board's text
			end
		end
	end)

	it("the course line counts down; an empty board says so; the footer has the last course's #1", function()
		local store = PeriodBoard.memoryStore()
		local a, boardA = server({ 1 })
		local view = ObbyBoard.boardView(boardA, a, T)
		local left = ObbyCourse.slotStart(SLOT + 1) - T
		expect(view.sub).toBe(
			`{ObbyRules.courseLabel(ObbyRules.courseNumber(SLOT))} · new course in {string.format(
				"%d:%02d",
				left // 60,
				left % 60
			)}`
		)
		expect(view.rows[1].name).toBe(ObbyBoard.EMPTY_TEXT)
		expect(view.footer).toBeNil()
		best(a, boardA, 1, 368, T + 20)
		ObbyBoard.flush(boardA, store, T + 21)
		local nextCourse = ObbyCourse.build(SLOT + 1)
		a.obby = nextCourse
		ObbyBoard.sync(boardA, nextCourse)
		ObbyBoard.refresh(boardA, store, a, ObbyCourse.slotStart(SLOT + 1) + 5)
		local after = ObbyBoard.boardView(boardA, a, ObbyCourse.slotStart(SLOT + 1) + 5)
		expect(after.footer).toBe("Last course: P1 0:36.8")
		expect(after.rows[1].name).toBe(ObbyBoard.EMPTY_TEXT)
	end)

	it("a failed read or write turns the status to Error and the footer to Board offline", function()
		local a, boardA = server({ 1 })
		local broken: PeriodBoard.Store = {
			update = function(_map, _key, _transform, _expiration)
				error("down")
			end,
			range = function(_map, _count)
				error("down")
			end,
		}
		best(a, boardA, 1, 400, T + 20)
		local errors = ObbyBoard.flush(boardA, broken, T + 21)
		expect(#errors).toBe(1)
		expect(boardA.status).toBe("Error")
		expect(#boardA.pending).toBe(1) -- tried again on the next flush
		expect(ObbyBoard.refresh(boardA, broken, a, T + 22)).toBe(false)
		expect(ObbyBoard.boardView(boardA, a, T + 22).footer).toBe(ObbyBoard.OFFLINE_TEXT)
		expect(boardA.rows[1].userId).toBe(1) -- the board keeps its last rows
		local store = PeriodBoard.memoryStore()
		expect(#ObbyBoard.flush(boardA, store, T + 23)).toBe(0)
		ObbyBoard.refresh(boardA, store, a, T + 24)
		expect(boardA.status).toBe("Memory")
		expect(boardA.rows[1].userId).toBe(1)
	end)
end)
